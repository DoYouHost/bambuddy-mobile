import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/format/datetime_format.dart';
import '../../core/format/filament_colour.dart';
import '../../core/models/archive.dart';
import '../../core/models/print_run.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../common/print_run_labels.dart';
import '../common/print_thumbnail.dart';
import 'archive_calendar_data.dart';
import 'archive_details.dart';

/// A month of prints — the web's `CalendarView`: each print of an archive on
/// the day it ended, so a file printed three times shows three times. A day
/// with prints carries their count and a dot (green all good, amber mixed, red
/// all failed); picking it lists them, and a print opens its archive.
///
/// [archives] are the list's, filters applied; [printerId] narrows the server's
/// read the way the printer filter narrows the list.
class ArchiveCalendar extends ConsumerStatefulWidget {
  const ArchiveCalendar({
    super.key,
    required this.archives,
    required this.onOpen,
    this.printerId,
    this.today,
  });

  final List<Archive> archives;
  final int? printerId;
  final ValueChanged<Archive> onOpen;

  /// The day the calendar opens on; the clock's when null (tests fix it).
  final DateTime? today;

  @override
  ConsumerState<ArchiveCalendar> createState() => _ArchiveCalendarState();
}

class _ArchiveCalendarState extends ConsumerState<ArchiveCalendar> {
  late final DateTime _today = widget.today ?? DateTime.now();
  late DateTime _month = DateTime(_today.year, _today.month);
  int? _selectedDay;

  void _move(int months) => setState(() {
    _month = DateTime(_month.year, _month.month + months);
    _selectedDay = null;
  });

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final dates = DateTimeFormats.of(context);
    final runs = ref.watch(
      archiveMonthPrintsProvider((
        year: _month.year,
        month: _month.month,
        printerId: widget.printerId,
      )),
    );
    // While the month loads, or if it failed, only the archives that stand for
    // their one print are placed; null (no route) places every printed one.
    final prints = calendarPrints(
      widget.archives,
      runs.hasValue ? runs.value : const [],
      _month.year,
      _month.month,
    );
    final byDay = <int, List<CalendarPrint>>{};
    for (final p in prints) {
      (byDay[p.date.day] ??= []).add(p);
    }
    final good = prints.where((p) => p.status == 'completed').length;
    final failed = prints.where((p) => printRunIsFailure(p.status)).length;
    final selected = _selectedDay == null ? null : byDay[_selectedDay] ?? [];

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DashSpace.xs,
        vertical: DashSpace.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DashSpace.sm,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: l10n.archiveCalendarPrevious,
                onPressed: () => _move(-1),
              ).tagged('archive.calendar.previous'),
              Expanded(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: DashSpace.sm,
                  runSpacing: DashSpace.xs,
                  children: [
                    Text(dates.monthYear(_month), style: t.titleSm),
                    TextButton(
                      onPressed: () => setState(() {
                        _month = DateTime(_today.year, _today.month);
                        _selectedDay = null;
                      }),
                      child: Text(l10n.archiveCalendarToday),
                    ).tagged('archive.calendar.today'),
                    if (runs.isLoading)
                      const SizedBox.square(
                        dimension: DashIcon.sm,
                        child: CircularProgressIndicator(
                          strokeWidth: DashStroke.regular,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: l10n.archiveCalendarNext,
                onPressed: () => _move(1),
              ).tagged('archive.calendar.next'),
            ],
          ),
          if (runs.hasError)
            Text(
              l10n.connectFailed,
              textAlign: TextAlign.center,
              style: t.labelSoft,
            ),
          _MonthGrid(
            month: _month,
            today: _today,
            byDay: byDay,
            selectedDay: _selectedDay,
            onDay: (day) =>
                setState(() => _selectedDay = _selectedDay == day ? null : day),
          ),
          Row(
            children: [
              _Stat(value: prints.length, label: l10n.archiveCalendarPrints),
              _Stat(
                value: good,
                label: l10n.archiveCalendarSuccessful,
                ink: t.accentGreenInk,
              ),
              _Stat(
                value: failed,
                label: l10n.archiveCalendarFailed,
                ink: t.dangerInk,
              ),
            ],
          ),
          if (selected == null)
            Text(
              l10n.archiveCalendarSelectDay,
              textAlign: TextAlign.center,
              style: t.labelSoft,
            )
          else ...[
            Text(
              dates.dateNamedMonth(
                DateTime(_month.year, _month.month, _selectedDay!),
              ),
              style: t.bodyStrong,
            ),
            if (selected.isEmpty)
              Text(l10n.archiveCalendarNoPrints, style: t.labelSoft)
            else
              for (final print in selected)
                _PrintRow(
                  print: print,
                  onTap: () => widget.onOpen(print.archive),
                ),
          ],
        ],
      ),
    );
  }
}

/// Seven columns from the locale's first day of the week, as Material's own
/// date picker lays its month out (`MaterialLocalizations.firstDayOfWeekIndex`).
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.today,
    required this.byDay,
    required this.selectedDay,
    required this.onDay,
  });

  final DateTime month;
  final DateTime today;
  final Map<int, List<CalendarPrint>> byDay;
  final int? selectedDay;
  final ValueChanged<int> onDay;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final material = MaterialLocalizations.of(context);
    final first = material.firstDayOfWeekIndex;
    // DateTime.weekday is 1 (Monday) … 7 (Sunday); the index is 0 for Sunday.
    final lead = (DateTime(month.year, month.month).weekday % 7 - first) % 7;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final cells = <int?>[
      for (var i = 0; i < lead; i++) null,
      for (var d = 1; d <= days; d++) d,
    ];
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Text(
                  material.narrowWeekdays[(first + i) % 7],
                  textAlign: TextAlign.center,
                  style: t.labelSoft,
                ),
              ),
          ],
        ),
        const SizedBox(height: DashSpace.xs),
        for (var row = 0; row * 7 < cells.length; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: switch (row * 7 + col < cells.length
                      ? cells[row * 7 + col]
                      : null) {
                    null => const SizedBox.shrink(),
                    final day => _DayCell(
                      date: DateTime(month.year, month.month, day),
                      prints: byDay[day] ?? const [],
                      today:
                          today.year == month.year &&
                          today.month == month.month &&
                          today.day == day,
                      selected: selectedDay == day,
                      onTap: () => onDay(day),
                    ),
                  },
                ),
            ],
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.prints,
    required this.today,
    required this.selected,
    required this.onTap,
  });

  final DateTime date;
  final List<CalendarPrint> prints;
  final bool today;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final good = prints.where((p) => p.status == 'completed').length;
    final failed = prints.where((p) => printRunIsFailure(p.status)).length;
    final dot = failed > 0 && good == 0
        ? t.danger
        : failed > 0
        ? t.accentOrange
        : t.accentGreen;
    final ink = selected ? t.onAccent : t.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      label: l10n.archiveCalendarDay(
        DateTimeFormats.of(context).dateNamedMonth(date),
        prints.length,
      ),
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(DashRadius.md),
        onTap: onTap,
        child: AspectRatio(
          aspectRatio: 1,
          child: Container(
            margin: const EdgeInsets.all(DashSpace.xs),
            decoration: BoxDecoration(
              color: selected
                  ? t.accent
                  : prints.isNotEmpty
                  ? t.subCard
                  : null,
              borderRadius: BorderRadius.circular(DashRadius.md),
              border: today && !selected
                  ? Border.all(color: t.accent, width: DashStroke.regular)
                  : null,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(DashSpace.xs),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${date.day}', style: t.body.copyWith(color: ink)),
                    if (prints.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: FilamentDot.size * 0.8,
                            height: FilamentDot.size * 0.8,
                            decoration: BoxDecoration(
                              color: dot,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: DashSpace.xs),
                          Text(
                            '${prints.length}',
                            style: t.micro.copyWith(color: ink),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ).tagged('archive.calendar.day');
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.ink});

  final int value;
  final String label;
  final Color? ink;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: t.titleSm.copyWith(color: ink ?? t.textPrimary),
          ),
          Text(label, textAlign: TextAlign.center, style: t.labelSoft),
        ],
      ),
    );
  }
}

class _PrintRow extends StatelessWidget {
  const _PrintRow({required this.print, required this.onTap});

  final CalendarPrint print;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final (_, ink) = printRunTone(t, print.status);
    final colours = filamentColourTokens(print.colors);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: DashSpace.sm),
      leading: PrintThumbnail(archiveId: print.archive.id, size: DashSize.d48),
      title: Text(print.archive.displayName, maxLines: 2),
      subtitle: Wrap(
        spacing: DashSpace.sm,
        runSpacing: DashSpace.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            printRunStatusLabel(l10n, print.status),
            style: t.label.copyWith(color: ink),
          ),
          for (final hex in colours) FilamentDot(hex: hex),
        ],
      ),
      onTap: onTap,
    ).tagged('archive.calendar.print');
  }
}
