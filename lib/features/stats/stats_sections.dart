import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/models/archive_stats.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../common/hex_color.dart';
import 'stats_common.dart';
import 'stats_computed.dart';
import 'stats_providers.dart';

// ── Failure Analysis ────────────────────────────────────────────────────────

class FailureAnalysisCard extends ConsumerWidget {
  const FailureAnalysisCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
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
          child: Center(
            child: Text(l10n.statsLoadFailed,
                style: TextStyle(fontFamily: DashTokens.fontUi, color: t.textSecondary)),
          ),
        ),
        data: (f) {
          final rateColor = f.failureRate <= 5
              ? t.accentGreen
              : (f.failureRate <= 15 ? t.accentOrange : t.danger);
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
                    style: TextStyle(
                      fontFamily: DashTokens.fontMono,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: rateColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      rangeLabel,
                      style: TextStyle(
                        fontFamily: DashTokens.fontUi,
                        fontSize: 12,
                        color: t.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                l10n.statsFailedOfTotal(f.failedPrints, f.totalPrints),
                style: TextStyle(
                  fontFamily: DashTokens.fontUi,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: t.textTertiary,
                ),
              ),
              if (reasons.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    l10n.statsNoFailures,
                    style: TextStyle(fontFamily: DashTokens.fontUi, color: t.textSecondary),
                  ),
                )
              else ...[
                const SizedBox(height: 14),
                Text(
                  l10n.statsTopFailureReasons,
                  style: TextStyle(
                    fontFamily: DashTokens.fontUi,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: t.accentGreenInk,
                  ),
                ),
                const SizedBox(height: 6),
                for (final e in reasons.take(5))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.key,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: DashTokens.fontUi,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: t.textSecondary,
                            ),
                          ),
                        ),
                        Text(
                          '${e.value}',
                          style: TextStyle(
                            fontFamily: DashTokens.fontMono,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: t.textPrimary,
                          ),
                        ),
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

  /// Widest window shown (GitHub-style ~1 year). "All time" on a
  /// multi-year history would otherwise build `weeks*7` `Container`s eagerly
  /// (this grid isn't lazy/virtualized) — cap to the most recent window
  /// instead of growing unbounded.
  static const _maxWeeks = 53;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final days = data.printsByDay;
    final maxCount = days.values.fold<int>(1, math.max);

    // Range: from Monday of the week with earliest print to today, capped to
    // the most recent [_maxWeeks].
    final sorted = days.keys.toList()..sort();
    final first = sorted.first;
    final last = sorted.last;
    final fullStartMonday = first.subtract(Duration(days: first.weekday - 1));
    final fullWeeks = (last.difference(fullStartMonday).inDays ~/ 7) + 1;
    final weeks = fullWeeks > _maxWeeks ? _maxWeeks : fullWeeks;
    final startMonday = fullWeeks > _maxWeeks
        ? fullStartMonday.add(Duration(days: (fullWeeks - _maxWeeks) * 7))
        : fullStartMonday;

    final track = t.gaugeTrack;
    final labelStyle = TextStyle(
      fontFamily: DashTokens.fontUi,
      fontSize: 10,
      color: t.textTertiary,
    );

    Color cellColor(DateTime day) {
      final n = days[day] ?? 0;
      if (n == 0) return track;
      return Color.lerp(track, t.accentGreen, (n / maxCount).clamp(0.2, 1.0))!;
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
              Text(l10n.statsHeatmapLess, style: labelStyle),
              const SizedBox(width: 6),
              for (final frac in [0.0, 0.33, 0.66, 1.0])
                Container(
                  width: 13,
                  height: 13,
                  margin: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    color: frac == 0 ? track : Color.lerp(track, t.accentGreen, frac)!,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              const SizedBox(width: 6),
              Text(l10n.statsHeatmapMore, style: labelStyle),
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
    // Server ≥ 1.2.5.2 only — stays absent rather than reading 0 kWh elsewhere.
    final hungriest = data.hungriest;
    if (hungriest?.energyKwh != null) {
      add(Icons.bolt_outlined, l10n.statsMostEnergy,
          l10n.statsKwh(hungriest!.energyKwh!.toStringAsFixed(2)),
          hungriest.printName);
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
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: t.accentGreenInk),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: DashTokens.fontUi,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: t.textSecondary,
                  ),
                ),
                if (sub != null)
                  Text(
                    sub!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: DashTokens.fontUi,
                      fontSize: 11.5,
                      color: t.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontFamily: DashTokens.fontMono,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
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
    final t = DashTokens.of(context);
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      rows[i].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: DashTokens.fontUi,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    rows[i].value,
                    style: TextStyle(
                      fontFamily: DashTokens.fontMono,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: t.textTertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: rows[i].fraction.clamp(0, 1).toDouble(),
                  minHeight: 8,
                  color: rows[i].color ?? t.accentGreen,
                  backgroundColor: t.gaugeTrack,
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
    final t = DashTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: DashTokens.fontUi,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: t.textTertiary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: DashTokens.fontMono,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: t.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ── Usage / energy over time (line charts) ──────────────────────────────

class UsageOverTimeCard extends StatelessWidget {
  const UsageOverTimeCard({super.key, required this.data, required this.locale});

  final StatsComputed data;
  final String locale;

  @override
  Widget build(BuildContext context) => _OverTimeChart(
        title: AppLocalizations.of(context).statsUsageOverTime,
        points: data.usageOverTime,
        locale: locale,
        color: DashTokens.of(context).accentGreen,
        formatY: (v) =>
            v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : v.toInt().toString(),
      );
}

/// Energy drawn per day. Only reachable when [StatsComputed.hasEnergyData] —
/// the readings come per-print from `/archives/slim` on servers from 1.2.5.2,
/// and an older one (or an install that never had energy tracking on) would
/// otherwise get a flat zero line reading as "you used no power".
class EnergyOverTimeCard extends StatelessWidget {
  const EnergyOverTimeCard({super.key, required this.data, required this.locale});

  final StatsComputed data;
  final String locale;

  @override
  Widget build(BuildContext context) => _OverTimeChart(
        title: AppLocalizations.of(context).statsEnergyOverTime,
        points: data.energyOverTime,
        locale: locale,
        color: DashTokens.of(context).accentBlue,
        // kWh per day lands in single digits, where the filament chart's
        // integer axis would collapse every day into "0" or "1".
        formatY: (v) => v.toStringAsFixed(v >= 10 ? 0 : 1),
      );
}

class _OverTimeChart extends StatelessWidget {
  const _OverTimeChart({
    required this.title,
    required this.points,
    required this.locale,
    required this.color,
    required this.formatY,
  });

  final String title;
  final List<MapEntry<DateTime, double>> points;
  final String locale;
  final Color color;
  final String Function(double) formatY;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final axisStyle = TextStyle(
      fontFamily: DashTokens.fontMono,
      fontSize: 10.5,
      color: t.textTertiary,
    );
    if (points.length < 2) {
      return SectionCard(
        title: title,
        child: SizedBox(
          height: 60,
          child: Center(
            child: Text(l10n.statsEmpty,
                style: TextStyle(fontFamily: DashTokens.fontUi, color: t.textSecondary)),
          ),
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
      title: title,
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
                  getTitlesWidget: (v, meta) =>
                      Text(formatY(v), style: axisStyle),
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
                      child: Text(df.format(points[i].key), style: axisStyle),
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
                color: color,
                barWidth: 2,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: color.withValues(alpha: 0.15),
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
    final t = DashTokens.of(context);
    final entries = widget.data.byMaterial.entries.toList()
      ..sort((a, b) => _metric.of(b.value).compareTo(_metric.of(a.value)));
    final total = entries.fold<num>(0, (s, e) => s + _metric.of(e.value));

    // Two ways a slice stops being worth its own colour, both pooled into one
    // neutral arc at the end of the ring:
    //
    //  - under [pooledShare] it renders as a two-pixel splinter, which reads as
    //    a rendering glitch rather than as data;
    //  - past the palette it would *reuse* a colour already on the ring, so two
    //    legend rows would carry the same dot and neither would identify its
    //    own arc (the old `i % _palette.length`).
    //
    // The legend keeps every row and every number — nothing is hidden, the tail
    // just stops pretending to be individually findable on a 120px ring.
    const pooledShare = 0.02;
    bool pooled(int i) =>
        i >= _palette.length ||
        (total > 0 && _metric.of(entries[i].value) / total < pooledShare);
    Color colorFor(int i) => pooled(i) ? t.textTertiary : _palette[i];

    final pooledTotal = [
      for (var i = 0; i < entries.length; i++)
        if (pooled(i)) _metric.of(entries[i].value),
    ].fold<num>(0, (s, v) => s + v);

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
                    if (!pooled(i))
                      PieChartSectionData(
                        value: _metric.of(entries[i].value).toDouble(),
                        color: colorFor(i),
                        radius: 22,
                        showTitle: false,
                      ),
                  if (pooledTotal > 0)
                    PieChartSectionData(
                      value: pooledTotal.toDouble(),
                      color: t.textTertiary,
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
                            color: colorFor(i),
                            text: entries[i].key,
                          ),
                        ),
                        Text(
                          '${_metric.format(_metric.of(entries[i].value))} · ${total == 0 ? 0 : (_metric.of(entries[i].value) / total * 100).round()}%',
                          style: TextStyle(
                            fontFamily: DashTokens.fontMono,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: t.textTertiary,
                          ),
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
    final t = DashTokens.of(context);
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
              color: t.accentGreen,
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
    final t = DashTokens.of(context);
    final entries = data.gramsByColor.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) {
      return SectionCard(
        title: l10n.statsColorDistribution,
        child: SizedBox(
          height: 50,
          child: Center(
            child: Text(l10n.statsEmpty,
                style: TextStyle(fontFamily: DashTokens.fontUi, color: t.textSecondary)),
          ),
        ),
      );
    }
    final total = entries.fold<double>(0, (s, e) => s + e.value);
    final top = entries.take(8).toList();
    final moreCount = entries.length - top.length;

    // Colours under this share are drawn as one neutral slice instead of
    // individually. At 16 colours the tail lands at one or two pixels a piece,
    // which reads as noise on the ring and as banding between neighbours —
    // and the legend never named them anyway (it stops at eight, with the
    // "+N more" line below). Grouping keeps every proportion honest while
    // leaving the ring legible.
    const sliverShare = 0.02;
    final sliverTotal = entries
        .where((e) => e.value / total < sliverShare)
        .fold<double>(0, (s, e) => s + e.value);
    final drawn = entries.where((e) => e.value / total >= sliverShare);

    return SectionCard(
      title: l10n.statsColorDistribution,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The percentages are shares of filament *mass*, which nothing on the
          // card said — leaving the reader to guess between mass, print count
          // and time, all three of which this screen also reports.
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              l10n.statsColorShareHint,
              style: TextStyle(
                fontFamily: DashTokens.fontUi,
                fontSize: 11.5,
                color: t.textTertiary,
              ),
            ),
          ),
          Row(
            children: [
              SizedBox(
                width: 132,
                height: 132,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 1,
                        // Wide enough that the readout below fits inside the
                        // hole; the ring keeps its 20px thickness (44+20 = 64,
                        // inside the 66 half-extent).
                        centerSpaceRadius: 44,
                        sections: [
                          for (final e in drawn)
                            PieChartSectionData(
                              value: e.value,
                              color: colorFromHex(e.key) ?? t.textTertiary,
                              radius: 20,
                              showTitle: false,
                            ),
                          if (sliverTotal > 0)
                            PieChartSectionData(
                              value: sliverTotal,
                              color: t.textTertiary,
                              radius: 20,
                              showTitle: false,
                            ),
                        ],
                      ),
                    ),
                    // Bounded to the square that fits inside the hole
                    // (side = r·√2 ≈ 62 for r = 44) and scaled down rather than
                    // overflowing, so a long total like "10.24 kg" can never
                    // paint over the ring the way it used to.
                    SizedBox(
                      width: 60,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              fmtGrams(total),
                              style: TextStyle(
                                fontFamily: DashTokens.fontMono,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: t.textPrimary,
                              ),
                            ),
                            Text(
                              l10n.statsColorsCount(entries.length),
                              style: TextStyle(
                                fontFamily: DashTokens.fontUi,
                                fontSize: 11,
                                color: t.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
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
                        color: colorFromHex(e.key) ?? t.textTertiary,
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
              child: Text(
                l10n.statsMoreCount(moreCount),
                style: TextStyle(
                  fontFamily: DashTokens.fontUi,
                  fontSize: 11.5,
                  color: t.textTertiary,
                ),
              ),
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
    final t = DashTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: t.subCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.subCardBorder),
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
              border: Border.all(color: t.cardBorder),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: DashTokens.fontMono,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: t.textPrimary,
            ),
          ),
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
    final t = DashTokens.of(context);
    final axisStyle = TextStyle(
      fontFamily: DashTokens.fontMono,
      fontSize: 10.5,
      color: t.textTertiary,
    );
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
                getTitlesWidget: (v, meta) => v == meta.max
                    ? const SizedBox.shrink()
                    : Text(v.toInt().toString(), style: axisStyle),
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
                    child: Text(labels[i], style: axisStyle),
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
                  color: t.accentGreen,
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
