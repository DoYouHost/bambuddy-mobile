import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/edge_access.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers.dart';
import '../../setup/edge_access_sheet.dart';
import '../../setup/edge_sign_in_screen.dart';
import 'connection_banner.dart';

/// Says Cloudflare Access stopped accepting the credential (#72) and offers the
/// way out from the button: signing in again for a browser session, the sheet for
/// a service token. Only while the saved credential is for the host that was
/// refused: a banner for one the person has since replaced or removed would be
/// stale news.
class EdgeSessionBanner extends ConsumerStatefulWidget {
  const EdgeSessionBanner({super.key});

  @override
  ConsumerState<EdgeSessionBanner> createState() => _EdgeSessionBannerState();
}

class _EdgeSessionBannerState extends ConsumerState<EdgeSessionBanner> {
  bool _busy = false;

  /// Held until the way out is over, so a second tap in the frame of the first
  /// cannot push a second screen. Lowered on the error path too, which is
  /// rethrown: a bug in the app belongs in the report, and the button must not
  /// stay dead behind it.
  Future<void> _fix(EdgeAccess saved) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      switch (saved) {
        case BrowserSession():
          await signInAgain(context, ref, host: saved.host);
        case ServiceToken():
          await showEdgeAccessSheet(
            context,
            host: saved.host,
            area: 'dashboard',
          );
      }
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      rethrow;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final ended = ref.watch(edgeSessionEndedProvider);
    final saved = ref.watch(edgeAccessProvider);
    if (ended == null || saved == null || saved.host != ended) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final (message, label, id) = switch (saved) {
      BrowserSession() => (
        l10n.edgeSessionBanner,
        l10n.edgeAccessSignIn,
        'dashboard.edge_session_sign_in',
      ),
      ServiceToken() => (
        l10n.edgeTokenBanner,
        l10n.edgeAccessSetUp,
        'dashboard.edge_token_replace',
      ),
    };
    return ConnectionBanner(
      message: message,
      action: TextButton(
        onPressed: _busy ? null : () => _fix(saved),
        child: Text(label),
      ).tagged(id),
    );
  }
}
