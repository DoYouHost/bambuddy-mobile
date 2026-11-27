import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/api/edge_access.dart';
import '../../core/api/edge_cookie.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

/// Builds the page the person signs in on; replaced in tests, which have no
/// WebView. [onLoaded] is told after each page it finishes, [onFailed] when the
/// page itself could not be loaded.
typedef EdgeSignInPageBuilder =
    Widget Function(
      Uri url, {
      required VoidCallback onLoaded,
      required VoidCallback onFailed,
    });

/// Null in the app: the real WebView.
final edgeSignInPageProvider = Provider<EdgeSignInPageBuilder?>((_) => null);

/// Signs in to the Cloudflare Access in front of [host] in a WebView (#72), and
/// pops with the [BrowserSession] it leaves, or null when the person backs out.
///
/// The WebView is only the way to the cookie: it is not told what to do with
/// the pages it opens (a sign-in goes through the identity provider's own
/// domain), and after each one the cookie store is asked whether Access has let
/// it through. The saving is the caller's.
class EdgeSignInScreen extends ConsumerStatefulWidget {
  const EdgeSignInScreen({super.key, required this.host});

  final String host;

  @override
  ConsumerState<EdgeSignInScreen> createState() => _EdgeSignInScreenState();
}

class _EdgeSignInScreenState extends ConsumerState<EdgeSignInScreen> {
  bool _failed = false;

  /// A new WebView per attempt: a failed one is thrown away rather than reloaded.
  int _attempt = 0;

  bool _checking = false;
  bool _again = false;
  bool _done = false;

  Uri get _url => Uri(scheme: 'https', host: widget.host, path: '/');

  /// Pages can finish while the cookie store is still being asked about the
  /// last: the answer then is about a page that is no longer the latest, so the
  /// question is asked once more instead of dropped.
  Future<void> _onLoaded() async {
    if (!mounted || _done || _failed) return;
    final route = ModalRoute.of(context);
    if (_checking) {
      _again = true;
      return;
    }
    _checking = true;
    try {
      do {
        _again = false;
        final session = await EdgeSignIn(
          host: widget.host,
          jar: ref.read(edgeCookieJarProvider),
          now: clock.now,
        ).check();
        // Not the route on top once the person has backed out: the screen is
        // still mounted for the length of the exit animation, and a pop now
        // would close what is underneath it.
        if (!mounted || _done || _failed || route?.isCurrent != true) return;
        if (session != null) {
          _done = true;
          Navigator.of(context).pop(session);
          return;
        }
      } while (_again);
    } finally {
      _checking = false;
    }
  }

  void _onFailed() {
    if (mounted && !_done) setState(() => _failed = true);
  }

  void _retry() => setState(() {
    _failed = false;
    _attempt++;
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final builder = ref.watch(edgeSignInPageProvider) ?? _webView;
    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(context, title: l10n.edgeAccessTitle),
        body: _failed
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(DashSpace.gutter),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.edgeAccessSignInFailed,
                        style: t.bodySoft,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: DashSpace.md),
                      FilledButton(
                        onPressed: _retry,
                        child: Text(l10n.retry),
                      ).tagged('edge_sign_in.retry'),
                    ],
                  ),
                ),
              )
            : KeyedSubtree(
                key: ValueKey(_attempt),
                child: builder(_url, onLoaded: _onLoaded, onFailed: _onFailed),
              ),
      ),
    );
  }

  Widget _webView(
    Uri url, {
    required VoidCallback onLoaded,
    required VoidCallback onFailed,
  }) => _SignInWebView(url: url, onLoaded: onLoaded, onFailed: onFailed);
}

class _SignInWebView extends StatefulWidget {
  const _SignInWebView({
    required this.url,
    required this.onLoaded,
    required this.onFailed,
  });

  final Uri url;
  final VoidCallback onLoaded;
  final VoidCallback onFailed;

  @override
  State<_SignInWebView> createState() => _SignInWebViewState();
}

class _SignInWebViewState extends State<_SignInWebView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      // Identity providers' sign-in pages do not work without it. The user agent
      // is left as the WebView has it: some providers refuse an embedded browser
      // (the warning says so), and posing as another one would be a lie to them.
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => widget.onLoaded(),
          // A sub-resource failing is the page's own affair.
          onWebResourceError: (error) {
            if (error.isForMainFrame == true) widget.onFailed();
          },
        ),
      )
      ..loadRequest(widget.url);
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}

/// Signs in again to [host] after the session ended (#72): the way the sheet
/// does it, without the warning it already gave once. Empties the WebView first,
/// as the sheet does, so the answer is a new sign-in and not the session that
/// was just refused. True when a session was saved.
Future<bool> signInAgain(
  BuildContext context,
  WidgetRef ref, {
  required String host,
}) async {
  await ref.read(edgeCookieJarProvider).clear();
  if (!context.mounted) return false;
  final session = await Navigator.of(context, rootNavigator: true)
      .push<BrowserSession>(
        MaterialPageRoute(builder: (_) => EdgeSignInScreen(host: host)),
      );
  if (session == null || !context.mounted) return false;
  await ref.read(tlsIdentityProvider.notifier).setEdge(session);
  return true;
}
