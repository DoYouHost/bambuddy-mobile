import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../wear_shape.dart';

/// The scroll position, drawn the way Wear OS draws it: a short arc hugging the
/// right side of the round face (a straight bar on a square one).
///
/// Google Play rejects a watch app whose scrollable screens show nothing while
/// they scroll, and a plain Material [Scrollbar] is the wrong answer here — a
/// straight bar pinned to the right edge of a round display is itself clipped by
/// the bezel, trading one rejection for the other.
///
/// Purely a readout: it never scrolls anything, so the caller wraps it in an
/// [IgnorePointer] and the painter takes no hit tests.
class WearScrollIndicator extends StatelessWidget {
  const WearScrollIndicator({
    super.key,
    required this.controller,
    required this.opacity,
    required this.shape,
  });

  final ScrollController controller;

  /// Fade driven by the scroll view: the indicator is for the moment of
  /// scrolling, not permanent chrome on a 1.4" screen.
  final Animation<double> opacity;

  final WearShape shape;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      // The controller for the offset, the fade for the alpha; either one moving
      // has to repaint.
      animation: Listenable.merge([controller, opacity]),
      builder: (context, _) {
        final metrics = _metrics();
        if (metrics == null || opacity.value <= 0) {
          return const SizedBox.shrink();
        }
        return CustomPaint(
          size: Size.infinite,
          painter: _WearScrollIndicatorPainter(
            metrics: metrics,
            shape: shape,
            opacity: opacity.value,
            color: Theme.of(context).colorScheme.primary,
          ),
        );
      },
    );
  }

  /// Where the view sits in its content, or null while there is nothing to
  /// indicate — no attached position yet, or content that fits on the face.
  _ScrollFraction? _metrics() {
    if (!controller.hasClients) return null;
    // `position` asserts a single attached view; during a route transition two
    // are briefly attached, and the one being built is the last.
    final position = controller.positions.last;
    if (!position.hasContentDimensions ||
        !position.hasPixels ||
        position.maxScrollExtent <= 0) {
      return null;
    }
    final content = position.maxScrollExtent + position.viewportDimension;
    return _ScrollFraction(
      offset: (position.pixels / position.maxScrollExtent).clamp(0.0, 1.0),
      visible: content <= 0
          ? 1
          : (position.viewportDimension / content).clamp(0.0, 1.0),
    );
  }
}

/// How much of the content is on screen, and how far down it the view has got.
@immutable
class _ScrollFraction {
  const _ScrollFraction({required this.offset, required this.visible});

  /// 0 at the top of the scroll, 1 at the bottom.
  final double offset;

  /// Share of the whole content the viewport shows — the length of the thumb.
  final double visible;
}

class _WearScrollIndicatorPainter extends CustomPainter {
  const _WearScrollIndicatorPainter({
    required this.metrics,
    required this.shape,
    required this.opacity,
    required this.color,
  });

  final _ScrollFraction metrics;
  final WearShape shape;
  final double opacity;
  final Color color;

  /// Sweep of the whole track on a round face. Wide enough to read as a scale,
  /// short enough to stay clear of the top and bottom of the circle.
  static const _trackSweep = 70 * math.pi / 180;

  /// A thumb this short still reads as a position rather than a dot, however
  /// long the content behind it is.
  static const _minThumbSweep = 8 * math.pi / 180;

  static const _stroke = 4.0;

  /// Gap between the track and the edge of the glass.
  static const _edgeGap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.20 * opacity);
    final thumb = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: opacity);

    if (shape == WearShape.round) {
      _paintArc(canvas, size, track, thumb);
    } else {
      _paintBar(canvas, size, track, thumb);
    }
  }

  void _paintArc(Canvas canvas, Size size, Paint track, Paint thumb) {
    final radius = size.shortestSide / 2 - _edgeGap - _stroke / 2;
    if (radius <= 0) return;
    final bounds = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: radius,
    );
    // Angles run clockwise from 3 o'clock, so the track is centred on the right
    // edge of the face.
    final start = -_trackSweep / 2;
    canvas.drawArc(bounds, start, _trackSweep, false, track);

    final thumbSweep = math.max(_trackSweep * metrics.visible, _minThumbSweep);
    final thumbStart = start + (_trackSweep - thumbSweep) * metrics.offset;
    canvas.drawArc(bounds, thumbStart, thumbSweep, false, thumb);
  }

  void _paintBar(Canvas canvas, Size size, Paint track, Paint thumb) {
    final x = size.width - _edgeGap - _stroke / 2;
    final top = size.height * 0.2;
    final length = size.height * 0.6;
    if (length <= 0) return;
    canvas.drawLine(Offset(x, top), Offset(x, top + length), track);

    final thumbLength = math.max(length * metrics.visible, _stroke * 3);
    final thumbTop = top + (length - thumbLength) * metrics.offset;
    canvas.drawLine(
      Offset(x, thumbTop),
      Offset(x, thumbTop + thumbLength),
      thumb,
    );
  }

  @override
  bool shouldRepaint(_WearScrollIndicatorPainter old) =>
      old.metrics.offset != metrics.offset ||
      old.metrics.visible != metrics.visible ||
      old.opacity != opacity ||
      old.shape != shape ||
      old.color != color;
}
