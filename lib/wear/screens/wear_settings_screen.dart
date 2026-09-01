import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/server_profile.dart';
import '../../core/watch/watch_config_sync.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../wear_action.dart';
import '../wear_providers.dart';
import '../wear_theme.dart';
import '../widgets/wear_confirm_dialog.dart';
import '../widgets/wear_header.dart';
import '../widgets/wear_screen.dart';
import '../widgets/wear_scroll_view.dart';
import '../widgets/wear_spinner.dart';

/// The watch's only settings screen, and the only way off a server once it is
/// configured: before this, a watch that had connected once was married to that
/// server for good — nothing on the device could change or forget it.
///
/// Deliberately thin. Everything else the app knows how to do is a phone
/// setting; what belongs here is what a watch cannot ask the phone to do for it.
///
/// Stateful for one reason: both actions write to secure storage and then touch
/// `ref` and the navigator. Swipe-to-dismiss is a *sideways swipe* on Wear OS —
/// far easier to trigger by accident than a back gesture on a phone — and doing
/// it mid-write would leave this code running against a disposed widget, where a
/// stateless `ref` throws instead of no-oping. A real [State.mounted] is the
/// guard, and the same state carries the busy flag that keeps a double tap from
/// starting the write twice.
class WearSettingsScreen extends ConsumerStatefulWidget {
  const WearSettingsScreen({super.key});

  @override
  ConsumerState<WearSettingsScreen> createState() => _WearSettingsScreenState();
}

class _WearSettingsScreenState extends ConsumerState<WearSettingsScreen>
    with WearAction {

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(serverProfileProvider);
    final offered = ref.watch(pendingWatchConfigProvider);

    return WearScreen(
      child: WearScrollView(
        curved: true,
        children: [
          WearHeader(l10n.wearSettingsTitle),
          const SizedBox(height: 12),
          if (profile != null) ...[
            Text(l10n.wearCurrentServer,
                textAlign: TextAlign.center, style: WearText.fine),
            Text(
              profile.displayName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: WearText.body,
            ),
            const SizedBox(height: 12),
          ],
          if (busy)
            wearSpinner
          else ...[
            // Only when it is a different server: an offer for the one already
            // running is adopted by `WearApp` without ever reaching a screen.
            if (offered != null && !offered.isSameServerAs(profile)) ...[
              Text(l10n.wearFromPhoneWaiting,
                  textAlign: TextAlign.center, style: WearText.small),
              const SizedBox(height: 6),
              FilledButton(
                onPressed: () => _switchTo(offered),
                child: Text(l10n.wearFromPhoneUse),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton(
              onPressed: () => _forgetServer(l10n, profile),
              child: Text(l10n.changeServer),
            ),
            const SizedBox(height: 6),
            // Said here rather than in the dialog: the shared wear dialog
            // clips its subtitle to one line, and this is the consequence
            // worth reading before the tap, not after it.
            Text(
              l10n.changeServerWarning,
              textAlign: TextAlign.center,
              style: WearText.fine,
            ),
          ],
        ],
      ),
    );
  }

  /// Adopt the server the phone offered, in place of the one running.
  Future<void> _switchTo(WatchConfig config) => run(
        () => ref.read(pendingWatchConfigProvider.notifier).adopt(config),
        onDone: () => Navigator.of(context).pop(),
        // No onError: a refused write leaves the offer standing and brings the
        // button back, which is the whole message. Saying more would need copy
        // this screen does not have yet.
      );

  /// Drop the profile and every secret, which routes the app back to setup. The
  /// same wording and the same clearing the phone's drawer uses, so "change
  /// server" means one thing across both apps.
  Future<void> _forgetServer(
      AppLocalizations l10n, ServerProfile? profile) async {
    // Read before the dialog: `clear()` has to reach the notifier even if this
    // widget goes away while the question is on screen.
    final profiles = ref.read(serverProfileProvider.notifier);
    final confirmed = await wearConfirm(
      context,
      icon: Icons.swap_horiz_rounded,
      title: l10n.changeServerQuestion,
      subtitle: profile?.displayName,
    );
    if (!confirmed || !mounted) return;
    // Back to the printer screen we came from, which `WearApp` immediately
    // replaces with setup now that there is no profile.
    await run(profiles.clear, onDone: () => Navigator.of(context).pop());
  }
}
