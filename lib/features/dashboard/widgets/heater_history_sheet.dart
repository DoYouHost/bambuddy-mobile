import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/diagnostics/log_tag.dart';
import '../../../core/models/heater_history.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers.dart';
import 'history_chart_parts.dart';

/// One selectable sensor: the server's key plus the label the card already
/// shows for that tile, so the sheet doesn't translate sensor names twice.
typedef HeaterKindOption = ({String kind, String label});

/// Query key for [heaterHistoryDataProvider]: which sensor over which window.
typedef HeaterHistoryQuery = ({int printerId, int hours, String kind});

/// Fetches heater history for the given printer/sensor/window. Auto-disposes
/// when the sheet closes; keyed by hours and kind so switching either refetches.
final heaterHistoryDataProvider = FutureProvider.autoDispose
    .family<HeaterHistory, HeaterHistoryQuery>((ref, q) async {
  return ref.watch(heaterHistoryRepositoryProvider).fetch(
        q.printerId,
        hours: q.hours,
        // Only the sensor on screen. A week of one heater is already ~10k
        // samples; asking for all of them at once to make the sensor switch
        // instant would multiply that by three series nobody is looking at.
        kinds: [q.kind],
      );
});

/// Whether the temperature tiles offer their chart shortcut at all: the server
/// has the route and this session may read it. Invalidated by the sheet after a
/// failed fetch, so a 404 or a 403 takes the icon away instead of leaving a
/// shortcut that can only ever show an error.
final heaterHistorySupportedProvider = FutureProvider<bool>(
  (ref) => ref.watch(heaterHistoryRepositoryProvider).supportsHistory(),
);

/// Opens the heater history chart (nozzle / bed / chamber) as a bottom sheet.
/// [kinds] are the sensors this printer actually shows, [initialKind] the tile
/// the chart icon was tapped on.
Future<void> showHeaterHistorySheet(
  BuildContext context, {
  required int printerId,
  required List<HeaterKindOption> kinds,
  required String initialKind,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => HeaterHistorySheet(
      printerId: printerId,
      kinds: kinds,
      initialKind: initialKind,
    ),
  );
}

class HeaterHistorySheet extends ConsumerStatefulWidget {
  const HeaterHistorySheet({
    super.key,
    required this.printerId,
    required this.kinds,
    required this.initialKind,
  });

  final int printerId;
  final List<HeaterKindOption> kinds;
  final String initialKind;

  @override
  ConsumerState<HeaterHistorySheet> createState() => _HeaterHistorySheetState();
}

class _HeaterHistorySheetState extends ConsumerState<HeaterHistorySheet> {
  static const _ranges = [6, 24, 48, 168];

  late String _kind = widget.kinds.any((k) => k.kind == widget.initialKind)
      ? widget.initialKind
      : widget.kinds.first.kind;
  int _hours = 24;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final query = (printerId: widget.printerId, hours: _hours, kind: _kind);
    // A failure is also an observation about the route: re-ask whether the
    // shortcut should still be on the tiles.
    ref.listen(heaterHistoryDataProvider(query), (_, next) {
      if (next.hasError) ref.invalidate(heaterHistorySupportedProvider);
    });
    final async = ref.watch(heaterHistoryDataProvider(query));

    return logTag(
      'sheet.heater_history',
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.heaterHistoryTitle,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (widget.kinds.length > 1) ...[
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    for (final k in widget.kinds)
                      ButtonSegment(value: k.kind, label: Text(k.label)),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (s) => setState(() => _kind = s.first),
                ),
                const SizedBox(height: 8),
              ],
              HistoryRangeSelector(
                ranges: _ranges,
                selected: _hours,
                labelOf: (h) => sensorRangeLabel(l10n, h),
                onChanged: (h) => setState(() => _hours = h),
              ),
              const SizedBox(height: 16),
              async.when(
                loading: () => const SizedBox(
                  height: 260,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, _) => SizedBox(
                  height: 260,
                  child: Center(child: Text(l10n.sensorHistoryError)),
                ),
                data: (history) => _Content(
                  series: history.seriesFor(_kind),
                  color: _kindColor(_kind),
                  hours: _hours,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.heaterHistoryRecordingInfo,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Same hue per sensor as the live tile reads: hot end orange, bed blue,
  /// chamber green.
  static Color _kindColor(String kind) => switch (kind) {
        'bed' => const Color(0xFF3B82F6),
        'chamber' => const Color(0xFF10B981),
        _ => const Color(0xFFF97316),
      };
}

class _Content extends StatelessWidget {
  const _Content({
    required this.series,
    required this.color,
    required this.hours,
  });

  final HeaterSeries? series;
  final Color color;
  final int hours;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final points = thinnedForChart(series?.points ?? const <HeaterHistoryPoint>[]);

    final values = <FlSpot>[
      for (final p in points)
        if (p.value case final v?)
          FlSpot(p.recordedAt.millisecondsSinceEpoch.toDouble(), v),
    ];
    final targets = <FlSpot>[
      for (final p in points)
        if (p.target case final t?)
          FlSpot(p.recordedAt.millisecondsSinceEpoch.toDouble(), t),
    ];

    if (values.isEmpty) {
      return SizedBox(
        height: 260,
        child: Center(child: Text(l10n.sensorHistoryEmpty)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            HistoryStat(
              label: l10n.sensorHistoryCurrent,
              value: _fmt(values.last.y),
            ),
            HistoryStat(
              label: l10n.sensorHistoryAverage,
              value: _fmt(series?.avgValue),
            ),
            HistoryStat(
              label: l10n.sensorHistoryMin,
              value: _fmt(series?.minValue),
            ),
            HistoryStat(
              label: l10n.sensorHistoryMax,
              value: _fmt(series?.maxValue),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _Legend(color: color, hasTarget: targets.isNotEmpty),
        const SizedBox(height: 8),
        SizedBox(
          height: 220,
          child: LineChart(_chartData(context, values, targets)),
        ),
      ],
    );
  }

  static String _fmt(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)}°C';

  LineChartData _chartData(
    BuildContext context,
    List<FlSpot> values,
    List<FlSpot> targets,
  ) {
    final theme = Theme.of(context);
    final axis = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    // Fix X domain to the full window so a sparse series still reads correctly.
    final maxX = DateTime.now().millisecondsSinceEpoch.toDouble();
    final minX = maxX - hours * 3600 * 1000;
    final timeFmt = hours > 24 ? DateFormat.Md() : DateFormat.Hm();

    // Auto-scale to the readings AND the setpoints — a cold nozzle under a 250°
    // target would otherwise push the dashed line off the top of the chart.
    var lo = values.first.y;
    var hi = values.first.y;
    for (final s in [...values, ...targets]) {
      lo = math.min(lo, s.y);
      hi = math.max(hi, s.y);
    }

    return LineChartData(
      minX: minX,
      maxX: maxX,
      minY: math.max(0, lo - 5),
      maxY: hi + 5,
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 36,
            getTitlesWidget: (v, meta) => Text(v.toInt().toString(), style: axis),
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
                timeFmt.format(DateTime.fromMillisecondsSinceEpoch(v.toInt())),
                style: axis,
              ),
            ),
          ),
        ),
      ),
      lineBarsData: [
        if (targets.isNotEmpty)
          LineChartBarData(
            spots: targets,
            isStepLineChart: true,
            color: color.withValues(alpha: 0.55),
            barWidth: 1.5,
            dashArray: const [5, 5],
            dotData: const FlDotData(show: false),
          ),
        LineChartBarData(
          spots: values,
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
    );
  }
}

/// Tells the two lines apart: the solid one is what the sensor read, the dashed
/// one the setpoint that was in force.
class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.hasTarget});

  final Color color;
  final bool hasTarget;

  @override
  Widget build(BuildContext context) {
    if (!hasTarget) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    Widget item(Color c, bool dashed, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 2,
              child: CustomPaint(painter: _LinePainter(c, dashed: dashed)),
            ),
            const SizedBox(width: 6),
            Text(label, style: style),
          ],
        );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        item(color, false, l10n.heaterHistoryReading),
        const SizedBox(width: 16),
        item(color.withValues(alpha: 0.55), true, l10n.heaterHistoryTarget),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  const _LinePainter(this.color, {required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    if (!dashed) {
      canvas.drawLine(Offset(0, size.height / 2),
          Offset(size.width, size.height / 2), paint);
      return;
    }
    const dash = 4.0;
    for (var x = 0.0; x < size.width; x += dash * 2) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset(math.min(x + dash, size.width), size.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.color != color || old.dashed != dashed;
}
