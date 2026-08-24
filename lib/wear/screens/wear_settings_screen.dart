import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/server_profile.dart';
import '../../core/watch/watch_config_sync.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../wear_providers.dart';
import '../widgets/wear_confirm_dialog.dart';

/// The watch's only settings screen, and the only way off a server once it is
/// configured: before this, a watch that had connected once was married to that
/// server for good — nothing on the device could change or forget it.
///
/// Deliberately thin. Everything else the app knows how to do is a phone
/// setting; what belongs here is what a watch cannot ask the phone to do for it.
class WearSettingsScreen extends ConsumerWidget {
  const WearSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(serverProfileProvider);
    final offered = ref.watch(pendingWatchConfigProvider);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          children: [
            Center(
              child: Text(l10n.wearSettingsTitle,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 12),
            if (profile != null) ...[
              Text(l10n.wearCurrentServer,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10)),
              Text(
                profile.displayName,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
            ],
            // Only when it is a different server: an offer for the one already
            // running is adopted by `WearApp` without ever reaching a screen.
            if (offered != null && !offered.isSameServerAs(profile)) ...[
              Text(l10n.wearFromPhoneWaiting,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11)),
              const SizedBox(height: 6),
              FilledButton(
                onPressed: () => _switchTo(context, ref, offered),
                child: Text(l10n.wearFromPhoneUse),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton(
              onPressed: () => _forgetServer(context, ref, l10n, profile),
              child: Text(l10n.changeServer),
            ),
            const SizedBox(height: 6),
            // Said here rather than in the dialog: the shared wear dialog clips
            // its subtitle to one line, and this is the consequence worth
            // reading before the tap, not after it.
            Text(
              l10n.changeServerWarning,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 9, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  /// Adopt the server the phone offered, in place of the one running.
  Future<void> _switchTo(
      BuildContext context, WidgetRef ref, WatchConfig config) async {
    final navigator = Navigator.of(context);
    try {
      await ref.read(watchConfigSyncProvider).apply(config);
    } catch (_) {
      // Secure storage refused the write. The offer stays on the latch, so the
      // button is still there to try again — better than a screen that lies
      // about having switched.
      return;
    }
    ref.read(pendingWatchConfigProvider.notifier).dismiss();
    ref.invalidate(serverProfileProvider);
    navigator.pop();
  }

  /// Drop the profile and every secret, which routes the app back to setup. The
  /// same wording and the same clearing the phone's drawer uses, so "change
  /// server" means one thing across both apps.
  Future<void> _forgetServer(BuildContext context, WidgetRef ref,
      AppLocalizations l10n, ServerProfile? profile) async {
    final navigator = Navigator.of(context);
    final profiles = ref.read(serverProfileProvider.notifier);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => WearConfirmDialog(
        icon: Icons.swap_horiz_rounded,
        title: l10n.changeServerQuestion,
        subtitle: profile?.displayName,
        confirmColor: const Color(0xFFB3261E),
      ),
    );
    if (confirmed != true) return;
    await profiles.clear();
    // Back to the printer screen we came from, which `WearApp` immediately
    // replaces with setup now that there is no profile.
    navigator.pop();
  }
}
