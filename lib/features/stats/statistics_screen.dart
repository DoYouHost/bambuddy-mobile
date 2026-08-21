import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/models/archive_stats.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../common/dash_async.dart';
import '../common/dash_progress.dart';
import '../common/system_insets.dart';
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

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(
          context,
          title: l10n.statsTitle,
          actions: [_UserFilterMenu(filter: filter), _RangeMenu(filter: filter)],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(archiveSlimProvider);
            ref.invalidate(failureAnalysisProvider);
            await ref.read(statsProvider.notifier).refresh();
          },
          child: dashAsync(
            context,
            stats,
            onRetry: () => ref.read(statsProvider.notifier).refresh(),
            fallbackMessage: l10n.statsLoadFailed,
            scrollableError: true,
            skipLoadingOnReload: false,
            skipLoadingOnRefresh: false,
            data: (data) => _StatsBody(data: data),
          ),
        ),
      ),
    );
  }
}

/// "Filter by user" menu in AppBar. Hidden entirely when [statsUsersProvider]
/// comes back empty — either no users to pick from, or the server refused both
/// user listings to this identity (see [statsUsersProvider]).
class _UserFilterMenu extends ConsumerWidget {
  const _UserFilterMenu({required this.filter});

  final StatsFilter filter;

  /// Menu value for "All users", which the filter itself stores as `null`.
  ///
  /// It cannot be `null` here. `PopupMenuButton` resolves its menu route with
  /// `null` on dismissal and has no way to tell that apart from an item whose
  /// value *is* null, so it calls `onCanceled` for both — a `value: null` row
  /// is simply unpickable, which left "All users" unreachable once any user had
  /// been chosen. `-1` is taken: it is the server's own "no user" filter.
  static const _allUsers = -2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final users = ref.watch(statsUsersProvider).valueOrNull ?? const [];
    if (users.isEmpty) return const SizedBox.shrink();

    String labelFor(int? id) {
      if (id == null) return l10n.statsAllUsers;
      if (id == -1) return l10n.statsNoUser;
      for (final u in users) {
        if (u.id == id) return u.username;
      }
      return '?';
    }

    return logTag(
      'stats.user_filter',
      PopupMenuButton<int>(
        icon:
            Icon(Icons.people_outline, color: DashTokens.of(context).textSecondary),
        tooltip: labelFor(filter.createdById),
        initialValue: filter.createdById ?? _allUsers,
        onSelected: (id) => ref
            .read(statsFilterProvider.notifier)
            .setCreatedById(id == _allUsers ? null : id),
        // Tagging the item's child, not the item: a `PopupMenuItem` wrapped in
        // `Semantics` is no longer a `PopupMenuEntry`. Which user was picked is
        // not logged — that is the user's data, and one id per menu is enough.
        itemBuilder: (context) => [
          PopupMenuItem(
            value: _allUsers,
            child: logTag('stats.user_filter.all', Text(l10n.statsAllUsers)),
          ),
          PopupMenuItem(
            value: -1,
            child: logTag('stats.user_filter.none', Text(l10n.statsNoUser)),
          ),
          const PopupMenuDivider(),
          for (final u in users)
            PopupMenuItem(
              value: u.id,
              child: logTag('stats.user_filter.user', Text(u.username)),
            ),
        ],
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
    return logTag(
      'stats.range',
      PopupMenuButton<StatsRange>(
        icon: Icon(Icons.date_range, color: DashTokens.of(context).textSecondary),
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
        // The range is ours, not the user's, so the chosen one can be named.
        itemBuilder: (context) => [
          for (final r in StatsRange.values)
            PopupMenuItem(
              value: r,
              child: logTag('stats.range.${r.name}', Text(statsRangeLabel(l10n, r))),
            ),
        ],
      ),
    );
  }
}

class _StatsBody extends ConsumerWidget {
  const _StatsBody({required this.data});

  final ArchiveStats data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);

    if (data.isEmpty) {
      return ListView(
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: _Centered(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bar_chart_outlined, size: 48, color: t.textTertiary),
                  const SizedBox(height: 12),
                  Text(
                    l10n.statsEmpty,
                    style: TextStyle(
                      fontFamily: DashTokens.fontUi,
                      color: t.textSecondary,
                    ),
                  ),
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
      padding: withSystemNavInset(
        context,
        const EdgeInsets.fromLTRB(12, 12, 12, 24),
      ),
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
            SizedBox(height: 80, child: DashLoading()),
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
                  // Per-print energy only reaches us from a 1.2.5.2 server, and
                  // only once energy tracking has recorded something.
                  if (c.hasEnergyData) ...[
                    EnergyOverTimeCard(data: c, locale: locale),
                    const SizedBox(height: 12),
                  ],
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
    final t = DashTokens.of(context);
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
                Icon(Icons.hourglass_empty, size: 14, color: t.textTertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.statsEnergyWarmingUp,
                    style: t.microSoft,
                  ),
                ),
              ],
            ),
          ],
          Divider(height: 24, color: t.hairline),
          Row(
            children: [
              Icon(Icons.summarize_outlined, size: 28, color: t.accentGreenInk),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.statsTotalCost,
                  style: t.body,
                ),
              ),
              Text(
                fmtNum(data.totalCost + data.totalEnergyCost),
                style: t.monoTitle,
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
    final t = DashTokens.of(context);
    return Row(
      children: [
        Icon(icon, size: 28, color: t.accentGreenInk),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.micro,
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.monoTitle,
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
    final t = DashTokens.of(context);
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
              color: _rateColor(t, rate),
              label: '${rate.round()}%',
            ),
            const SizedBox(height: 12),
            LegendDot(
              color: t.accentGreen,
              text: l10n.statsSuccessful(data.successfulPrints),
            ),
            const SizedBox(height: 4),
            LegendDot(
              color: t.danger,
              text: l10n.statsFailed(data.failedPrints),
            ),
            const SizedBox(height: 4),
            LegendDot(
              color: t.accentOrange,
              text: l10n.statsCancelled(data.cancelledPrints),
            ),
          ],
        ),
      ),
    );
  }

  Color _rateColor(DashTokens t, double rate) {
    if (rate >= 90) return t.accentGreen;
    if (rate >= 70) return t.accentOrange;
    return t.danger;
  }
}

class _TimeAccuracyCard extends StatelessWidget {
  const _TimeAccuracyCard({required this.data});

  final ArchiveStats data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
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
              color: t.accentOrange,
              label: '${acc.round()}%',
            ),
            const SizedBox(height: 12),
            Text(
              l10n.statsTimeAccuracyHint,
              textAlign: TextAlign.center,
              style: t.label,
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
