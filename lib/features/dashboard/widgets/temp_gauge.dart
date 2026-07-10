import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Circular temperature gauge: a full background track with a rounded accent arc
/// filled proportionally to [fraction] (0..1), starting at the top and sweeping
/// clockwise. Matches the design's 34×34 ring (r14, stroke 3.2). The fill
/// animates smoothly when the value changes (live temperature updates).
class TempGauge extends StatelessWidget {
  const TempGauge({
    super.key,
    required this.fraction,
    required this.color,
    required this.trackColor,
    this.size = 38,
    this.strokeWidth = 3.2,
    this.centerText,
    this.centerIcon,
    this.centerColor,
  });

  final double fraction;
  final Color color;
  final Color trackColor;
  final double size;
  final double strokeWidth;

  /// Optional small label drawn in the middle of the ring (e.g. the target
  /// temperature, or "-" when unset). Ignored when [centerIcon] is set.
  final String? centerText;

  /// Optional glyph drawn in the middle of the ring instead of [centerText]
  /// (e.g. chamber cooling/heating).
  final IconData? centerIcon;
  final Color? centerColor;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: fraction.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (_, value, _) => SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size.square(size),
              painter: _GaugePainter(
                fraction: value,
                color: color,
                trackColor: trackColor,
                strokeWidth: strokeWidth,
              ),
            ),
            if (centerIcon != null)
              Icon(centerIcon, size: 15, color: centerColor ?? color)
            else if (centerText != null)
              Text(
                centerText!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                  color: centerColor ?? color,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.fraction,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double fraction;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.width - strokeWidth) / 2;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = trackColor;
    canvas.drawCircle(center, radius, track);

    if (fraction <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, // start at top
      2 * math.pi * fraction,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth;
}
