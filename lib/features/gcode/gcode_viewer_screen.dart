import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/api/endpoints.dart';
import '../../core/settings/server_profile.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/state_views.dart';

/// Full-screen 3D G-code viewer. Embeds hosted PrettyGCode page
/// (`<baseUrl>/gcode-viewer/`) in WebView.
///
/// Page authenticates its API calls with `Bearer` token from `localStorage.auth_token`.
/// Load bare viewer first (NO params — no API calls, so no 401 or SPA redirect), then
/// on `onPageFinished` inject auth and manually call adapter public API
/// `BambuddyPrettyGCode.loadArchive(...)`.
///
/// Auth by [AuthMode]:
///  - [AuthMode.jwt]   → JWT to `localStorage.auth_token` (adapter adds Bearer);
///  - [AuthMode.apiKey]→ wrap `window.fetch`, add X-API-Key header
///                       (adapter sends only Bearer);
///  - [AuthMode.none]  → nothing; server allows no auth.
class GcodeViewerScreen extends ConsumerStatefulWidget {
  const GcodeViewerScreen({
    super.key,
    this.archiveId,
    this.libraryFileId,
    this.plate,
    this.title,
  }) : assert(archiveId != null || libraryFileId != null,
            'archiveId lub libraryFileId wymagane');

  /// Archive id to view (`?archive=`). Mutually exclusive with [libraryFileId].
  final int? archiveId;

  /// Library file id (`?library_file=`). Mutually exclusive with [archiveId].
  final int? libraryFileId;

  /// Plate number (1..N) for multi-plate archives; null → first plate.
  final int? plate;

  /// Title on bar (e.g. print name); fallback from l10n.
  final String? title;

  @override
  ConsumerState<GcodeViewerScreen> createState() => _GcodeViewerScreenState();
}

class _GcodeViewerScreenState extends ConsumerState<GcodeViewerScreen> {
  WebViewController? _controller;
  bool _ready = false;
  bool _failed = false;

  /// Guards [_onPageFinished] against re-entrancy: `onPageFinished` can fire
  /// twice (redirect / reload) before the first call's `await` chain — auth
  /// read + `runJavaScript` — has finished, and `_ready` alone doesn't catch
  /// that since it's only set true at the very end of a successful run.
  bool _injecting = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() {
    final profile = ref.read(serverProfileProvider);
    if (profile == null) {
      setState(() => _failed = true);
      return;
    }

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _onPageFinished(profile),
          // Only main frame error = actual load failure. Viewer pulls many resources
          // (e.g. webcam image) whose 404 must NOT break entire screen with error view.
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() => _failed = true);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse('${profile.baseUrl}${Endpoints.gcodeViewer}'));

    setState(() => _controller = controller);
  }

  /// Injects auth and starts source loading after bare viewer loads. Waits (JS poll)
  /// until adapter viewmodel is ready, only then calls `loadArchive`/`loadLibraryFile` —
  /// otherwise G-code fetch won't trigger.
  Future<void> _onPageFinished(ServerProfile profile) async {
    if (_ready || _injecting) return; // Inject only once (first full load).
    _injecting = true;
    try {
      await _inject(profile);
    } finally {
      _injecting = false;
    }
  }

  Future<void> _inject(ServerProfile profile) async {
    final controller = _controller;
    if (controller == null) return;

    String? token;
    String? apiKey;
    final creds = ref.read(credentialsStoreProvider);
    switch (profile.authMode) {
      case AuthMode.jwt:
        token = await creds.readJwt();
      case AuthMode.apiKey:
        apiKey = await creds.readApiKey();
      case AuthMode.none:
        break;
    }
    if (!mounted) return;

    final loadCall = widget.archiveId != null
        ? 'loadArchive(${widget.archiveId}, ${widget.plate ?? 'undefined'})'
        : 'loadLibraryFile(${widget.libraryFileId}, ${widget.plate ?? 'undefined'})';

    // Viewer dark mode follows SYSTEM theme (not app theme).
    final dark = WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;

    // jsonEncode → safe embedding of token/key as JS literals.
    final tokenJs = token == null ? 'null' : jsonEncode(token);
    final apiKeyJs = apiKey == null ? 'null' : jsonEncode(apiKey);

    final script = '''
(function () {
  try {
    var TOKEN = $tokenJs;
    var APIKEY = $apiKeyJs;
    var DARK = $dark;
    if (TOKEN) {
      // Best-effort: storage access can throw in a sandboxed/incognito WebView.
      // The X-API-Key fetch patch below is the real auth path, so ignore failures.
      try { localStorage.setItem('auth_token', TOKEN); } catch (e) {}
      try { sessionStorage.setItem('auth_token', TOKEN); } catch (e) {}
    }
    if (APIKEY && !window.__bbApiKeyPatched) {
      window.__bbApiKeyPatched = true;
      var _f = window.fetch;
      window.fetch = function (res, init) {
        init = init || {};
        var h = Object.assign({}, init.headers || {});
        h['X-API-Key'] = APIKEY;
        init.headers = h;
        return _f(res, init);
      };
    }
    var tries = 0;
    (function waitVM() {
      var api = window.BambuddyPrettyGCode;
      if (api && api.getViewModel && api.getViewModel()) {
        api.$loadCall;
      } else if (tries++ < 100) {
        setTimeout(waitVM, 50);
      }
    })();

    // Dark mode: PrettyGCode controls it via dat.GUI checkbox ("darkMode").
    // pgSettings is private in closure, localStorage NOT read by default (opt-in "save locally"),
    // so toggle via checkbox click — fires original handler (scene background + CSS class + render).
    // Gui created in onTabChange only, so poll until it exists.
    var dtries = 0;
    (function applyDark() {
      var labels = document.querySelectorAll('#mygui .cr.boolean .property-name');
      for (var i = 0; i < labels.length; i++) {
        if (labels[i].textContent.trim() === 'darkMode') {
          var row = labels[i].closest('.cr.boolean');
          var cb = row && row.querySelector('input[type=checkbox]');
          if (cb) {
            if (cb.checked !== DARK) cb.click();
            return;
          }
        }
      }
      if (dtries++ < 100) setTimeout(applyDark, 50);
    })();
  } catch (e) { /* best-effort */ }
})();
''';

    await controller.runJavaScript(script);
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = _controller;
    // Fixed dark tokens regardless of system theme: the WebView canvas behind
    // this bar is always black (matches the embedded viewer), so the bar must
    // stay light-on-black even in light mode.
    const t = DashTokens.dark();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: loggedAppBar(
        AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(color: t.textPrimary),
          title: Text(
            widget.title ?? l10n.gcodeViewerTitle,
            style: TextStyle(
              fontFamily: DashTokens.fontUi,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: t.textPrimary,
            ),
          ),
        ),
      ),
      body: _failed
          ? AsyncErrorView(
              message: l10n.gcodeViewerError,
              onRetry: _retry,
              retryLabel: l10n.retry,
              icon: Icons.broken_image_outlined,
            )
          : controller == null
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  children: [
                    WebViewWidget(controller: controller),
                    if (!_ready)
                      const Center(child: CircularProgressIndicator()),
                  ],
                ),
    );
  }

  void _retry() {
    setState(() {
      _failed = false;
      _ready = false;
      _controller = null;
    });
    _init();
  }
}

