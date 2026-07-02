import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/archive_stats.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../common/state_views.dart';
import 'stats_common.dart';
import 'stats_providers.dart';
import 'stats_sections.dart';

/// Archive statistics screen (full screen, pushed from Dashboard drawer).
///
/// Parity with web version: top cards (Quick Stats, success rate, time accuracy)
/// from `GET /archives/stats`; rich widgets (heatmap, records, trends, histograms)
/// computed client-side from `GET /archives/slim`; failure analysis from
/// `GET /archives/analysis/failures`.
class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final stats = ref.watch(statsProvider);
    final filter = ref.watch(statsFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.statsTitle),
        actions: [_RangeMenu(filter: filter)],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(archiveSlimProvider);
          ref.invalidate(failureAnalysisProvider);
          await ref.read(statsProvider.notifier).refresh();
        },
        child: stats.when(
          loading: () => const _Centered(child: CircularProgressIndicator()),
          error: (e, _) => AsyncErrorView(
            message:
                e is AppApiException ? e.localized(l10n) : l10n.statsLoadFailed,
            onRetry: () => ref.read(statsProvider.notifier).refresh(),
            retryLabel: l10n.retry,
            scrollable: true,
          ),
          data: (data) => _StatsBody(data: data),
        ),
      ),
    );
  }
}

/// Time range picker menu in AppBar. `custom` opens date range picker.
class _RangeMenu extends ConsumerWidget {
  const _RangeMenu({required this.filter});

  final StatsFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<StatsRange>(
      icon: const Icon(Icons.date_range),
      tooltip: statsRangeLabel(l10n, filter.range),
      initialValue: filter.range,
      onSelected: (range) async {
        if (range == StatsRange.custom) {
          final now = DateTime.now();
          final picked = await showDateRangePicker(
            context: context,
            firstDate: DateTime(now.year - 5),
            lastDate: now,
            initialDateRange: filter.from != null && filter.to != null
                ? DateTimeRange(start: filter.from!, end: filter.to!)
                : null,
          );
          if (picked != null) {
            ref
                .read(statsFilterProvider.notifier)
                .setCustom(picked.start, picked.end);
          }
          return;
        }
        ref.read(statsFilterProvider.notifier).setRange(range);
      },
      itemBuilder: (context) => [
        for (final r in StatsRange.values)
          PopupMenuItem(value: r, child: Text(statsRangeLabel(l10n, r))),
      ],
    );
  }
}

class _StatsBody extends ConsumerWidget {
  const _StatsBody({required this.data});

  final ArchiveStats data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    if (data.isEmpty) {
      return ListView(
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: _Centered(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bar_chart_outlined, size: 48),
                  const SizedBox(height: 12),
                  Text(l10n.statsEmpty),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final locale = Localizations.localeOf(context).languageCode;
    final computed = ref.watch(statsComputedProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        _OverviewCard(data: data),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _SuccessRateCard(data: data)),
              const SizedBox(width: 12),
              Expanded(child: _TimeAccuracyCard(data: data)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const FailureAnalysisCard(),
        // Rich widgets computed from slim list — wait for it to load.
        ...computed.when(
          loading: () => const [
            SizedBox(height: 12),
            SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
          ],
          error: (_, _) => const [],
          data: (c) => c.isEmpty
              ? const <Widget>[]
              : [
                  const SizedBox(height: 12),
                  PrintActivityCard(data: c, locale: locale),
                  const SizedBox(height: 12),
                  RecordsCard(data: c, locale: locale),
                  const SizedBox(height: 12),
                  PrinterStatsCard(data: c),
                  const SizedBox(height: 12),
                  FilamentTrendsHeader(stats: data),
                  const SizedBox(height: 12),
                  UsageOverTimeCard(data: c, locale: locale),
                  const SizedBox(height: 12),
                  ByMaterialCard(data: c),
                  const SizedBox(height: 12),
                  SuccessByMaterialCard(data: c),
                  const SizedBox(height: 12),
                  ColorDistributionCard(data: c),
                  const SizedBox(height: 12),
                  DurationHistogramCard(data: c),
                  const SizedBox(height: 12),
                  HabitsCard(data: c, locale: locale),
                  const SizedBox(height: 12),
                  TimeOfDayCard(data: c),
                ],
        ),
      ],
    );
  }
}

// ── Overview (Quick Stats) ──────────────────────────────────────────────────

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.data});

  final ArchiveStats data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SectionCard(
      title: l10n.statsOverview,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.view_in_ar_outlined,
                  label: l10n.statsTotalPrints,
                  value: '${data.totalPrints}',
                ),
              ),
              Expanded(
                child: _StatTile(
                  icon: Icons.schedule,
                  label: l10n.statsPrintTime,
                  value: l10n.statsHours(fmtNum(data.totalPrintTimeHours)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.inventory_2_outlined,
                  label: l10n.statsFilamentUsed,
                  value: fmtGrams(data.totalFilamentGrams),
                ),
              ),
              Expanded(
                child: _StatTile(
                  icon: Icons.payments_outlined,
                  label: l10n.statsFilamentCost,
                  value: fmtNum(data.totalCost),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.bolt_outlined,
                  label: l10n.statsEnergyUsed,
                  value: '${fmtNum(data.totalEnergyKwh)} kWh',
                ),
              ),
              Expanded(
                child: _StatTile(
                  icon: Icons.electrical_services,
                  label: l10n.statsEnergyCost,
                  value: fmtNum(data.totalEnergyCost),
                ),
              ),
            ],
          ),
          if (data.energyDataWarmingUp) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.hourglass_empty, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.statsEnergyWarmingUp,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
          const Divider(height: 24),
          Row(
            children: [
              Icon(Icons.summarize_outlined,
                  size: 28, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.statsTotalCost,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Text(
                fmtNum(data.totalCost + data.totalEnergyCost),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 28, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                value,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Success rate / Time accuracy (ring gauges) ────────────────────────────

class _SuccessRateCard extends StatelessWidget {
  const _SuccessRateCard({required this.data});

  final ArchiveStats data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final rate = data.successRate;
    return SectionCard(
      title: l10n.statsSuccessRate,
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            RingGauge(
              percent: rate,
              color: _rateColor(rate, scheme),
              label: '${rate.round()}%',
            ),
            const SizedBox(height: 12),
            LegendDot(
              color: Colors.green,
              text: l10n.statsSuccessful(data.successfulPrints),
            ),
            const SizedBox(height: 4),
            LegendDot(
              color: scheme.error,
              text: l10n.statsFailed(data.failedPrints),
            ),
          ],
        ),
      ),
    );
  }

  Color _rateColor(double rate, ColorScheme scheme) {
    if (rate >= 90) return Colors.green;
    if (rate >= 70) return Colors.orange;
    return scheme.error;
  }
}

class _TimeAccuracyCard extends StatelessWidget {
  const _TimeAccuracyCard({required this.data});

  final ArchiveStats data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final acc = data.averageTimeAccuracy;
    return SectionCard(
      title: l10n.statsTimeAccuracy,
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            RingGauge(
              percent: acc.clamp(0, 100).toDouble(),
              color: Colors.orange,
              label: '${acc.round()}%',
            ),
            const SizedBox(height: 12),
            Text(
              l10n.statsTimeAccuracyHint,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared ─────────────────────────────────────────────────────────────────

class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(child: child);
}
