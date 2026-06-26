import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/notification_prefs.dart';
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
    final prefs = ref.watch(notificationPrefsProvider);
    final notifier = ref.read(notificationPrefsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.notifSettingsTitle)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              l10n.notifSettingsHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          _Header(l10n.notifEventsHeader),
          for (final e in _eventRows(l10n))
            SwitchListTile(
              title: Text(e.label),
              subtitle: Text(e.description),
              value: prefs.isOn(e.event),
              onChanged: (v) => notifier.setEvent(e.event, v),
            ),
          const Divider(height: 24),
          _Header(l10n.notifThresholdsHeader),
          _ThresholdSlider(
            label: l10n.notifLowFilamentThreshold(prefs.lowFilamentThreshold),
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
          const SizedBox(height: 16),
        ],
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall
            ?.copyWith(color: theme.colorScheme.primary),
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
    final theme = Theme.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodyMedium),
            Slider(
              value: value.clamp(min, max).toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              label: '$value',
              onChanged:
                  enabled ? (v) => onChanged(v.round()) : null,
            ),
          ],
        ),
      ),
    );
  }
}
