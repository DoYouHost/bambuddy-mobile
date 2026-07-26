import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/notifications/notification_prefs.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

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
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final enabled = onChanged != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: logTag(
        'notification_settings.event',
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
