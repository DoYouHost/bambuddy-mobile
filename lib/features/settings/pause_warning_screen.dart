import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/format/duration_format.dart';
import '../../core/models/queue_settings.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../common/dash_async.dart';
import 'queue_settings_providers.dart';

/// How long before a slicer pause the server — and this app — warn (server
/// #2984, `pause_warning_minutes`).
///
/// A **server** setting, so it lives in the settings hub and says so. Who may
/// change it is the queue settings' own answer ([queueSettingsLockProvider]):
/// an account with `settings:update`, or a server with authentication off. For
/// everyone else the slider stays on screen with the server's value and a line
/// saying why it cannot move — reading it is a smaller function, not a blocked
/// one, and the app warns by it all the same.
class PauseWarningScreen extends ConsumerWidget {
  const PauseWarningScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final lock = ref.watch(queueSettingsLockProvider).value;
    final reason = switch (lock) {
      null || QueueSettingsLock.none => null,
      QueueSettingsLock.apiKey => l10n.queueSettingsReadOnlyApiKey,
      QueueSettingsLock.permission => l10n.queueSettingsReadOnlyPermission,
    };

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(context, title: l10n.pauseWarningTitle),
        body: RefreshIndicator(
          // The repository too: it carries the latch a 403 closed, and a
          // permission granted server-side is only noticed through a fresh one.
          onRefresh: () async {
            ref.invalidate(serverSettingsRepositoryProvider);
            await ref.read(serverSettingsProvider.notifier).refresh();
          },
          child: dashAsync(
            context,
            ref.watch(queueSettingsProvider),
            onRetry: () => ref.invalidate(serverSettingsProvider),
            data: (settings) =>
                settings.known.contains(QueueSetting.pauseWarningMinutes)
                ? ListView(
                    padding: screenListPadding(context),
                    children: [
                      if (reason != null) ...[
                        InlineNote(
                          reason,
                          icon: Icons.lock_outline,
                          padding: const EdgeInsets.symmetric(
                            horizontal: DashSpace.xs,
                          ),
                        ),
                        const SizedBox(height: DashSpace.md),
                      ],
                      _slider(context, ref, settings, lock, l10n),
                    ],
                  )
                : EmptyStateView(
                    message: l10n.queueSettingsUnavailable,
                    icon: Icons.tune,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _slider(
    BuildContext context,
    WidgetRef ref,
    QueueSettings settings,
    QueueSettingsLock? lock,
    AppLocalizations l10n,
  ) {
    const setting = QueueSetting.pauseWarningMinutes;
    final minutes = settings.number(setting);
    return SettingsCard(
      rows: [
        SettingsSlider(
          tag: 'queue_settings.pause_warning_minutes',
          label: l10n.pauseWarningLabel(formatMinutes(l10n, minutes)),
          subtitle: l10n.pauseWarningDesc,
          bubble: formatMinutes(l10n, minutes),
          value: minutes,
          min: setting.min!,
          max: setting.max!,
          // Unresolved is not writable, as on the queue screen.
          enabled: lock == QueueSettingsLock.none,
          onChanged: (v) =>
              ref.read(queueSettingsProvider.notifier).preview(setting, v),
          onChangeEnd: (v) async {
            final messenger = ScaffoldMessenger.of(context);
            final outcome = await ref
                .read(queueSettingsProvider.notifier)
                .set(setting, v);
            if (outcome.messageFor(l10n) case final message?) {
              messenger.snack(message);
            }
          },
        ),
      ],
    );
  }
}
