import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/alarm_ringer.dart';
import '../../core/notifications/notification_prefs.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

/// Whether the alarm may take the whole screen. `autoDispose` and invalidated
/// on resume, because the answer changes on a system settings page.
final _fullScreenProvider = FutureProvider.autoDispose<bool>(
  (_) => const AlarmRinger().canFullScreen(),
);

/// The alarm's settings (#61): the switch, what rings it, the hours and how
/// long it rings. Part of the notification settings screen.
class AlarmSettingsSection extends ConsumerStatefulWidget {
  const AlarmSettingsSection({super.key});

  @override
  ConsumerState<AlarmSettingsSection> createState() =>
      _AlarmSettingsSectionState();
}

class _AlarmSettingsSectionState extends ConsumerState<AlarmSettingsSection> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(_fullScreenProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final alarm = ref.watch(notificationPrefsProvider.select((p) => p.alarm));
    final notifier = ref.read(notificationPrefsProvider.notifier);
    void save(AlarmPrefs next) => notifier.setAlarm(next);
    final on = alarm.enabled;
    final windowOn = on && alarm.windowEnabled;
    final steps = AlarmPrefs.ringMinuteSteps;
    // Only "no" asks for it: while loading there is nothing to say yet.
    final needsFullScreen = on && ref.watch(_fullScreenProvider).value == false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionHeader(l10n.alarmHeader),
        SettingsCard(
          rows: [
            SettingsSwitchRow(
              tag: 'notification_settings.alarm',
              title: l10n.alarmTitle,
              subtitle: l10n.alarmDesc,
              value: on,
              onChanged: (v) => save(alarm.copyWith(enabled: v)),
            ),
            if (needsFullScreen) const _FullScreenRow(),
            for (final (event, title, desc) in [
              (
                AlarmEvent.printFinished,
                l10n.alarmEvtFinished,
                l10n.alarmEvtFinishedDesc,
              ),
              (
                AlarmEvent.printBlocked,
                l10n.alarmEvtBlocked,
                l10n.alarmEvtBlockedDesc,
              ),
              (
                AlarmEvent.dryingFinished,
                l10n.alarmEvtDrying,
                l10n.alarmEvtDryingDesc,
              ),
            ])
              SettingsSwitchRow(
                tag: 'notification_settings.alarm_event',
                title: title,
                subtitle: desc,
                value: alarm.events.contains(event),
                onChanged: on ? (v) => save(alarm.withEvent(event, v)) : null,
              ),
            SettingsSwitchRow(
              tag: 'notification_settings.alarm_window',
              title: l10n.alarmWindowTitle,
              subtitle: l10n.alarmWindowDesc,
              value: alarm.windowEnabled,
              onChanged: on
                  ? (v) => save(alarm.copyWith(windowEnabled: v))
                  : null,
            ),
            _TimeRow(
              tag: 'notification_settings.alarm_from',
              label: l10n.alarmWindowFrom,
              minuteOfDay: alarm.windowStart,
              onPicked: windowOn
                  ? (m) => save(alarm.copyWith(windowStart: m))
                  : null,
            ),
            _TimeRow(
              tag: 'notification_settings.alarm_to',
              label: l10n.alarmWindowTo,
              minuteOfDay: alarm.windowEnd,
              onPicked: windowOn
                  ? (m) => save(alarm.copyWith(windowEnd: m))
                  : null,
            ),
            // The slider moves over the index of [steps], not over minutes:
            // that is what makes its stops uneven.
            SettingsSlider(
              tag: 'notification_settings.alarm_ring',
              label: l10n.alarmRingFor(alarm.ringMinutes),
              subtitle: l10n.alarmRingForDesc,
              bubble: l10n.alarmMinutes(alarm.ringMinutes),
              value: steps.indexOf(alarm.ringMinutes),
              min: 0,
              max: steps.length - 1,
              enabled: on,
              onChanged: (i) => save(alarm.copyWith(ringMinutes: steps[i])),
            ),
            Padding(
              padding: const EdgeInsets.all(DashSpace.md),
              child: OutlinedButton(
                onPressed: on ? () => _ringTest(l10n) : null,
                child: Text(l10n.alarmTest),
              ).tagged('notification_settings.alarm_test'),
            ),
          ],
        ),
      ],
    );
  }

  /// Rings for a minute, whatever the slider says: enough to hear it and to
  /// see the screen, short enough not to need stopping.
  Future<void> _ringTest(AppLocalizations l10n) async {
    final messenger = ScaffoldMessenger.of(context);
    final rang = await const AlarmRinger().ring(
      id: alarmTestId,
      title: l10n.alarmTest,
      body: l10n.alarmTestBody,
      stopLabel: l10n.alarmStop,
      minutes: 1,
    );
    if (!rang) messenger.snack(l10n.alarmTestFailed);
  }
}

/// The test alarm's notification id, apart from every alert band.
const alarmTestId = 0x7A1A;

/// Says the alarm will only be a heads-up notification, and opens the system
/// page where the full-screen permission is granted.
class _FullScreenRow extends StatelessWidget {
  const _FullScreenRow();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DashSpace.md),
      child: Row(
        children: [
          Expanded(
            child: InlineNote(
              l10n.alarmFullScreenNeeded,
              padding: EdgeInsets.zero,
              urgent: true,
            ),
          ),
          const SizedBox(width: DashSpace.sm),
          TextButton(
            onPressed: const AlarmRinger().openFullScreenSettings,
            child: Text(l10n.alarmFullScreenAllow),
          ).tagged('notification_settings.alarm_full_screen'),
        ],
      ),
    );
  }
}

/// A label and a time of day; tapping it opens the system time picker.
class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.tag,
    required this.label,
    required this.minuteOfDay,
    required this.onPicked,
  });

  final String tag;
  final String label;
  final int minuteOfDay;

  /// Null greys the row out.
  final ValueChanged<int>? onPicked;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final time = TimeOfDay(hour: minuteOfDay ~/ 60, minute: minuteOfDay % 60);
    final text = MaterialLocalizations.of(context).formatTimeOfDay(
      time,
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final picked = onPicked;
    return Opacity(
      opacity: picked != null ? 1 : 0.5,
      child: logTag(
        tag,
        Semantics(
          button: true,
          enabled: picked != null,
          child: InkWell(
            borderRadius: BorderRadius.circular(DashRadius.lg),
            onTap: picked == null
                ? null
                : () async {
                    final chosen = await showTimePicker(
                      context: context,
                      initialTime: time,
                    );
                    if (chosen != null) {
                      picked(chosen.hour * 60 + chosen.minute);
                    }
                  },
            child: Padding(
              padding: const EdgeInsets.all(DashSpace.md),
              child: Row(
                children: [
                  Expanded(child: Text(label, style: t.titleSm)),
                  const SizedBox(width: DashSpace.md),
                  Text(text, style: t.titleSm.copyWith(color: t.accent)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
