import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/diagnostics/log_tag.dart';
import '../../../core/theme/dash_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../common/dash_sheet.dart';
import '../dashboard_filters.dart';

/// Opens the dashboard filter bottom sheet. Changes are written straight to
/// [dashboardFiltersProvider], so the list behind it updates live.
Future<void> showDashboardFilterSheet(BuildContext context) {
  return dashSurfaceSheet<void>(
    context,
    barrierColor: null,
    builder: (_) => const _DashboardFilterSheet(),
  );
}

class _DashboardFilterSheet extends ConsumerWidget {
  const _DashboardFilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = DashTokens.of(context);
    final filters = ref.watch(dashboardFiltersProvider);
    final notifier = ref.read(dashboardFiltersProvider.notifier);

    return logTag(
      'sheet.dashboard_filters',
      SafeArea(
        top: false,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: t.overlaySurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: t.subCardBorder)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: t.textTertiary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Fixed height so the header never resizes the sheet or
                    // shifts the title when the Clear button toggles.
                    SizedBox(
                      height: 48,
                      child: Row(
                        children: [
                          Text(l10n.dashboardFilters,
                              style: theme.textTheme.titleLarge),
                          const Spacer(),
                          // Keep the button's slot laid out even when inactive,
                          // so it can't reflow the row.
                          Visibility(
                            visible: filters.activeCount > 0,
                            maintainSize: true,
                            maintainAnimation: true,
                            maintainState: true,
                            child: TextButton(
                              onPressed: () => notifier.state =
                                  const DashboardFilters(),
                              child: Text(l10n.filtersClear),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    _GroupLabel(label: l10n.filterStatus),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final bucket in PrinterStatusBucket.values)
                          ChoiceChip(
                            label: Text(_statusLabel(l10n, bucket)),
                            selected: filters.status == bucket,
                            onSelected: (_) => notifier.state =
                                filters.copyWith(status: bucket),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: filters.hideOffline,
                      onChanged: (v) =>
                          notifier.state = filters.copyWith(hideOffline: v),
                      title: Text(
                        l10n.hideOffline,
                        style: TextStyle(
                          fontFamily: DashTokens.fontUi,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: t.textPrimary,
                        ),
                      ),
                      activeThumbColor: t.accentGreen,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      )
    );
  }

  String _statusLabel(AppLocalizations l10n, PrinterStatusBucket bucket) =>
      switch (bucket) {
        PrinterStatusBucket.all => l10n.statusAll,
        PrinterStatusBucket.printing => l10n.statusPrinting,
        PrinterStatusBucket.idle => l10n.statusIdle,
        PrinterStatusBucket.paused => l10n.statusPaused,
        PrinterStatusBucket.finished => l10n.statusFinished,
        PrinterStatusBucket.error => l10n.statusErrorFilter,
        PrinterStatusBucket.offline => l10n.statusOfflineFilter,
      };
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: DashTokens.fontUi,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: t.textSecondary,
        ),
      ),
    );
  }
}
