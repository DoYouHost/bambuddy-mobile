import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/models/archive_stats.dart';
import '../../l10n/app_localizations.dart';
import 'stats_common.dart';
import 'stats_computed.dart';
import 'stats_providers.dart';

/// Default chart green (consistent with app theme).
const _accent = Color(0xFF22C55E);

// ── Failure Analysis ────────────────────────────────────────────────────────

class FailureAnalysisCard extends ConsumerWidget {
  const FailureAnalysisCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final rangeLabel =
        statsRangeLabel(l10n, ref.watch(statsFilterProvider).range);
    final async = ref.watch(failureAnalysisProvider);
    return SectionCard(
      title: l10n.statsFailureAnalysis,
      child: async.when(
        loading: () => const SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => SizedBox(
          height: 60,
          child: Center(child: Text(l10n.statsLoadFailed)),
        ),
        data: (f) {
          final rateColor = f.failureRate <= 5
              ? _accent
              : (f.failureRate <= 15 ? Colors.orange : theme.colorScheme.error);
          final reasons = f.failuresByReason.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${fmtNum(f.failureRate)}%',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: rateColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(rangeLabel, style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                l10n.statsFailedOfTotal(f.failedPrints, f.totalPrints),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (reasons.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(l10n.statsNoFailures),
                )
              else ...[
                const SizedBox(height: 14),
                Text(
                  l10n.statsTopFailureReasons,
                  style: theme.textTheme.labelMedium,
                ),
                const SizedBox(height: 6),
                for (final e in reasons.take(5))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(child: Text(e.key, overflow: TextOverflow.ellipsis)),
                        Text('${e.value}',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ── Print Activity (heatmapa) ───────────────────────────────────────────────

class PrintActivityCard extends StatelessWidget {
  const PrintActivityCard({super.key, required this.data, required this.locale});

  final StatsComputed data;
  final String locale;

  static const _margin = 3.0;
  static const _labelW = 30.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final days = data.printsByDay;
    final maxCount = days.values.fold<int>(1, math.max);

    // Range: from Monday of the week with earliest print to today.
    final sorted = days.keys.toList()..sort();
    final first = sorted.first;
    final startMonday = first.subtract(Duration(days: first.weekday - 1));
    final last = sorted.last;
    final weeks = (last.difference(startMonday).inDays ~/ 7) + 1;

    final track = theme.colorScheme.surfaceContainerHighest;
    final labelStyle = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: 10);

    Color cellColor(DateTime day) {
      final n = days[day] ?? 0;
      if (n == 0) return track;
      return Color.lerp(track, _accent, (n / maxCount).clamp(0.2, 1.0))!;
    }

    DateTime dayAt(int w, int d) => startMonday.add(Duration(days: w * 7 + d));

    // Short weekday names in locale.
    final wd = DateFormat.E(locale).dateSymbols.STANDALONESHORTWEEKDAYS;
    String weekdayLabel(int d) => d.isEven ? wd[(d + 1) % 7] : '';
    final monthFmt = DateFormat.MMM(locale);

    return SectionCard(
      title: l10n.statsPrintActivity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              // Cell scaled so grid (+ label column) fills card width.
              // For very long ranges, scale down to minimum and enable horizontal scroll.
              final avail = c.maxWidth - _labelW;
              var size = avail / weeks - _margin;
              final scroll = size < 9;
              if (scroll) size = 14;
              final colW = size + _margin;

              // Month header: label above column when month starts.
              final monthRow = Row(
                children: [
                  const SizedBox(width: _labelW),
                  for (var w = 0; w < weeks; w++)
                    SizedBox(
                      width: colW,
                      child: (w == 0 ||
                              dayAt(w, 0).month != dayAt(w - 1, 0).month)
                          ? Text(monthFmt.format(dayAt(w, 0)),
                              style: labelStyle, overflow: TextOverflow.visible)
                          : null,
                    ),
                ],
              );

              final body = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Weekday label column.
                  Column(
                    children: [
                      for (var d = 0; d < 7; d++)
                        SizedBox(
                          width: _labelW,
                          height: colW,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(weekdayLabel(d), style: labelStyle),
                          ),
                        ),
                    ],
                  ),
                  for (var w = 0; w < weeks; w++)
                    Column(
                      children: [
                        for (var d = 0; d < 7; d++)
                          Container(
                            width: size,
                            height: size,
                            margin: const EdgeInsets.all(_margin / 2),
                            decoration: BoxDecoration(
                              color: cellColor(dayAt(w, d)),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                      ],
                    ),
                ],
              );

              final content = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [monthRow, const SizedBox(height: 2), body],
              );
              return scroll
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: content,
                    )
                  : content;
            },
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(l10n.statsHeatmapLess, style: theme.textTheme.bodySmall),
              const SizedBox(width: 6),
              for (final t in [0.0, 0.33, 0.66, 1.0])
                Container(
                  width: 13,
                  height: 13,
                  margin: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    color: t == 0 ? track : Color.lerp(track, _accent, t)!,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              const SizedBox(width: 6),
              Text(l10n.statsHeatmapMore, style: theme.textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Records ─────────────────────────────────────────────────────────────────

class RecordsCard extends StatelessWidget {
  const RecordsCard({super.key, required this.data, required this.locale});

  final StatsComputed data;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = <Widget>[];

    void add(IconData icon, String label, String value, String? sub) {
      rows.add(_RecordRow(icon: icon, label: label, value: value, sub: sub));
    }

    final longest = data.longest;
    if (longest?.effectiveSeconds != null) {
      add(Icons.schedule, l10n.statsLongestPrint,
          fmtDuration(longest!.effectiveSeconds!), longest.printName);
    }
    final heaviest = data.heaviest;
    if (heaviest?.filamentUsedGrams != null) {
      add(Icons.inventory_2_outlined, l10n.statsHeaviestPrint,
          fmtGrams(heaviest!.filamentUsedGrams!), heaviest.printName);
    }
    final exp = data.mostExpensive;
    if (exp?.cost != null) {
      add(Icons.payments_outlined, l10n.statsMostExpensive,
          fmtNum(exp!.cost!), exp.printName);
    }
    if (data.busiestDay != null) {
      add(Icons.calendar_today, l10n.statsBusiestDay,
          l10n.statsPrintsCount(data.busiestDayCount),
          DateFormat.yMMMd(locale).format(data.busiestDay!));
    }
    if (data.bestSuccessStreak > 0) {
      add(Icons.bolt, l10n.statsSuccessStreak,
          l10n.statsConsecutive(data.bestSuccessStreak), null);
    }

    return SectionCard(
      title: l10n.statsRecords,
      child: Column(children: rows),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({
    required this.icon,
    required this.label,
    required this.value,
    this.sub,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodySmall),
                if (sub != null)
                  Text(sub!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(value,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// ── Bar list (shared for breakdowns) ─────────────────────────────────────

class BarList extends StatelessWidget {
  const BarList({super.key, required this.rows});

  /// (label, value-text, fraction 0..1, optional color).
  final List<({String label, String value, double fraction, Color? color})> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(rows[i].label,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  Text(rows[i].value,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: rows[i].fraction.clamp(0, 1).toDouble(),
                  minHeight: 8,
                  color: rows[i].color,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            ],
          ),
          if (i != rows.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

// ── Printer Stats (metric toggle) ──────────────────────────────────────────

class PrinterStatsCard extends ConsumerStatefulWidget {
  const PrinterStatsCard({super.key, required this.data});

  final StatsComputed data;

  @override
  ConsumerState<PrinterStatsCard> createState() => _PrinterStatsCardState();
}

class _PrinterStatsCardState extends ConsumerState<PrinterStatsCard> {
  StatMetric _metric = StatMetric.weight;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final names = ref.watch(printerNamesProvider).valueOrNull ?? const {};
    final entries = widget.data.byPrinter.entries.toList()
      ..sort((a, b) => _metric.of(b.value).compareTo(_metric.of(a.value)));
    final maxVal = entries.fold<num>(
        1, (m, e) => math.max(m, _metric.of(e.value)));

    return SectionCard(
      title: l10n.statsByPrinter,
      trailing: MetricToggle(
        value: _metric,
        onChanged: (m) => setState(() => _metric = m),
      ),
      child: BarList(
        rows: [
          for (final e in entries)
            (
              label: names[e.key] ?? l10n.statsPrinterFallback('${e.key}'),
              value: _metric.format(_metric.of(e.value)),
              fraction: _metric.of(e.value) / maxVal,
              color: null,
            ),
        ],
      ),
    );
  }
}

// ── Filament Trends — header ──────────────────────────────────────────────

class FilamentTrendsHeader extends StatelessWidget {
  const FilamentTrendsHeader({super.key, required this.stats});

  final ArchiveStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final avg = stats.totalPrints == 0
        ? 0.0
        : stats.totalFilamentGrams / stats.totalPrints;
    return SectionCard(
      title: l10n.statsFilamentTrends,
      child: Row(
        children: [
          Expanded(
            child: _Metric(
                label: l10n.statsPeriodFilament,
                value: fmtGrams(stats.totalFilamentGrams)),
          ),
          Expanded(
            child: _Metric(
                label: l10n.statsPeriodCost, value: fmtNum(stats.totalCost)),
          ),
          Expanded(
            child: _Metric(
                label: l10n.statsAvgPerPrint, value: fmtGrams(avg)),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Text(value,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// ── Usage Over Time (line chart) ────────────────────────────────────────

class UsageOverTimeCard extends StatelessWidget {
  const UsageOverTimeCard({super.key, required this.data, required this.locale});

  final StatsComputed data;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final points = data.usageOverTime;
    if (points.length < 2) {
      return SectionCard(
        title: l10n.statsUsageOverTime,
        child: SizedBox(
          height: 60,
          child: Center(child: Text(l10n.statsEmpty)),
        ),
      );
    }
    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].value),
    ];
    final maxY = points.fold<double>(1, (m, e) => math.max(m, e.value));
    final df = DateFormat.MMMd(locale);

    return SectionCard(
      title: l10n.statsUsageOverTime,
      child: SizedBox(
        height: 180,
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: maxY * 1.15,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 38,
                  getTitlesWidget: (v, meta) => Text(
                    v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : v.toInt().toString(),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  interval: (points.length / 4).ceilToDouble(),
                  getTitlesWidget: (v, meta) {
                    final i = v.round();
                    if (i < 0 || i >= points.length) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(df.format(points[i].key),
                          style: theme.textTheme.bodySmall),
                    );
                  },
                ),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                preventCurveOverShooting: true,
                color: _accent,
                barWidth: 2,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: _accent.withValues(alpha: 0.15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── By Material (donut + metric toggle) ────────────────────────────────────────────

class ByMaterialCard extends StatefulWidget {
  const ByMaterialCard({super.key, required this.data});

  final StatsComputed data;

  @override
  State<ByMaterialCard> createState() => _ByMaterialCardState();
}

class _ByMaterialCardState extends State<ByMaterialCard> {
  StatMetric _metric = StatMetric.weight;

  static const _palette = [
    Color(0xFF22C55E), Color(0xFF3B82F6), Color(0xFFF59E0B),
    Color(0xFFEF4444), Color(0xFFA855F7), Color(0xFF14B8A6),
    Color(0xFFEC4899), Color(0xFF84CC16),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entries = widget.data.byMaterial.entries.toList()
      ..sort((a, b) => _metric.of(b.value).compareTo(_metric.of(a.value)));
    final total = entries.fold<num>(0, (s, e) => s + _metric.of(e.value));

    return SectionCard(
      title: l10n.statsByMaterialTitle,
      trailing: MetricToggle(
        value: _metric,
        onChanged: (m) => setState(() => _metric = m),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 32,
                sections: [
                  for (var i = 0; i < entries.length; i++)
                    PieChartSectionData(
                      value: _metric.of(entries[i].value).toDouble(),
                      color: _palette[i % _palette.length],
                      radius: 22,
                      showTitle: false,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < entries.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(
                          child: LegendDot(
                            color: _palette[i % _palette.length],
                            text: entries[i].key,
                          ),
                        ),
                        Text(
                          '${_metric.format(_metric.of(entries[i].value))} · ${total == 0 ? 0 : (_metric.of(entries[i].value) / total * 100).round()}%',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Success by Material ─────────────────────────────────────────────────────

class SuccessByMaterialCard extends StatelessWidget {
  const SuccessByMaterialCard({super.key, required this.data});

  final StatsComputed data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entries = data.byMaterial.entries.toList()
      ..sort((a, b) => b.value.successRate.compareTo(a.value.successRate));
    return SectionCard(
      title: l10n.statsSuccessByMaterial,
      child: BarList(
        rows: [
          for (final e in entries)
            (
              label: e.key,
              value: '${e.value.successRate.round()}% (${e.value.prints})',
              fraction: e.value.successRate / 100,
              color: _accent,
            ),
        ],
      ),
    );
  }
}

// ── Color Distribution (donut of actual colors) ──────────────────────────

class ColorDistributionCard extends StatelessWidget {
  const ColorDistributionCard({super.key, required this.data});

  final StatsComputed data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final entries = data.gramsByColor.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) {
      return SectionCard(
        title: l10n.statsColorDistribution,
        child: SizedBox(height: 50, child: Center(child: Text(l10n.statsEmpty))),
      );
    }
    final total = entries.fold<double>(0, (s, e) => s + e.value);
    final top = entries.take(8).toList();
    final moreCount = entries.length - top.length;

    return SectionCard(
      title: l10n.statsColorDistribution,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 1,
                        centerSpaceRadius: 34,
                        sections: [
                          for (final e in entries)
                            PieChartSectionData(
                              value: e.value,
                              color: colorFromHex(e.key) ?? theme.disabledColor,
                              radius: 20,
                              showTitle: false,
                            ),
                        ],
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(fmtGrams(total),
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        Text(l10n.statsColorsCount(entries.length),
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in top)
                      _ColorChip(
                        color: colorFromHex(e.key) ?? theme.disabledColor,
                        label: '${(e.value / total * 100).round()}%',
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (moreCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(l10n.statsMoreCount(moreCount),
                  style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

/// Color swatch + percentage label (readable, with border for white/black).
class _ColorChip extends StatelessWidget {
  const _ColorChip({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: theme.dividerColor),
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

// ── Bar histograms (duration / habits / time of day) ──────────────────

/// Shared bar chart with X-axis labels.
class _BarHistogram extends StatelessWidget {
  const _BarHistogram({required this.values, required this.labels, this.everyLabel = 1});

  final List<double> values;
  final List<String> labels;

  /// Show X-axis label every [everyLabel] bar (spacing).
  final int everyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxY = values.fold<double>(1, math.max);
    return SizedBox(
      height: 170,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY * 1.2,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(enabled: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (v, meta) =>
                    v == meta.max ? const SizedBox.shrink() : Text(v.toInt().toString(),
                        style: theme.textTheme.bodySmall),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (v, meta) {
                  final i = v.round();
                  if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                  if (i % everyLabel != 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(labels[i], style: theme.textTheme.bodySmall),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < values.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: values[i],
                  color: _accent,
                  width: 10,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                ),
              ]),
          ],
        ),
      ),
    );
  }
}

class DurationHistogramCard extends StatelessWidget {
  const DurationHistogramCard({super.key, required this.data});

  final StatsComputed data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SectionCard(
      title: l10n.statsPrintDuration,
      child: _BarHistogram(
        values: data.durationBuckets.map((e) => e.toDouble()).toList(),
        labels: durationBucketLabels,
      ),
    );
  }
}

class HabitsCard extends StatefulWidget {
  const HabitsCard({super.key, required this.data, required this.locale});

  final StatsComputed data;
  final String locale;

  @override
  State<HabitsCard> createState() => _HabitsCardState();
}

class _HabitsCardState extends State<HabitsCard> {
  StatMetric _metric = StatMetric.weight;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Short weekday names in user's locale.
    final symbols = DateFormat.E(widget.locale).dateSymbols.STANDALONESHORTWEEKDAYS;
    final labels = [for (var i = 1; i <= 7; i++) symbols[i % 7]];
    return SectionCard(
      title: l10n.statsPrintHabits,
      trailing: MetricToggle(
        value: _metric,
        onChanged: (m) => setState(() => _metric = m),
      ),
      child: _BarHistogram(
        values: [for (final b in widget.data.byWeekday) _metric.of(b).toDouble()],
        labels: labels,
      ),
    );
  }
}

class TimeOfDayCard extends StatelessWidget {
  const TimeOfDayCard({super.key, required this.data});

  final StatsComputed data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SectionCard(
      title: l10n.statsPrintTimeOfDay,
      child: _BarHistogram(
        values: data.byHour.map((e) => e.toDouble()).toList(),
        labels: [
          for (var h = 0; h < 24; h++)
            h % 6 == 0 ? '${h.toString().padLeft(2, '0')}:00' : '',
        ],
        everyLabel: 6,
      ),
    );
  }
}
