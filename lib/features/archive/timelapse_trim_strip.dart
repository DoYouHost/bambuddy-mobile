import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/diagnostics/log_tag.dart';
import '../common/dash_progress.dart';

/// Filmstrip, trim range and playhead in one control.
///
/// Keeping them apart meant reading a time off a slider and looking for it in
/// a strip above — the frames are the timeline, so the handles belong on them.
///
/// Three gestures share the surface: a drag that starts within
/// [_grabRadius] of either handle moves that handle, anything else scrubs the
/// playhead, and a tap seeks. The handles win ties because they are the only
/// gesture that cannot be repeated elsewhere.
class TimelapseTrimStrip extends StatefulWidget {
  const TimelapseTrimStrip({
    super.key,
    required this.frames,
    required this.duration,
    required this.trim,
    required this.minClip,
    required this.onTrimChanged,
    required this.onTrimCommitted,
    required this.onSeek,
    this.position,
    this.loading = false,
  });

  /// Evenly spaced frames across the whole recording; empty while they load.
  final List<Uint8List> frames;

  /// Length of the recording in seconds. The strip's full width.
  final double duration;

  /// Selected range in seconds.
  final RangeValues trim;

  /// Shortest range the handles may close to.
  final double minClip;

  final ValueChanged<RangeValues> onTrimChanged;

  /// Fires once when a handle drag ends, with the edge that moved, in
  /// seconds. Once per gesture, so a seek per dragged pixel cannot flood the
  /// decoder with flushes.
  ///
  /// The edge is reported rather than the range because by the time a drag
  /// ends the caller's own copy of the range has already been updated — it has
  /// nothing left to compare against to tell which handle the user held.
  final ValueChanged<double> onTrimCommitted;

  final ValueChanged<double> onSeek;

  /// Playhead position in seconds; null hides the line (no preview running).
  final double? position;

  /// Whether the frames are still being rendered server-side.
  final bool loading;

  /// Width of one trim handle, and therefore the margin at each end of the
  /// timeline it is parked in.
  static const handleWidth = 12.0;

  /// Keys for the parts whose rendered rectangles carry a requirement: a
  /// handle must never cover the playhead or the frames, and the frames must
  /// not move when the trim does. Tests assert on the laid-out geometry
  /// rather than recomputing this widget's own arithmetic.
  static const framesKey = ValueKey('timelapse.trim.frames');
  static const dimStartKey = ValueKey('timelapse.trim.dim.start');
  static const dimEndKey = ValueKey('timelapse.trim.dim.end');
  static const playheadKey = ValueKey('timelapse.trim.playhead');
  static const startHandleKey = ValueKey('timelapse.trim.handle.start');
  static const endHandleKey = ValueKey('timelapse.trim.handle.end');

  @override
  State<TimelapseTrimStrip> createState() => _TimelapseTrimStripState();
}

enum _Grab { start, end, playhead }

class _TimelapseTrimStripState extends State<TimelapseTrimStrip> {
  static const _height = 72.0;

  /// Corner rounding shared by the strip and the outer edge of its handles.
  static const radius = 8.0;

  /// How close to a handle a touch must land to move it instead of scrubbing.
  static const _grabRadius = 24.0;

  _Grab? _grab;

  /// Where the dragged handle was last put, in seconds.
  ///
  /// Read at the end of the drag instead of `widget.trim`: the parent only
  /// hands the new range back on its next build, which need not happen before
  /// the finger lifts. Trusting the property there reported the edge as it was
  /// when the gesture started.
  double? _draggedTo;

  /// Width of the timeline itself: the strip minus a handle's width at each
  /// end, so a handle parked at either extreme sits in the margin instead of
  /// over the frames.
  ///
  /// The inset is **fixed**, not taken from where the handles currently are.
  /// Deriving it from the selection re-laid the frames out on every drag —
  /// the strip stretched as you trimmed — and left the time axis disagreeing
  /// with the pixels: the playhead spent the first fraction of a second
  /// clamped at the edge before it appeared to move at all.
  double _trackWidth(double width) =>
      math.max(1.0, width - 2 * TimelapseTrimStrip.handleWidth);

  static const _trackLeft = TimelapseTrimStrip.handleWidth;

  double _seconds(double dx, double width) =>
      ((dx - _trackLeft) / _trackWidth(width) * widget.duration)
          .clamp(0, widget.duration);

  double _x(double seconds, double width) => widget.duration <= 0
      ? _trackLeft
      : _trackLeft + seconds / widget.duration * _trackWidth(width);

  void _begin(double dx, double width) {
    final startX = _x(widget.trim.start, width);
    final endX = _x(widget.trim.end, width);
    final toStart = (dx - startX).abs();
    final toEnd = (dx - endX).abs();
    _grab = switch ((toStart, toEnd)) {
      _ when toStart <= _grabRadius && toStart <= toEnd => _Grab.start,
      _ when toEnd <= _grabRadius => _Grab.end,
      _ => _Grab.playhead,
    };
    _update(dx, width);
  }

  void _update(double dx, double width) {
    final at = _seconds(dx, width);
    switch (_grab) {
      // The bounds are held apart with max/min rather than passed straight to
      // clamp: on a recording shorter than [TimelapseTrimStrip.minClip] the
      // limits cross, and clamp throws from inside a gesture callback.
      case _Grab.start:
        final limit = math.max(0.0, widget.trim.end - widget.minClip);
        _draggedTo = at.clamp(0.0, limit);
        widget.onTrimChanged(RangeValues(_draggedTo!, widget.trim.end));
      case _Grab.end:
        final limit = math.min(
          widget.duration,
          widget.trim.start + widget.minClip,
        );
        _draggedTo = at.clamp(limit, widget.duration);
        widget.onTrimChanged(RangeValues(widget.trim.start, _draggedTo!));
      case _Grab.playhead:
        widget.onSeek(
          at.clamp(widget.trim.start, math.max(widget.trim.start, widget.trim.end)),
        );
      case null:
        break;
    }
  }

  void _end() {
    final grab = _grab;
    final edge = _draggedTo;
    _grab = null;
    _draggedTo = null;
    if (edge != null && (grab == _Grab.start || grab == _Grab.end)) {
      widget.onTrimCommitted(edge);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: _height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final track = _trackWidth(width);
          final startX = _x(widget.trim.start, width);
          final endX = _x(widget.trim.end, width);
          final position = widget.position;
          const hw = TimelapseTrimStrip.handleWidth;

          return logTag(
            'timelapse_edit.trim',
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              // On tap *up*, not down: a press that turns into a handle drag
              // would otherwise have already yanked the playhead to wherever
              // the finger landed before the drag gesture won the arena.
              onTapUp: (d) {
                _grab = _Grab.playhead;
                _update(d.localPosition.dx, width);
                _grab = null;
              },
              onHorizontalDragStart: (d) => _begin(d.localPosition.dx, width),
              onHorizontalDragUpdate: (d) => _update(d.localPosition.dx, width),
              onHorizontalDragEnd: (_) => _end(),
              onHorizontalDragCancel: _end,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(radius),
                      ),
                    ),
                  ),
                  // Every frame of the recording, across the whole track and
                  // laid out from the track alone — trimming must not move or
                  // rescale them, or the strip stops being a timeline.
                  Positioned(
                    key: TimelapseTrimStrip.framesKey,
                    left: _trackLeft,
                    width: track,
                    top: 0,
                    bottom: 0,
                    child: _Frames(
                      frames: widget.frames,
                      loading: widget.loading,
                    ),
                  ),
                  // What the cut discards stays visible but dimmed, as in the
                  // web editor: that is how you see whether the cut lands
                  // where you meant it to.
                  Positioned(
                    key: TimelapseTrimStrip.dimStartKey,
                    left: _trackLeft,
                    width: (startX - _trackLeft).clamp(0.0, track),
                    top: 0,
                    bottom: 0,
                    child: const ColoredBox(color: Colors.black54),
                  ),
                  Positioned(
                    key: TimelapseTrimStrip.dimEndKey,
                    left: endX,
                    width: (_trackLeft + track - endX).clamp(0.0, track),
                    top: 0,
                    bottom: 0,
                    child: const ColoredBox(color: Colors.black54),
                  ),
                  if (position != null)
                    Positioned(
                      key: TimelapseTrimStrip.playheadKey,
                      // Centred on the true time, kept inside the track by its
                      // own half-width — a single pixel of correction at the
                      // very ends, not the axis-wide inset that used to hold
                      // the line still for the first moments of playback.
                      left: (_x(position, width) - 1).clamp(
                        _trackLeft,
                        math.max(_trackLeft, _trackLeft + track - 2),
                      ),
                      width: 2,
                      top: 0,
                      bottom: 0,
                      child: const ColoredBox(color: Colors.white),
                    ),
                  Positioned(
                    left: startX - hw,
                    width: (endX - startX + 2 * hw).clamp(0.0, width),
                    top: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: scheme.primary, width: 2),
                        borderRadius: BorderRadius.circular(radius),
                      ),
                    ),
                  ),
                  // Just outside the selection's edges, so a handle never
                  // covers a frame that is being kept, nor the playhead.
                  _Handle(
                    key: TimelapseTrimStrip.startHandleKey,
                    x: startX - hw,
                    width: hw,
                    color: scheme.primary,
                    leading: true,
                  ),
                  _Handle(
                    key: TimelapseTrimStrip.endHandleKey,
                    x: endX,
                    width: hw,
                    color: scheme.primary,
                    leading: false,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle({
    super.key,
    required this.x,
    required this.width,
    required this.color,
    required this.leading,
  });

  final double x;
  final double width;
  final Color color;

  /// Which end of the selection this is. Only the outer corners are rounded,
  /// matching the strip's own; a radius on the inner side would let the ground
  /// through the corner pixels, which reads as a half-transparent handle.
  ///
  /// Deliberately no grip line down the middle: in green over frames it was
  /// indistinguishable from the playhead, and looked like the playhead showing
  /// through the handle.
  final bool leading;

  @override
  Widget build(BuildContext context) => Positioned(
    left: x,
    width: width,
    top: 0,
    bottom: 0,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(leading ? _TimelapseTrimStripState.radius : 0),
          right: Radius.circular(leading ? 0 : _TimelapseTrimStripState.radius),
        ),
      ),
    ),
  );
}

/// The frames themselves, or a placeholder of the same height so the control
/// does not resize when they arrive.
class _Frames extends StatelessWidget {
  const _Frames({required this.frames, required this.loading});

  final List<Uint8List> frames;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (frames.isEmpty) {
      return ColoredBox(
        color: scheme.surfaceContainerHigh,
        child: loading
            ? const Center(
                child: DashSpinner(size: 20),
              )
            : null,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        // Without this the row hands each frame a loose height, so the image
        // sizes itself to its own aspect ratio inside the tile's width and
        // sits letterboxed in the middle instead of filling the strip.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final frame in framesFitting(frames, constraints.maxWidth))
            Expanded(
              child: Image.memory(
                frame,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
        ],
      ),
    );
  }
}

/// As many of [frames] as fit across [width] at [minFrameWidth], each one the
/// closest the server rendered to the middle of the tile that will show it.
///
/// The server renders a fixed count sized for a desktop-width strip; squeezing
/// all of them onto a phone leaves each a sliver too narrow to recognise, and
/// the point of the strip is telling one moment of the print from another.
///
/// Which frame goes in which tile is not free choice: the tiles are drawn at
/// equal width across the whole recording, so tile `i` of `fits` covers the
/// slice `[i / fits, (i + 1) / fits]` of it, and frame `j` of `n` was rendered
/// at `j / n` of it (`timelapse_processor.py`: `timestamp = i * duration /
/// count`). Picking `frames[i * n ~/ fits]` — the frame at the tile's *start* —
/// slides every picture towards the beginning and drops the tail entirely: at
/// 14 frames in 6 tiles the last tile covers 83–100 % but showed 78.6 %, and
/// nothing past that was on screen to trim against. Rounding to the tile's
/// midpoint keeps each picture under the moment it depicts; the last tile also
/// gets the last frame rendered as long as the server keeps sending fewer than
/// three per tile, which at its fourteen it does on any strip we draw.
List<T> framesFitting<T>(
  List<T> frames,
  double width, {
  double minFrameWidth = 56,
}) {
  if (frames.isEmpty) return frames;
  final fits = (width / minFrameWidth).floor().clamp(1, frames.length);
  if (fits >= frames.length) return frames;
  final n = frames.length;
  return [
    for (var i = 0; i < fits; i++)
      frames[(n * (i + 0.5) / fits).round().clamp(0, n - 1)],
  ];
}
