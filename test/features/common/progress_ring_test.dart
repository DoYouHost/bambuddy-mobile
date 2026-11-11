import 'dart:ui' as ui;

import 'package:bambuddy_mobile/features/common/progress_ring.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The colour at ([x], [y]) of [painter] drawn on a 100×100 canvas.
Future<Color> pixel(ProgressRingPainter painter, int x, int y) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(100, 100));
  final image = await recorder.endRecording().toImage(100, 100);
  final bytes = (await image.toByteData())!;
  final o = (y * 100 + x) * 4;
  return Color.fromARGB(
    bytes.getUint8(o + 3),
    bytes.getUint8(o),
    bytes.getUint8(o + 1),
    bytes.getUint8(o + 2),
  );
}

void main() {
  const arc = Color(0xFFFF0000);
  const track = Color(0xFF0000FF);
  ProgressRingPainter ring(double value) =>
      ProgressRingPainter(value: value, color: arc, track: track, stroke: 10);

  // (50, 5) is the middle of the stroke at 12 o'clock, (5, 50) at 9 o'clock.
  test('no arc at zero, only the track', () async {
    expect(await pixel(ring(0), 50, 5), track);
  });

  test('the arc starts at 12 o\'clock and runs clockwise', () async {
    expect(await pixel(ring(0.25), 50, 5), arc);
    expect(await pixel(ring(0.25), 95, 50), arc, reason: '3 o\'clock');
    expect(await pixel(ring(0.25), 5, 50), track, reason: 'not yet at 9');
    expect(await pixel(ring(1), 5, 50), arc);
  });

  test('repaints only when something drawn changes', () {
    expect(ring(0.5).shouldRepaint(ring(0.5)), isFalse);
    expect(ring(0.5).shouldRepaint(ring(0.6)), isTrue);
  });
}
