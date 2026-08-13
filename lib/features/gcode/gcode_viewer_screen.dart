import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/api/endpoints.dart';
import '../../core/diagnostics/diagnostic_recorder.dart';
import '../../core/diagnostics/log_event.dart';
import '../../core/settings/server_profile.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/state_views.dart';

/// What the injected script reported back about the page it landed on.
///
/// The channel exists because the page can fail in a way no HTTP status shows:
/// a server that dropped the vendored viewer answers `/gcode-viewer/` from the
/// SPA catch-all with a **200**, so `onWebResourceError` never fires and the
/// screen would sit black forever — see
/// `docs/plans/17-gcode-preview-server-viewer-swap.md`.
enum GcodeViewerReport {
  /// The adapter answered and was told to load the source.
  ready,

  /// The page came up without `BambuddyPrettyGCode`. That is a server past the
  /// 1.2.6-cycle commit that deleted the vendored PrettyGCode tree; the app
  /// cannot drive what is there now.
  noAdapter,

  /// The injected script threw before it could decide either way.
  scriptError,
}

/// Maps a channel message to a [GcodeViewerReport]; `null` for anything else.
///
/// Deliberately strict: an unrecognised message must **not** resolve to a
/// verdict. The report is what decides whether the user sees the viewer or an
/// error, so a garbled message may only be ignored — a wrong guess in either
/// direction replaces a working preview with an error page, or the reverse.
@visibleForTesting
GcodeViewerReport? parseGcodeViewerReport(String message) =>
    switch (message.trim()) {
      'ready' => GcodeViewerReport.ready,
      'no-adapter' => GcodeViewerReport.noAdapter,
      'error' => GcodeViewerReport.scriptError,
      _ => null,
    };

/// Why the screen is showing an error instead of the viewer.
enum _Failure {
  /// The page did not load at all (main-frame error).
  load,

  /// The page loaded, but this server no longer carries the embedded viewer.
  viewerRemoved,
}

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
///
/// **Servers past the 1.2.6 cycle have no such page.** The vendored viewer was
/// deleted server-side and replaced with an SPA route the app cannot drive, so
/// this screen only detects that and says so — drawing the preview ourselves is
/// the plan, not this change.
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
  /// Name the injected script posts to. Must match the JS below.
  static const _channel = 'BambuddyReport';

  /// How long to wait for a report before giving up on getting one.
  ///
  /// The script's own poll ends after ~5 s, so a report normally lands well
  /// inside this. Timing out **reveals the page rather than erroring**: no
  /// report means the channel itself did not work, which says nothing about
  /// what the page is showing, and the old behaviour — show it, whatever it is
  /// — is the safe answer to that.
  static const _reportTimeout = Duration(seconds: 15);

  WebViewController? _controller;
  bool _ready = false;
  _Failure? _failure;

  /// Guards [_onPageFinished] against re-entrancy: `onPageFinished` can fire
  /// twice (redirect / reload) before the first call's `await` chain — auth
  /// read + `runJavaScript` — has finished.
  bool _injecting = false;
  bool _injected = false;

  Timer? _watchdog;

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() {
    final profile = ref.read(serverProfileProvider);
    if (profile == null) {
      setState(() => _failure = _Failure.load);
      return;
    }

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..addJavaScriptChannel(_channel, onMessageReceived: _onReport)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _onPageFinished(profile),
          // Only main frame error = actual load failure. Viewer pulls many resources
          // (e.g. webcam image) whose 404 must NOT break entire screen with error view.
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() => _failure = _Failure.load);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse('${profile.baseUrl}${Endpoints.gcodeViewer}'));

    setState(() => _controller = controller);
  }

  void _onReport(JavaScriptMessage message) {
    final report = parseGcodeViewerReport(message.message);
    if (report == null || !mounted) return;
    _watchdog?.cancel();

    switch (report) {
      case GcodeViewerReport.ready:
        setState(() => _ready = true);
      case GcodeViewerReport.noAdapter:
        // Worth a record: from the log alone this is indistinguishable from a
        // screen the user simply left, and it is the whole reason issue #17
        // took a server clone to explain.
        DiagnosticRecorder.active?.add(
          LogSource.app,
          'gcode_viewer',
          lvl: LogLevel.warn,
          fields: const {'state': 'no_adapter'},
        );
        setState(() => _failure = _Failure.viewerRemoved);
      case GcodeViewerReport.scriptError:
        setState(() => _failure = _Failure.load);
    }
  }

  /// Injects auth and starts source loading after bare viewer loads. Waits (JS poll)
  /// until adapter viewmodel is ready, only then calls `loadArchive`/`loadLibraryFile` —
  /// otherwise G-code fetch won't trigger.
  Future<void> _onPageFinished(ServerProfile profile) async {
    if (_injected || _injecting) return; // Inject only once (first full load).
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
  function report(what) {
    try { $_channel.postMessage(what); } catch (e) {}
  }
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
        report('ready');
      } else if (tries++ < 100) {
        setTimeout(waitVM, 50);
      } else {
        // Five seconds without the adapter: this is not a slow page, it is a
        // page that has no viewer in it.
        report('no-adapter');
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
  } catch (e) {
    report('error');
  }
})();
''';

    await controller.runJavaScript(script);
    if (!mounted) return;
    _injected = true;
    _watchdog?.cancel();
    _watchdog = Timer(_reportTimeout, () {
      if (!mounted || _ready || _failure != null) return;
      setState(() => _ready = true);
    });
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
      body: switch (_failure) {
        // Nothing to retry: the page is gone from this server for good, so the
        // only useful button is the way out.
        _Failure.viewerRemoved => AsyncErrorView(
            message: l10n.gcodeViewerUnsupported,
            // `canPop` first: this route lives outside the shell, so a session
            // restored straight onto it has nothing to pop back to.
            onRetry: () => context.canPop() ? context.pop() : context.go('/'),
            retryLabel: l10n.back,
            icon: Icons.info_outline,
          ),
        _Failure.load => AsyncErrorView(
            message: l10n.gcodeViewerError,
            onRetry: _retry,
            retryLabel: l10n.retry,
            icon: Icons.broken_image_outlined,
          ),
        null => controller == null
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  WebViewWidget(controller: controller),
                  if (!_ready) const Center(child: CircularProgressIndicator()),
                ],
              ),
      },
    );
  }

  void _retry() {
    _watchdog?.cancel();
    setState(() {
      _failure = null;
      _ready = false;
      _injected = false;
      _controller = null;
    });
    _init();
  }
}
