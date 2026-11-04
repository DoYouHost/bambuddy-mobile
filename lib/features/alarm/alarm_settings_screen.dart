import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/printer.dart';
import '../../core/notifications/alarm_ringer.dart';
import '../../core/notifications/notification_prefs.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/dash_async.dart';

/// Whether the alarm may take the whole screen. `autoDispose` and invalidated
/// on resume, because the answer changes on a system settings page.
final _fullScreenProvider = FutureProvider.autoDispose<bool>(
  (_) => const AlarmRinger().canFullScreen(),
);

/// The printers the exclusions are chosen from.
final _alarmPrintersProvider = FutureProvider.autoDispose<List<Printer>>(
  (ref) => ref.watch(printersRepositoryProvider).fetchPrinters(),
);

/// The alarm's settings (#61): the switch, what rings it, the hours and how
/// long it rings. A screen of its own under app settings, apart from the
/// notifications: the alarm has its own switches and does not follow theirs.
class AlarmSettingsScreen extends ConsumerStatefulWidget {
  const AlarmSettingsScreen({super.key});

  @override
  ConsumerState<AlarmSettingsScreen> createState() =>
      _AlarmSettingsScreenState();
}

class _AlarmSettingsScreenState extends ConsumerState<AlarmSettingsScreen> {
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

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(context, title: l10n.alarmHeader),
        body: ListView(
          padding: screenListPadding(context),
          children: [
            SettingsCard(
              rows: [
                SettingsSwitchRow(
                  tag: 'alarm_settings.enabled',
                  title: l10n.alarmTitle,
                  subtitle: l10n.alarmDesc,
                  value: on,
                  onChanged: (v) => save(alarm.copyWith(enabled: v)),
                ),
                if (needsFullScreen) const _FullScreenRow(),
              ],
            ),
            const SizedBox(height: DashSpace.xl),
            SettingsSectionHeader(l10n.notifEventsHeader),
            SettingsCard(
              rows: [
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
                    tag: 'alarm_settings.event',
                    title: title,
                    subtitle: desc,
                    value: alarm.events.contains(event),
                    onChanged: on
                        ? (v) => save(alarm.withEvent(event, v))
                        : null,
                  ),
              ],
            ),
            dashAsyncStrip(
              context,
              ref.watch(_alarmPrintersProvider),
              data: (printers) => _Exclusions(
                printers: printers,
                alarm: alarm,
                onChanged: on ? save : null,
              ),
            ),
            const SizedBox(height: DashSpace.xl),
            SettingsSectionHeader(l10n.alarmHoursHeader),
            SettingsCard(
              rows: [
                SettingsSwitchRow(
                  tag: 'alarm_settings.window',
                  title: l10n.alarmWindowTitle,
                  subtitle: l10n.alarmWindowDesc,
                  value: alarm.windowEnabled,
                  onChanged: on
                      ? (v) => save(alarm.copyWith(windowEnabled: v))
                      : null,
                ),
                _TimeRow(
                  tag: 'alarm_settings.from',
                  label: l10n.alarmWindowFrom,
                  minuteOfDay: alarm.windowStart,
                  onPicked: windowOn
                      ? (m) => save(alarm.copyWith(windowStart: m))
                      : null,
                ),
                _TimeRow(
                  tag: 'alarm_settings.to',
                  label: l10n.alarmWindowTo,
                  minuteOfDay: alarm.windowEnd,
                  onPicked: windowOn
                      ? (m) => save(alarm.copyWith(windowEnd: m))
                      : null,
                ),
              ],
            ),
            const SizedBox(height: DashSpace.xl),
            SettingsSectionHeader(l10n.alarmLengthHeader),
            SettingsCard(
              rows: [
                // The slider moves over the index of [steps], not over minutes:
                // that is what makes its stops uneven.
                SettingsSlider(
                  tag: 'alarm_settings.length',
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
                  ).tagged('alarm_settings.test'),
                ),
              ],
            ),
          ],
        ),
      ),
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
      printer: '',
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
          ).tagged('alarm_settings.full_screen'),
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

/// The excluded locations and printers. A location excludes every printer in
/// it; such a printer reads as excluded and cannot be switched back alone.
class _Exclusions extends StatelessWidget {
  const _Exclusions({
    required this.printers,
    required this.alarm,
    required this.onChanged,
  });

  final List<Printer> printers;
  final AlarmPrefs alarm;

  /// Null greys every row out, while the alarm is off.
  final ValueChanged<AlarmPrefs>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final save = onChanged;
    // Matched by exact name, as the server matches them.
    final locations = {
      for (final p in printers)
        if (p.location case final String l when l.isNotEmpty) l,
    }.toList()..sort();
    if (printers.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (locations.isNotEmpty) ...[
          const SizedBox(height: DashSpace.xl),
          SettingsSectionHeader(l10n.alarmExcludedLocationsHeader),
          SettingsCard(
            rows: [
              for (final location in locations)
                SettingsSwitchRow(
                  tag: 'alarm_settings.exclude_location',
                  title: location,
                  subtitle: l10n.alarmExcludeLocationDesc,
                  value: alarm.excludedLocations.contains(location),
                  onChanged: save == null
                      ? null
                      : (v) => save(
                          alarm.copyWith(
                            excludedLocations: v
                                ? {...alarm.excludedLocations, location}
                                : ({...alarm.excludedLocations}
                                    ..remove(location)),
                          ),
                        ),
                ),
            ],
          ),
        ],
        const SizedBox(height: DashSpace.xl),
        SettingsSectionHeader(l10n.alarmExcludedPrintersHeader),
        SettingsCard(
          rows: [
            for (final printer in printers) _printerRow(l10n, printer, save),
          ],
        ),
      ],
    );
  }

  Widget _printerRow(
    AppLocalizations l10n,
    Printer printer,
    ValueChanged<AlarmPrefs>? save,
  ) {
    final location = printer.location;
    final byLocation =
        location != null && alarm.excludedLocations.contains(location);
    return SettingsSwitchRow(
      tag: 'alarm_settings.exclude_printer',
      title: printer.name,
      subtitle: byLocation
          ? l10n.alarmExcludedWithLocation(location)
          : l10n.alarmExcludePrinterDesc,
      value: byLocation || alarm.excludedPrinters.contains(printer.id),
      onChanged: save == null || byLocation
          ? null
          : (v) => save(
              alarm.copyWith(
                excludedPrinters: v
                    ? {...alarm.excludedPrinters, printer.id}
                    : ({...alarm.excludedPrinters}..remove(printer.id)),
              ),
            ),
    );
  }
}
