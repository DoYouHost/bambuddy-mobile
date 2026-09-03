import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/format/datetime_format.dart';
import '../../core/format/duration_format.dart';
import '../../core/models/print_log_entry.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../data/print_log_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../archive/archive_providers.dart' show printersForPickerProvider;
import '../common/api_failure_snack.dart';
import '../common/confirm_dialog.dart';
import '../common/currency_symbol.dart';
import '../common/dash_async.dart';
import '../common/dash_input.dart';
import '../common/dash_search_field.dart';
import '../common/dash_sheet.dart';
import '../common/dash_snack.dart';
import '../common/filter_controls.dart';
import '../common/print_run_labels.dart';
import '../common/print_thumbnail.dart';
import '../common/sheet_surface.dart';
import '../common/sliver_search_bar.dart';
import '../common/state_views.dart';
import '../stats/stats_common.dart' show fmtGrams, fmtNum;
import '../stats/stats_providers.dart' show statsUsersProvider;
import 'print_log_classify_sheet.dart';
import 'print_log_providers.dart';

/// The print log: one row per run, from a table that outlives the archives it
/// points at.
///
/// Two things live here and nowhere else in the app — the failure cause of a
/// single run, which is what the Stats screen's Failure Analysis groups by, and
/// the runs whose archive is already gone.
class PrintLogScreen extends ConsumerStatefulWidget {
  const PrintLogScreen({super.key});

  @override
  ConsumerState<PrintLogScreen> createState() => _PrintLogScreenState();
}

class _PrintLogScreenState extends ConsumerState<PrintLogScreen> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Unlike the archive's, this search is a server-side filter — every
  /// keystroke would be a request, so the debounce is doing real work.
  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      ref.read(printLogFiltersProvider.notifier).setQuery(q.trim());
    });
  }

  void _openFilters() => dashSurfaceSheet<void>(
        context,
        builder: (_) => const _PrintLogFilterSheet(),
      );

  void _openEntry(PrintLogEntry entry) => dashSheet<void>(
        context,
        builder: (_) => PrintLogClassifySheet(entry: entry),
      );

  /// Clearing wipes every user's rows and drops their contribution from the
  /// statistics, so the count goes in the question rather than in a toast
  /// afterwards.
  Future<void> _clearLog() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final total = ref.read(printLogProvider).valueOrNull?.total ?? 0;
    final confirmed = await confirmDialog(
      context,
      title: l10n.printLogClearTitle,
      message: l10n.printLogClearBody(total),
      confirmLabel: l10n.printLogClear,
      destructive: true,
      icon: Icons.delete_sweep_outlined,
      id: 'print_log.clear',
    );
    if (!confirmed) return;

    final (deleted, error) =
        await ref.read(printLogProvider.notifier).clearAll();
    if (!mounted) return;
    if (error != null) {
      showApiFailure(
        messenger,
        error,
        l10n,
        action: 'print_log.clear',
        message: l10n.printLogClearFailed,
      );
      return;
    }
    messenger.snack(l10n.printLogCleared(deleted ?? 0));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(printLogProvider);
    final filters = ref.watch(printLogFiltersProvider);
    final sortable = ref.watch(printLogCostEnergyProvider).valueOrNull ?? false;

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(
          context,
          title: l10n.printLogTitle,
          actions: [
            if (sortable) _SortMenu(filters: filters),
            logTag(
              'print_log.menu',
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'clear') _clearLog();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'clear',
                    child: logTag(
                      'print_log.menu.clear',
                      Text(l10n.printLogClear),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        body: dashAsync(
          context,
          async,
          onRetry: () => ref.read(printLogProvider.notifier).refresh(),
          fallbackMessage: l10n.printLogLoadFailed,
          data: (state) => RefreshIndicator(
            onRefresh: () => ref.read(printLogProvider.notifier).refresh(),
            child: NotificationListener<ScrollNotification>(
              // Paging happens on the wire (the endpoint caps a page at 500),
              // so the next page is fetched before the user reaches the end
              // rather than behind a button they have to find.
              onNotification: (n) {
                if (n.metrics.pixels > n.metrics.maxScrollExtent - 400) {
                  ref.read(printLogProvider.notifier).loadMore();
                }
                return false;
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  DashSliverSearchBar(
                    child: SizedBox(
                      height: 48,
                      child: Row(
                        children: [
                          Expanded(
                            child: DashSearchField(
                              id: 'print_log.search',
                              hintText: l10n.printLogSearchHint,
                              onChanged: _onSearchChanged,
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilterButton(
                            count: filters.activeCount,
                            tooltip: l10n.printLogFilters,
                            id: 'print_log.filters',
                            onTap: _openFilters,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (state.items.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyStateView(
                        message: filters.activeCount > 0 ||
                                filters.query.isNotEmpty
                            ? l10n.printLogNoMatches
                            : l10n.printLogEmpty,
                        icon: filters.activeCount > 0 ||
                                filters.query.isNotEmpty
                            ? Icons.search_off
                            : Icons.receipt_long_outlined,
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      sliver: SliverList.builder(
                        itemCount: state.items.length + 1,
                        itemBuilder: (context, i) => i == state.items.length
                            ? _ListFooter(state: state)
                            : _PrintLogCard(
                                entry: state.items[i],
                                onTap: () => _openEntry(state.items[i]),
                              ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sort control. Only built on a server that honours it: below 1.2.6 the
/// params are dropped in silence, and a control that changes nothing is worse
/// than no control (`ServerFeature.printLogCostEnergy`).
class _SortMenu extends ConsumerWidget {
  const _SortMenu({required this.filters});

  final PrintLogFilters filters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final notifier = ref.read(printLogFiltersProvider.notifier);

    /// A caption above a group of rows. `enabled: false` because it is a label,
    /// not a choice — tapping it must not close the menu.
    PopupMenuEntry<String> caption(String text) => PopupMenuItem<String>(
          enabled: false,
          height: 32,
          child: Text(text, style: t.micro.copyWith(color: t.textTertiary)),
        );

    return logTag(
      'print_log.sort',
      PopupMenuButton<String>(
        icon: Icon(Icons.sort, color: t.textSecondary),
        tooltip: l10n.printLogSort,
        onSelected: (value) {
          if (value == 'asc' || value == 'desc') {
            notifier.set(filters.copyWith(descending: value == 'desc'));
            return;
          }
          final column = PrintLogSort.values.firstWhere((s) => s.name == value);
          notifier.set(filters.copyWith(sort: column));
        },
        itemBuilder: (context) => [
          // Both groups are checkmarked states rather than actions. The
          // direction used to be one row labelled with what a tap would do
          // ("Ascending" while sorting descending), which reads as the current
          // setting and says the opposite of it.
          caption(l10n.printLogSort),
          for (final s in PrintLogSort.values)
            CheckedPopupMenuItem(
              value: s.name,
              checked: filters.sort == s,
              child: logTag(
                'print_log.sort.${s.name}',
                Text(printLogSortLabel(l10n, s)),
              ),
            ),
          const PopupMenuDivider(),
          caption(l10n.printLogSortDirection),
          CheckedPopupMenuItem(
            value: 'desc',
            checked: filters.descending,
            child: logTag(
              'print_log.sort.desc',
              Text(l10n.printLogSortDescending),
            ),
          ),
          CheckedPopupMenuItem(
            value: 'asc',
            checked: !filters.descending,
            child: logTag(
              'print_log.sort.asc',
              Text(l10n.printLogSortAscending),
            ),
          ),
        ],
      ),
    );
  }
}

String printLogSortLabel(AppLocalizations l10n, PrintLogSort sort) =>
    switch (sort) {
      PrintLogSort.date => l10n.printLogSortDate,
      PrintLogSort.printName => l10n.printLogSortName,
      PrintLogSort.printer => l10n.printLogSortPrinter,
      PrintLogSort.user => l10n.printLogSortUser,
      PrintLogSort.status => l10n.printLogSortStatus,
      PrintLogSort.duration => l10n.printLogSortDuration,
      PrintLogSort.filamentUsed => l10n.printLogSortFilament,
      PrintLogSort.cost => l10n.printLogSortCost,
      PrintLogSort.energy => l10n.printLogSortEnergy,
    };

/// Tail of the list: how far the page has got, and the manual way to ask for
/// more when the automatic one has nothing to scroll.
class _ListFooter extends ConsumerWidget {
  const _ListFooter({required this.state});

  final PrintLogState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    if (!state.hasMore) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Center(
          child: Text(
            l10n.printLogShowing(state.items.length, state.total),
            style: t.monoLabel,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Center(
        child: state.loadingMore
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : logTag(
                'print_log.load_more',
                TextButton(
                  onPressed: () =>
                      ref.read(printLogProvider.notifier).loadMore(),
                  child: Text(
                    '${l10n.printLogLoadMore} · '
                    '${l10n.printLogShowing(state.items.length, state.total)}',
                  ),
                ),
              ),
      ),
    );
  }
}

class _PrintLogCard extends ConsumerWidget {
  const _PrintLogCard({required this.entry, required this.onTap});

  final PrintLogEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final showMoney =
        ref.watch(printLogCostEnergyProvider).valueOrNull ?? false;

    final currency = ref.watch(currencySymbolProvider);

    final who = <String>[
      if (entry.printerName != null) entry.printerName!,
      entry.createdByUsername ?? l10n.printLogNoUser,
      DateTimeFormats.of(context).dateTime(entry.displayDate),
    ];
    final numbers = <String>[
      if (entry.durationSeconds != null)
        formatSeconds(l10n, entry.durationSeconds!),
      if (entry.filamentUsedGrams != null) fmtGrams(entry.filamentUsedGrams!),
      // Below 1.2.6 these are null for every row, which is not the same as
      // "this run cost nothing" — the gate is what keeps the two apart.
      if (showMoney && entry.cost != null)
        formatMoney(currency, fmtNum(entry.cost!)),
      if (showMoney && entry.energyKwh != null)
        l10n.printLogEnergy(fmtNum(entry.energyKwh!)),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: logTag(
          'print_log.card',
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: t.subCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: t.subCardBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PrintThumbnail.printLogEntry(
                    printLogEntryId: entry.hasThumbnail ? entry.id : null,
                    size: 52,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // The status rides beside the name rather than beside
                        // the whole card: it is the widest thing on the row,
                        // and holding a column of its own cost the lines below
                        // the space they need — the date and the energy both
                        // ended in an ellipsis.
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                entry.printName ?? '#${entry.id}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: t.titleSm,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _Pill(
                              label: printRunStatusLabel(l10n, entry.status),
                              color: entry.countsAsFailure
                                  ? t.danger
                                  : (entry.status == 'completed'
                                      ? t.accentGreen
                                      : t.textTertiary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          who.join(' · '),
                          // Wrapping, not an ellipsis: a run whose printer and
                          // user are both long is still a run whose date the
                          // reader came for.
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.label.copyWith(color: t.textSecondary),
                        ),
                        if (numbers.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            numbers.join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: t.monoValue.copyWith(
                              color: t.textSecondary,
                            ),
                          ),
                        ],
                        if (entry.failureReason != null || entry.isOrphan) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (entry.failureReason != null)
                                _Pill(
                                  label: failureReasonLabel(
                                      l10n, entry.failureReason),
                                  color: t.accentOrange,
                                ),
                              if (entry.isOrphan)
                                _Pill(
                                  label: l10n.printLogOrphan,
                                  color: t.textTertiary,
                                  icon: Icons.link_off,
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small tinted label — status, failure cause, "archive deleted".
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(label, style: t.micro.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// One "anything, or pick one" filter combo.
///
/// [anyValue] is what the "any" row carries, because a `DropdownMenu` has no
/// null option and every row needs a value of its own — an id no printer has,
/// an empty username. It never reaches [onPick]: choosing it, or choosing
/// nothing, is reported as null, so the caller only ever handles "no filter"
/// once. Duplicating that mapping per combo is how two pickers drift apart.
///
/// [options] pairs each value with the label it shows. Labels are names people
/// gave things, so they stay out of the diagnostic id — every row of one
/// picker records under the same `<id>.option`.
Widget _anyOrOne<T>(
  BuildContext context, {
  required String id,
  required String anyLabel,
  required T anyValue,
  required T? selected,
  required List<(T, String)> options,
  required ValueChanged<T?> onPick,
}) =>
    dashCombo<T>(
      context,
      id: id,
      initialSelection: selected ?? anyValue,
      textStyle: DashTokens.of(context).body,
      onSelected: (v) => onPick(v == null || v == anyValue ? null : v),
      entries: [
        DropdownMenuEntry(
          value: anyValue,
          label: anyLabel,
          labelWidget: logTag('$id.any', Text(anyLabel)),
        ),
        for (final (value, label) in options)
          DropdownMenuEntry(
            value: value,
            label: label,
            labelWidget: logTag('$id.option', Text(label)),
          ),
      ],
    );

/// Every filter here is applied by the server: the list is paged, so filtering
/// what is already loaded would answer about this page rather than the log.
class _PrintLogFilterSheet extends ConsumerWidget {
  const _PrintLogFilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final filters = ref.watch(printLogFiltersProvider);
    final notifier = ref.read(printLogFiltersProvider.notifier);
    final printers =
        ref.watch(printersForPickerProvider).valueOrNull ?? const [];
    // Empty (including on 403) hides the picker, mirroring the Stats screen:
    // the server decides who may list users, and the app has no permission
    // model of its own to ask.
    final users = ref.watch(statsUsersProvider).valueOrNull ?? const [];

    return logTag(
      'sheet.print_log_filters',
      DraggableSheetSurface(
        initialSize: 0.6,
        maxSize: 0.9,
        minSize: 0.35,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  Text(l10n.printLogFilters,
                      style: theme.textTheme.titleLarge),
                  const Spacer(),
                  Visibility(
                    visible: filters.activeCount > 0,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: logTag(
                      'print_log.filters.clear',
                      TextButton(
                        onPressed: notifier.clear,
                        child: Text(l10n.filtersClear),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            FilterGroupLabel(label: l10n.printLogFilterStatus),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // One id per value: the status keys are the server's wire
                // vocabulary, so the log can say which was picked without
                // carrying anything the user wrote.
                ChoiceChip(
                  label: Text(l10n.printLogAnyStatus),
                  selected: filters.status == null,
                  onSelected: (_) =>
                      notifier.set(filters.copyWith(clearStatus: true)),
                ).tagged('print_log.filters.status.any'),
                for (final s in printLogStatuses)
                  ChoiceChip(
                    label: Text(printRunStatusLabel(l10n, s)),
                    selected: filters.status == s,
                    onSelected: (_) =>
                        notifier.set(filters.copyWith(status: s)),
                  ).tagged('print_log.filters.status.$s'),
              ],
            ),
            const SizedBox(height: 16),

            if (printers.isNotEmpty) ...[
              FilterGroupLabel(label: l10n.printLogFilterPrinter),
              _anyOrOne<int>(
                context,
                id: 'print_log.filters.printer',
                anyLabel: l10n.printLogAnyPrinter,
                // No printer carries it, so it cannot collide with a real id.
                anyValue: -1,
                selected: filters.printerId,
                options: [for (final p in printers) (p.id, p.name)],
                onPick: (v) => notifier.set(
                  v == null
                      ? filters.copyWith(clearPrinter: true)
                      : filters.copyWith(printerId: v),
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (users.isNotEmpty) ...[
              FilterGroupLabel(label: l10n.printLogFilterUser),
              _anyOrOne<String>(
                context,
                id: 'print_log.filters.user',
                anyLabel: l10n.printLogAnyUser,
                anyValue: '',
                selected: filters.username,
                options: [for (final u in users) (u.username, u.username)],
                onPick: (v) => notifier.set(
                  v == null
                      ? filters.copyWith(clearUsername: true)
                      : filters.copyWith(username: v),
                ),
              ),
              const SizedBox(height: 16),
            ],

            FilterGroupLabel(label: l10n.printLogFilterDates),
            logTag(
              'print_log.filters.dates',
              OutlinedButton.icon(
                icon: const Icon(Icons.date_range, size: 18),
                label: Text(
                  filters.from == null && filters.to == null
                      ? l10n.printLogFilterDates
                      : '${filters.from == null ? '' : DateTimeFormats.of(context).date(filters.from!)}'
                          ' – '
                          '${filters.to == null ? '' : DateTimeFormats.of(context).date(filters.to!)}',
                ),
                onPressed: () async {
                  final now = DateTime.now();
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(now.year - 5),
                    lastDate: now,
                    initialDateRange: filters.from != null &&
                            filters.to != null
                        ? DateTimeRange(start: filters.from!, end: filters.to!)
                        : null,
                  );
                  if (picked == null) return;
                  notifier.set(filters.copyWith(
                    from: picked.start,
                    // The picker hands back midnight; the range is meant to
                    // include everything printed on that day, and the server
                    // compares against an instant.
                    to: DateTime(
                      picked.end.year,
                      picked.end.month,
                      picked.end.day,
                      23,
                      59,
                      59,
                    ),
                  ));
                },
              ),
            ),
            if (filters.from != null || filters.to != null)
              Align(
                alignment: Alignment.centerLeft,
                child: logTag(
                  'print_log.filters.dates_clear',
                  TextButton(
                    onPressed: () =>
                        notifier.set(filters.copyWith(clearDates: true)),
                    child: Text(l10n.clear),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
