import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/diagnostics/log_tag.dart';
import '../../../core/format/datetime_format.dart';
import '../../../core/models/ams_history.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers.dart';
import '../../common/dash_async.dart';
import '../../common/dash_sheet.dart';
import 'history_chart_parts.dart';

/// Which metric the AMS history chart is showing.
enum AmsHistoryMetric { humidity, temperature }

/// Query key for [amsHistoryDataProvider]: identifies the AMS unit and window.
typedef AmsHistoryQuery = ({int printerId, int amsId, int hours});

/// Fetches AMS history for the given unit/window. Auto-disposes when the sheet
/// closes; keyed by hours so switching the range refetches.
final amsHistoryDataProvider = FutureProvider.autoDispose
    .family<AmsHistory, AmsHistoryQuery>((ref, q) async {
  return ref
      .watch(amsHistoryRepositoryProvider)
      .fetch(q.printerId, q.amsId, hours: q.hours);
});

/// Whether the AMS humidity/temperature chips open a chart at all: the route is
/// there and this session may read it. Invalidated by the sheet after a failed
/// fetch, so a 403 leaves plain readings rather than a tap that only errors.
final amsHistorySupportedProvider = FutureProvider<bool>(
  (ref) => ref.watch(amsHistoryRepositoryProvider).supportsHistory(),
);

/// AMS "Good"/"Fair" status thresholds. Chart reference lines. Sourced from
/// server settings, with the same keys and defaults as bambuddy.
typedef AmsThresholds = ({
  double humidityGood,
  double humidityFair,
  double tempGood,
  double tempFair,
});

const _defaultAmsThresholds = (
  humidityGood: 40.0,
  humidityFair: 60.0,
  tempGood: 28.0,
  tempFair: 35.0,
);

final amsThresholdsProvider = FutureProvider<AmsThresholds>((ref) async {
  final s = await ref.watch(serverSettingsProvider.future);
  double read(String key, double fallback) {
    final v = s[key];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  return (
    humidityGood: read('ams_humidity_good', _defaultAmsThresholds.humidityGood),
    humidityFair: read('ams_humidity_fair', _defaultAmsThresholds.humidityFair),
    tempGood: read('ams_temp_good', _defaultAmsThresholds.tempGood),
    tempFair: read('ams_temp_fair', _defaultAmsThresholds.tempFair),
  );
});

/// Opens the AMS temperature/humidity history chart as a bottom sheet.
Future<void> showAmsHistorySheet(
  BuildContext context, {
  required int printerId,
  required int amsId,
  required String amsLabel,
  AmsHistoryMetric initialMetric = AmsHistoryMetric.humidity,
}) {
  return dashSheet<void>(
    context,
    builder: (_) => AmsHistorySheet(
      printerId: printerId,
      amsId: amsId,
      amsLabel: amsLabel,
      initialMetric: initialMetric,
    ),
  );
}

class AmsHistorySheet extends ConsumerStatefulWidget {
  const AmsHistorySheet({
    super.key,
    required this.printerId,
    required this.amsId,
    required this.amsLabel,
    this.initialMetric = AmsHistoryMetric.humidity,
  });

  final int printerId;
  final int amsId;
  final String amsLabel;
  final AmsHistoryMetric initialMetric;

  @override
  ConsumerState<AmsHistorySheet> createState() => _AmsHistorySheetState();
}

class _AmsHistorySheetState extends ConsumerState<AmsHistorySheet> {
  static const _ranges = [6, 24, 48, 168];

  late AmsHistoryMetric _metric = widget.initialMetric;
  int _hours = 24;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isHumidity = _metric == AmsHistoryMetric.humidity;
    final query = (
      printerId: widget.printerId,
      amsId: widget.amsId,
      hours: _hours,
    );
    // A failure is also an observation about the route: re-ask whether the
    // chips should still open a chart.
    ref.listen(amsHistoryDataProvider(query), (_, next) {
      if (next.hasError) ref.invalidate(amsHistorySupportedProvider);
    });
    final async = ref.watch(amsHistoryDataProvider(query));
    final thresholds =
        ref.watch(amsThresholdsProvider).valueOrNull ?? _defaultAmsThresholds;
    final good =
        isHumidity ? thresholds.humidityGood : thresholds.tempGood;
    final fair =
        isHumidity ? thresholds.humidityFair : thresholds.tempFair;

    return logTag(
      'sheet.ams_history',
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.amsHistoryTitle(widget.amsLabel),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              SegmentedButton<AmsHistoryMetric>(
                segments: [
                  ButtonSegment(
                    value: AmsHistoryMetric.humidity,
                    icon: const Icon(Icons.water_drop_outlined, size: 18),
                    label: Text(l10n.amsHistoryHumidity),
                  ),
                  ButtonSegment(
                    value: AmsHistoryMetric.temperature,
                    icon: const Icon(Icons.thermostat, size: 18),
                    label: Text(l10n.amsHistoryTemperature),
                  ),
                ],
                selected: {_metric},
                onSelectionChanged: (s) => setState(() => _metric = s.first),
              ),
              const SizedBox(height: 8),
              HistoryRangeSelector(
                ranges: _ranges,
                selected: _hours,
                labelOf: (h) => sensorRangeLabel(l10n, h),
                onChanged: (h) => setState(() => _hours = h),
              ),
              const SizedBox(height: 16),
              dashAsyncStrip(
                context,
                async,
                height: 260,
                failureMessage: l10n.sensorHistoryError,
                data: (history) => _Content(
                  history: history,
                  isHumidity: isHumidity,
                  hours: _hours,
                  good: good,
                  fair: fair,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.amsHistoryRecordingInfo,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      )
    );
  }

}

class _Content extends StatelessWidget {
  const _Content({
    required this.history,
    required this.isHumidity,
    required this.hours,
    required this.good,
    required this.fair,
  });

  final AmsHistory history;
  final bool isHumidity;
  final int hours;

  /// "Good"/"Fair" status thresholds for the active metric (reference lines).
  final double good;
  final double fair;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Read the selected metric off each point; skip nulls so gaps don't distort.
    final spots = <FlSpot>[
      for (final p in thinnedForChart(history.points))
        if (_valueOf(p) case final v?)
          FlSpot(p.recordedAt.millisecondsSinceEpoch.toDouble(), v),
    ];

    if (spots.isEmpty) {
      return SizedBox(
        height: 260,
        child: Center(child: Text(l10n.sensorHistoryEmpty)),
      );
    }

    final unit = isHumidity ? '%' : '°C';
    final current = _valueOf(history.points.last);
    final avg = isHumidity ? history.avgHumidity : history.avgTemperature;
    final min = isHumidity ? history.minHumidity : history.minTemperature;
    final max = isHumidity ? history.maxHumidity : history.maxTemperature;
    final color = isHumidity ? const Color(0xFF3B82F6) : const Color(0xFFF97316);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            HistoryStat(
                label: l10n.sensorHistoryCurrent, value: _fmt(current, unit)),
            HistoryStat(
                label: l10n.sensorHistoryAverage, value: _fmt(avg, unit)),
            HistoryStat(label: l10n.sensorHistoryMin, value: _fmt(min, unit)),
            HistoryStat(label: l10n.sensorHistoryMax, value: _fmt(max, unit)),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 220,
          child: LineChart(_chartData(context, spots, color)),
        ),
      ],
    );
  }

  double? _valueOf(AmsHistoryPoint p) => isHumidity ? p.humidity : p.temperature;

  static String _fmt(double? v, String unit) =>
      v == null ? '—' : '${v.toStringAsFixed(unit == '%' ? 0 : 1)}$unit';

  LineChartData _chartData(BuildContext context, List<FlSpot> spots, Color c) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final axis = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    // Fix X domain to the full window so a sparse series still reads correctly.
    final maxX = DateTime.now().millisecondsSinceEpoch.toDouble();
    final minX = maxX - hours * 3600 * 1000;
    final fmt = DateTimeFormats.of(context);
    final axisLabel = hours > 24 ? fmt.dayMonthNumeric : fmt.time;

    // Humidity has a natural 0..100 scale; temperature auto-scales but must keep
    // the Good/Fair lines in view, so widen the range to include them.
    double? minY, maxY;
    if (isHumidity) {
      minY = 0;
      maxY = 100;
    } else {
      var lo = math.min(good, fair);
      var hi = math.max(good, fair);
      for (final s in spots) {
        lo = math.min(lo, s.y);
        hi = math.max(hi, s.y);
      }
      minY = lo - 2;
      maxY = hi + 2;
    }

    return LineChartData(
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      borderData: FlBorderData(show: false),
      extraLinesData: ExtraLinesData(
        horizontalLines: [
          _thresholdLine(good, const Color(0xFF22A352), l10n.amsHistoryGood),
          _thresholdLine(fair, const Color(0xFFD4A017), l10n.amsHistoryFair),
        ],
      ),
      titlesData: FlTitlesData(
        topTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 36,
            getTitlesWidget: (v, meta) => Text(
              v.toInt().toString(),
              style: axis,
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            interval: (maxX - minX) / 4,
            getTitlesWidget: (v, meta) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                axisLabel(
                  DateTime.fromMillisecondsSinceEpoch(v.toInt()),
                ),
                style: axis,
              ),
            ),
          ),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          preventCurveOverShooting: true,
          color: c,
          barWidth: 2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: c.withValues(alpha: 0.15),
          ),
        ),
      ],
    );
  }

  HorizontalLine _thresholdLine(double y, Color color, String label) {
    return HorizontalLine(
      y: y,
      color: color,
      strokeWidth: 1,
      dashArray: const [5, 5],
      label: HorizontalLineLabel(
        show: true,
        alignment: Alignment.topRight,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
        labelResolver: (_) => label,
      ),
    );
  }
}
