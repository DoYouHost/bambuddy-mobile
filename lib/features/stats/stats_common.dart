import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import 'stats_computed.dart';

/// Metric chosen in "Weight / Prints / Time" toggles.
enum StatMetric { weight, prints, time }

extension StatMetricValue on StatMetric {
  /// Extract metric value from bucket [b].
  num of(StatBucket b) => switch (this) {
        StatMetric.weight => b.grams,
        StatMetric.prints => b.prints,
        StatMetric.time => b.seconds,
      };

  String label(AppLocalizations l) => switch (this) {
        StatMetric.weight => l.statsMetricWeight,
        StatMetric.prints => l.statsMetricPrints,
        StatMetric.time => l.statsMetricTime,
      };

  /// Formatted metric value for row label.
  String format(num v) => switch (this) {
        StatMetric.weight => fmtGrams(v.toDouble()),
        StatMetric.prints => '${v.round()}',
        StatMetric.time => fmtDuration(v.round()),
      };
}

/// Section card with fixed header — common wrapper for all widgets.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: t.cardGradient,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: DashTokens.fontUi,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// Metric toggle (Weight / Prints / Time) as compact SegmentedButton.
class MetricToggle extends StatelessWidget {
  const MetricToggle({super.key, required this.value, required this.onChanged});

  final StatMetric value;
  final ValueChanged<StatMetric> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SegmentedButton<StatMetric>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: [
        for (final m in StatMetric.values)
          ButtonSegment(value: m, label: Text(m.label(l10n))),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    ).tagged('stats.metric');
  }
}

/// Ring gauge (0–100 percent) with label in center.
class RingGauge extends StatelessWidget {
  const RingGauge({
    super.key,
    required this.percent,
    required this.color,
    required this.label,
  });

  final double percent;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return SizedBox(
      width: 110,
      height: 110,
      child: CustomPaint(
        painter: _RingPainter(
          percent: percent.clamp(0, 100).toDouble(),
          color: color,
          track: t.gaugeTrack,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: DashTokens.fontUi,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.percent, required this.color, required this.track});

  final double percent;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      percent / 100 * 2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.percent != percent || old.color != color || old.track != track;
}

/// Horizontal color-text legend (dot + label).
class LegendDot extends StatelessWidget {
  const LegendDot({super.key, required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: DashTokens.fontUi,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: t.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Duration histogram bucket labels (upper bounds — common PL/EN).
const durationBucketLabels = <String>[
  '<30min', '<1h', '<2h', '<4h', '<8h', '<12h', '<24h', '24h+',
];

/// Number to max 2 decimal places, no trailing zeros.
String fmtNum(num v) {
  final d = v.toDouble();
  if (d == d.roundToDouble()) return d.toStringAsFixed(0);
  return d.toStringAsFixed(2);
}

/// Filament: grams below 1 kg, otherwise kilograms.
String fmtGrams(double g) =>
    g >= 1000 ? '${(g / 1000).toStringAsFixed(2)} kg' : '${g.toStringAsFixed(0)} g';

/// Duration from seconds: "9h 31m", "45m", "30s".
String fmtDuration(int seconds) {
  if (seconds <= 0) return '0m';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h > 0) return m > 0 ? '${h}h ${m}m' : '${h}h';
  if (m > 0) return '${m}m';
  return '${seconds}s';
}

