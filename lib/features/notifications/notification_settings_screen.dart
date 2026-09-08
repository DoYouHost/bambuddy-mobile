import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/notification_prefs.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/dash_async.dart';
import '../common/settings_rows.dart';
import '../common/system_insets.dart';

/// Whether the system is currently swallowing every alert, which the switches
/// below cannot show on their own: they keep reading "on" while nothing is
/// delivered, and the app has no other place that says why it went quiet.
///
/// Two separate ways to end up there — the app-level permission refused, and the
/// alerts channel muted by itself, which looks like a granted permission. Kept
/// `autoDispose` so re-entering the screen asks again after a trip to the system
/// settings. False whenever the platform does not answer: a banner that might be
/// wrong is worse than none.
final _notificationsBlockedProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  final service = ref.watch(notificationServiceProvider);
  if (service is! LocalNotificationService) return false;
  if (await service.notificationsEnabled() == false) return true;
  return await service.alertsChannelImportance() == 0;
});

/// Settings screen to choose which local events trigger notifications, with
/// thresholds for threshold-based events. Reads/writes [notificationPrefsProvider];
/// background isolate reads these prefs independently on next startup.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final prefs = ref.watch(notificationPrefsProvider);
    final notifier = ref.read(notificationPrefsProvider.notifier);

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(context, title: l10n.notifSettingsTitle),
        body: ListView(
          padding: withSystemNavInset(
            context,
            const EdgeInsets.fromLTRB(16, 8, 16, 24),
          ),
          children: [
            if (ref.watch(_notificationsBlockedProvider).orFalse)
              _BlockedBanner(l10n.notificationsBlocked),
            Text(l10n.notifSettingsHint, style: t.label),
            const SizedBox(height: 12),
            SettingsCard(
              rows: [
                SettingsSwitchRow(
                  tag: 'notification_settings.event',
                  title: l10n.notifMasterTitle,
                  subtitle: l10n.notifMasterDesc,
                  value: prefs.alertsEnabled,
                  onChanged: notifier.setAlertsEnabled,
                ),
              ],
            ),
            const SizedBox(height: 20),
            SettingsSectionHeader(l10n.notifEventsHeader),
            SettingsCard(
              rows: [
                for (final e in _eventRows(l10n))
                  SettingsSwitchRow(
                    tag: 'notification_settings.event',
                    title: e.label,
                    subtitle: e.description,
                    // Reflect the per-event choice, but grey out while the master
                    // switch is off — the events are silenced regardless.
                    value: prefs.enabled.contains(e.event),
                    onChanged: prefs.alertsEnabled
                        ? (v) => notifier.setEvent(e.event, v)
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: 20),
            SettingsSectionHeader(l10n.notifExtrasHeader),
            SettingsCard(
              rows: [
                SettingsSwitchRow(
                  tag: 'notification_settings.finish_photo',
                  title: l10n.notifFinishPhotoTitle,
                  subtitle: l10n.notifFinishPhotoDesc,
                  value: prefs.finishPhoto,
                  // It decorates the two print-ended alerts, so it is only worth
                  // touching while at least one of them can fire.
                  onChanged:
                      prefs.isOn(NotifEvent.printFinished) ||
                          prefs.isOn(NotifEvent.printFailed)
                      ? notifier.setFinishPhoto
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 20),
            SettingsSectionHeader(l10n.notifThresholdsHeader),
            SettingsCard(
              rows: [
                SettingsSlider(
                  tag: 'notifications.threshold',
                  label: l10n.notifLowFilamentThreshold(
                    prefs.lowFilamentThreshold,
                  ),
                  value: prefs.lowFilamentThreshold,
                  min: 1,
                  max: 50,
                  enabled: prefs.isOn(NotifEvent.lowFilament),
                  onChanged: notifier.setLowFilamentThreshold,
                ),
                SettingsSlider(
                  tag: 'notifications.threshold',
                  label: l10n.notifHumidityThreshold(
                    prefs.amsHumidityThreshold,
                  ),
                  value: prefs.amsHumidityThreshold,
                  min: 20,
                  max: 90,
                  enabled: prefs.isOn(NotifEvent.amsHumidity),
                  onChanged: notifier.setAmsHumidityThreshold,
                ),
                SettingsSlider(
                  tag: 'notifications.threshold',
                  label: l10n.notifBedCooledThreshold(prefs.bedCooledTemp),
                  value: prefs.bedCooledTemp,
                  min: 25,
                  max: 60,
                  enabled: prefs.isOn(NotifEvent.bedCooled),
                  onChanged: notifier.setBedCooledTemp,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<_EventRow> _eventRows(AppLocalizations l) => [
    _EventRow(
      NotifEvent.printStarted,
      l.notifEvtStarted,
      l.notifEvtStartedDesc,
    ),
    _EventRow(
      NotifEvent.printFinished,
      l.notifEvtFinished,
      l.notifEvtFinishedDesc,
    ),
    _EventRow(NotifEvent.printFailed, l.notifEvtFailed, l.notifEvtFailedDesc),
    _EventRow(
      NotifEvent.firstLayer,
      l.notifEvtFirstLayer,
      l.notifEvtFirstLayerDesc,
    ),
    _EventRow(
      NotifEvent.milestones,
      l.notifEvtMilestones,
      l.notifEvtMilestonesDesc,
    ),
    _EventRow(NotifEvent.plateNotEmpty, l.notifEvtPlate, l.notifEvtPlateDesc),
    _EventRow(
      NotifEvent.printerOffline,
      l.notifEvtOffline,
      l.notifEvtOfflineDesc,
    ),
    _EventRow(NotifEvent.printerError, l.notifEvtError, l.notifEvtErrorDesc),
    _EventRow(
      NotifEvent.lowFilament,
      l.notifEvtLowFilament,
      l.notifEvtLowFilamentDesc,
    ),
    _EventRow(
      NotifEvent.amsHumidity,
      l.notifEvtHumidity,
      l.notifEvtHumidityDesc,
    ),
    _EventRow(
      NotifEvent.bedCooled,
      l.notifEvtBedCooled,
      l.notifEvtBedCooledDesc,
    ),
    _EventRow(
      NotifEvent.maintenanceDue,
      l.notifEvtMaintenance,
      l.notifEvtMaintenanceDesc,
    ),
  ];
}

class _EventRow {
  const _EventRow(this.event, this.label, this.description);
  final NotifEvent event;
  final String label;
  final String description;
}

/// Says the switches below are being overruled by the system. Sits above them
/// because every one of them reads "on" while nothing gets through.
class _BlockedBanner extends StatelessWidget {
  const _BlockedBanner(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.notifications_off_outlined,
            size: 18,
            color: scheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: DashTokens.of(
                context,
              ).body.copyWith(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
