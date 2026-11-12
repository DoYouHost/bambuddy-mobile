import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// A progress ring: a [track] circle in the shorter side, and an arc of
/// [value] (0–1) in [color] from 12 o'clock with round ends. The screen saver
/// and the statistics drew it apart before; on their square canvases this is
/// the same pixels, and at zero no arc is drawn at all.
class ProgressRingPainter extends CustomPainter {
  const ProgressRingPainter({
    required this.value,
    required this.color,
    required this.track,
    required this.stroke,
  });

  final double value;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - stroke) / 2;
    Paint line(Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = c;
    canvas.drawCircle(center, radius, line(track));
    if (value <= 0) return;
    // One colour: a sweep gradient wraps around where the round cap reaches
    // back past 12 o'clock, and painted a bright blob at the start.
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * value,
      false,
      line(color)..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(ProgressRingPainter old) =>
      old.value != value ||
      old.color != color ||
      old.track != track ||
      old.stroke != stroke;
}
