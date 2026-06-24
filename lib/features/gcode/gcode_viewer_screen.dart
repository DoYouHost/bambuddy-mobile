import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/api/endpoints.dart';
import '../../core/settings/server_profile.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

/// Pełnoekranowa przeglądarka G-code 3D. Osadza hostowaną stronę PrettyGCode
/// (`<baseUrl>/gcode-viewer/`) w WebView.
///
/// Strona uwierzytelnia własne wywołania API tokenem `Bearer` czytanym z
/// `localStorage.auth_token`. Ładujemy więc najpierw goły viewer (BEZ
/// parametrów — wtedy NIE robi żadnego wywołania API, więc brak 401 i
/// przekierowania do SPA), a po `onPageFinished` wstrzykujemy auth i ręcznie
/// wołamy publiczne API adaptera `BambuddyPrettyGCode.loadArchive(...)`.
///
/// Auth wg [AuthMode]:
///  - [AuthMode.jwt]   → JWT do `localStorage.auth_token` (adapter doda Bearer);
///  - [AuthMode.apiKey]→ owijamy `window.fetch`, dokładając nagłówek X-API-Key
///                       (adapter sam wysyła tylko Bearer);
///  - [AuthMode.none]  → nic; serwer puszcza bez auth.
class GcodeViewerScreen extends ConsumerStatefulWidget {
  const GcodeViewerScreen({
    super.key,
    this.archiveId,
    this.libraryFileId,
    this.plate,
    this.title,
  }) : assert(archiveId != null || libraryFileId != null,
            'archiveId lub libraryFileId wymagane');

  /// Id archiwum do podglądu (`?archive=`). Wyklucza się z [libraryFileId].
  final int? archiveId;

  /// Id pliku z biblioteki (`?library_file=`). Wyklucza się z [archiveId].
  final int? libraryFileId;

  /// Numer płyty (1..N) dla archiwów wielopłytowych; null → pierwsza płyta.
  final int? plate;

  /// Tytuł na pasku (np. nazwa wydruku); fallback z l10n.
  final String? title;

  @override
  ConsumerState<GcodeViewerScreen> createState() => _GcodeViewerScreenState();
}

class _GcodeViewerScreenState extends ConsumerState<GcodeViewerScreen> {
  WebViewController? _controller;
  bool _ready = false;
  bool _failed = false;

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
          // Tylko błąd głównej ramki = realna porażka ładowania. Viewer ciągnie
          // wiele zasobów (np. obraz webcama), których 404 NIE może wywracać
          // całego ekranu na widok błędu.
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

  /// Wstrzykuje auth i uruchamia ładowanie źródła po załadowaniu gołego
  /// viewera. Czeka (poll w JS) aż viewmodel adaptera będzie gotowy, dopiero
  /// wtedy woła `loadArchive`/`loadLibraryFile` — inaczej pobranie G-code by
  /// się nie wyzwoliło.
  Future<void> _onPageFinished(ServerProfile profile) async {
    if (_ready) return; // wstrzykuj tylko raz (pierwsze pełne ładowanie)
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

    // Tryb ciemny viewera podążający za motywem SYSTEMU (nie motywem apki).
    final dark = WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;

    // jsonEncode → bezpieczne osadzenie tokenu/klucza jako literałów JS.
    final tokenJs = token == null ? 'null' : jsonEncode(token);
    final apiKeyJs = apiKey == null ? 'null' : jsonEncode(apiKey);

    final script = '''
(function () {
  try {
    var TOKEN = $tokenJs;
    var APIKEY = $apiKeyJs;
    var DARK = $dark;
    if (TOKEN) {
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

    // Tryb ciemny: PrettyGCode steruje nim checkboxem dat.GUI ("darkMode").
    // pgSettings jest prywatne w domknięciu, a localStorage NIE jest czytane
    // domyślnie (opt-in "save locally"), więc przełączamy stan klikając
    // realny checkbox — odpala oryginalny handler (tło sceny + klasa CSS +
    // render). Gui powstaje dopiero w onTabChange, więc odpytujemy aż będzie.
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

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(widget.title ?? l10n.gcodeViewerTitle)),
      body: _failed
          ? _ErrorView(message: l10n.gcodeViewerError, onRetry: _retry)
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

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image_outlined, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: Text(l10n.retry)),
          ],
        ),
      ),
    );
  }
}
