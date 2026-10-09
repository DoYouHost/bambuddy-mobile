import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/dash_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers.dart';
import '../../common/dash_async.dart';
import '../../common/dash_input.dart';
import '../../common/sheet_surface.dart';
import '../dashboard_filters.dart';
import '../dashboard_sort.dart';
import '../providers.dart';

/// Opens the dashboard filter and sort bottom sheet. Changes are written
/// straight to [dashboardFiltersProvider] and [dashboardSortProvider], so the
/// list behind it updates live.
Future<void> showDashboardFilterSheet(BuildContext context) {
  return dashSurfaceSheet<void>(
    context,
    builder: (_) => const _DashboardFilterSheet(),
  );
}

/// The name a status bucket goes by in a filter chip and in a section header.
String statusBucketLabel(AppLocalizations l10n, PrinterStatusBucket bucket) =>
    switch (bucket) {
      PrinterStatusBucket.all => l10n.statusAll,
      PrinterStatusBucket.printing => l10n.statusPrinting,
      PrinterStatusBucket.idle => l10n.statusIdle,
      PrinterStatusBucket.paused => l10n.statusPaused,
      PrinterStatusBucket.finished => l10n.statusFinished,
      PrinterStatusBucket.error => l10n.statusErrorFilter,
      PrinterStatusBucket.offline => l10n.statusOfflineFilter,
    };

class _DashboardFilterSheet extends ConsumerWidget {
  const _DashboardFilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = DashTokens.of(context);
    final filters = ref.watch(dashboardFiltersProvider);
    final notifier = ref.read(dashboardFiltersProvider.notifier);
    final sort = ref.watch(dashboardSortProvider);
    final sortNotifier = ref.read(dashboardSortProvider.notifier);
    final locations = printerLocationsOf([
      for (final p in ref.watch(dashboardProvider).printers ?? const [])
        p.printer.location,
    ]);
    final canManage = ref.watch(printerLocationsSupportedProvider).orFalse;

    return logTag(
      'sheet.dashboard_filters',
      FittedSheetSurface(
        // A Material of its own: the switch row's ink and splash paint on the
        // nearest one, which would otherwise be behind the sheet's fill.
        child: Flexible(
          child: Material(
            type: MaterialType.transparency,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                DashSpace.gutter,
                DashSpace.md,
                DashSpace.gutter,
                DashSpace.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Fixed height so the header never resizes the sheet or
                  // shifts the title when the Clear button toggles.
                  SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        Text(
                          l10n.dashboardFilters,
                          style: theme.textTheme.titleLarge,
                        ),
                        const Spacer(),
                        // Keep the button's slot laid out even when inactive,
                        // so it can't reflow the row.
                        Visibility(
                          visible: filters.activeCount > 0,
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          child: TextButton(
                            onPressed: () =>
                                notifier.state = const DashboardFilters(),
                            child: Text(l10n.filtersClear),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: DashSpace.sm),
                  _GroupLabel(label: l10n.filterStatus),
                  Wrap(
                    spacing: DashSpace.sm,
                    runSpacing: DashSpace.xs,
                    children: [
                      for (final bucket in PrinterStatusBucket.values)
                        ChoiceChip(
                          label: Text(statusBucketLabel(l10n, bucket)),
                          selected: filters.status == bucket,
                          onSelected: (_) =>
                              notifier.state = filters.copyWith(status: bucket),
                        ),
                    ],
                  ),
                  const SizedBox(height: DashSpace.sm),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: filters.hideOffline,
                    onChanged: (v) =>
                        notifier.state = filters.copyWith(hideOffline: v),
                    title: Text(l10n.hideOffline, style: t.bodyStrong),
                    activeThumbColor: t.accentGreen,
                  ),
                  // Offered while some printer has a location, as on the web, and
                  // while the server can manage them — the way in to the screen.
                  if (locations.isNotEmpty || canManage) ...[
                    const SizedBox(height: DashSpace.sm),
                    _GroupLabel(label: l10n.dashboardSortLocation),
                    if (locations.isNotEmpty)
                      dashCombo<String?>(
                        context,
                        id: 'dashboard_filters.location',
                        initialSelection: filters.location,
                        onSelected: (v) =>
                            notifier.state = filters.copyWith(location: v),
                        entries: [
                          DropdownMenuEntry(
                            value: null,
                            label: l10n.dashboardLocationAll,
                            labelWidget: logTag(
                              'dashboard_filters.location_all',
                              Text(l10n.dashboardLocationAll),
                            ),
                          ),
                          for (final location in locations)
                            DropdownMenuEntry(
                              value: location,
                              label: location,
                              labelWidget: logTag(
                                'dashboard_filters.location_option',
                                Text(location),
                              ),
                            ),
                        ],
                      ),
                    if (canManage)
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          context.push('/locations');
                        },
                        icon: const Icon(Icons.place_outlined),
                        label: Text(l10n.dashboardLocationsManage),
                      ).tagged('dashboard_filters.manage_locations'),
                  ],
                  const SizedBox(height: DashSpace.md),
                  _GroupLabel(label: l10n.dashboardSortTitle),
                  Wrap(
                    spacing: DashSpace.sm,
                    runSpacing: DashSpace.xs,
                    children: [
                      for (final by in PrinterSort.values)
                        ChoiceChip(
                          label: Text(_sortLabel(l10n, by)),
                          selected: sort.by == by,
                          onSelected: (_) =>
                              sortNotifier.state = sort.copyWith(by: by),
                        ).tagged(
                          'dashboard_filters.sort',
                          selected: sort.by == by,
                        ),
                    ],
                  ),
                  const SizedBox(height: DashSpace.sm),
                  Wrap(
                    spacing: DashSpace.sm,
                    runSpacing: DashSpace.xs,
                    children: [
                      for (final ascending in const [true, false])
                        ChoiceChip(
                          avatar: Icon(
                            ascending
                                ? Icons.arrow_upward
                                : Icons.arrow_downward,
                            size: 18,
                          ),
                          label: Text(
                            ascending
                                ? l10n.dashboardSortAscending
                                : l10n.dashboardSortDescending,
                          ),
                          selected: sort.ascending == ascending,
                          onSelected: (_) => sortNotifier.state = sort.copyWith(
                            ascending: ascending,
                          ),
                        ).tagged(
                          'dashboard_filters.direction',
                          selected: sort.ascending == ascending,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _sortLabel(AppLocalizations l10n, PrinterSort by) => switch (by) {
    PrinterSort.name => l10n.dashboardSortName,
    PrinterSort.status => l10n.filterStatus,
    PrinterSort.model => l10n.dashboardSortModel,
    PrinterSort.location => l10n.dashboardSortLocation,
    PrinterSort.eta => l10n.dashboardSortEta,
  };
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: DashSpace.sm),
      child: Text(label, style: t.bodyBold),
    );
  }
}
