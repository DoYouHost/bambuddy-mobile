import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/notifications/notification_prefs.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

/// Whether the system is currently swallowing every alert, which the switches
/// below cannot show on their own: they keep reading "on" while nothing is
/// delivered, and the app has no other place that says why it went quiet.
///
/// Two separate ways to end up there — the app-level permission refused, and the
/// alerts channel muted by itself, which looks like a granted permission. Kept
/// `autoDispose` so re-entering the screen asks again after a trip to the system
/// settings. False whenever the platform does not answer: a banner that might be
/// wrong is worse than none.
final _notificationsBlockedProvider = FutureProvider.autoDispose<bool>((ref) async {
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (ref.watch(_notificationsBlockedProvider).valueOrNull ?? false)
              _BlockedBanner(l10n.notificationsBlocked),
            Text(
              l10n.notifSettingsHint,
              style: TextStyle(
                fontFamily: DashTokens.fontUi,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: t.textTertiary,
              ),
            ),
            const SizedBox(height: 12),
            _DashSection(
              rows: [
                _DashSwitchRow(
                  title: l10n.notifMasterTitle,
                  subtitle: l10n.notifMasterDesc,
                  value: prefs.alertsEnabled,
                  onChanged: notifier.setAlertsEnabled,
                ),
              ],
            ),
            const SizedBox(height: 20),
            _Header(l10n.notifEventsHeader),
            _DashSection(
              rows: [
                for (final e in _eventRows(l10n))
                  _DashSwitchRow(
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
            _Header(l10n.notifExtrasHeader),
            _DashSection(
              rows: [
                _DashSwitchRow(
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
            _Header(l10n.notifThresholdsHeader),
            _DashSection(
              rows: [
                _ThresholdSlider(
                  label:
                      l10n.notifLowFilamentThreshold(prefs.lowFilamentThreshold),
                  value: prefs.lowFilamentThreshold,
                  min: 1,
                  max: 50,
                  enabled: prefs.isOn(NotifEvent.lowFilament),
                  onChanged: notifier.setLowFilamentThreshold,
                ),
                _ThresholdSlider(
                  label: l10n.notifHumidityThreshold(prefs.amsHumidityThreshold),
                  value: prefs.amsHumidityThreshold,
                  min: 20,
                  max: 90,
                  enabled: prefs.isOn(NotifEvent.amsHumidity),
                  onChanged: notifier.setAmsHumidityThreshold,
                ),
                _ThresholdSlider(
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
        _EventRow(NotifEvent.printStarted, l.notifEvtStarted, l.notifEvtStartedDesc),
        _EventRow(NotifEvent.printFinished, l.notifEvtFinished, l.notifEvtFinishedDesc),
        _EventRow(NotifEvent.printFailed, l.notifEvtFailed, l.notifEvtFailedDesc),
        _EventRow(NotifEvent.firstLayer, l.notifEvtFirstLayer, l.notifEvtFirstLayerDesc),
        _EventRow(NotifEvent.milestones, l.notifEvtMilestones, l.notifEvtMilestonesDesc),
        _EventRow(NotifEvent.plateNotEmpty, l.notifEvtPlate, l.notifEvtPlateDesc),
        _EventRow(NotifEvent.printerOffline, l.notifEvtOffline, l.notifEvtOfflineDesc),
        _EventRow(NotifEvent.printerError, l.notifEvtError, l.notifEvtErrorDesc),
        _EventRow(NotifEvent.lowFilament, l.notifEvtLowFilament, l.notifEvtLowFilamentDesc),
        _EventRow(NotifEvent.amsHumidity, l.notifEvtHumidity, l.notifEvtHumidityDesc),
        _EventRow(NotifEvent.bedCooled, l.notifEvtBedCooled, l.notifEvtBedCooledDesc),
        _EventRow(NotifEvent.maintenanceDue, l.notifEvtMaintenance, l.notifEvtMaintenanceDesc),
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
          Icon(Icons.notifications_off_outlined,
              size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: DashTokens.fontUi,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontFamily: DashTokens.fontUi,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: t.accentGreenInk,
        ),
      ),
    );
  }
}

/// Card grouping related rows — same container styling as the maintenance
/// screen's printer cards.
class _DashSection extends StatelessWidget {
  const _DashSection({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        gradient: t.cardGradient,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.cardBorder),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(height: 1, indent: 12, endIndent: 12, color: t.hairline),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// Title/subtitle row with a green pill switch on the right, replacing
/// [SwitchListTile] to match the Dash card look.
class _DashSwitchRow extends StatelessWidget {
  const _DashSwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.tag = 'notification_settings.event',
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Name this row taps under in a diagnostic log. Defaults to the per-event
  /// rows, which is what most of this screen is; a row that switches something
  /// other than an event passes its own.
  final String tag;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final enabled = onChanged != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: logTag(
        tag,
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? () => onChanged!(!value) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: DashTokens.fontUi,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: t.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontFamily: DashTokens.fontUi,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: t.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Switch(
                  value: value,
                  onChanged: onChanged,
                  activeThumbColor: t.accentGreen,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Threshold slider (integer). Disabled when related event is OFF — threshold has
/// no effect then, but value is preserved.
class _ThresholdSlider extends StatelessWidget {
  const _ThresholdSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final bool enabled;
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: DashTokens.fontUi,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: t.textPrimary,
              ),
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: t.accentGreen,
                inactiveTrackColor: t.gaugeTrack,
                thumbColor: t.accentGreen,
                overlayColor: t.accentGreen.withValues(alpha: 0.15),
                valueIndicatorColor: t.accentGreen,
                valueIndicatorTextStyle: const TextStyle(
                  fontFamily: DashTokens.fontMono,
                  color: Color(0xFF0A0C08),
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Slider(
                value: value.clamp(min, max).toDouble(),
                min: min.toDouble(),
                max: max.toDouble(),
                divisions: max - min,
                label: '$value',
                onChanged: enabled ? (v) => onChanged(v.round()) : null,
              ).tagged('notifications.threshold'),
            ),
          ],
        ),
      ),
    );
  }
}
