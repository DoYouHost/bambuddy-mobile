import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// One object's footprint inside an [ObjectPickMask], in mask-pixel
/// coordinates — everything the plate overlay needs to draw and label the real
/// shape instead of a badge over its center.
class PickedObjectShape {
  const PickedObjectShape({
    required this.id,
    required this.bounds,
    required this.fill,
    required this.outline,
    required this.labelAnchor,
    required this.labelSpan,
  });

  final int id;
  final Rect bounds;

  /// The region as a union of scanline rectangles. Fill it, never stroke it:
  /// stroking would draw every scanline's edges as well.
  final Path fill;

  /// The region's border as loose unit segments (`x1,y1,x2,y2, …`) for
  /// [Canvas.drawRawPoints] with [ui.PointMode.lines] — the outline is only
  /// ever stroked, so stitching them into loops would buy nothing but the
  /// question of which loop a corner-touching pixel belongs to.
  final Float32List outline;

  /// Middle of the shape's widest scanline — inside the shape even when it is
  /// a ring or a C, where the centroid would land on the plate instead.
  final Offset labelAnchor;

  /// Width (mask px) of that scanline: how much room the ID label has.
  final double labelSpan;
}

/// The slicer's object-ID mask for the plate being printed
/// (`GET /printers/{id}/cover?view=pick`): a render of the plate from the same
/// top-down camera as `view=top`, in which every pixel carries the id of the
/// object printed there, encoded as `r + (g << 8) + (b << 16)`. Same decoding
/// as the web client's `pickObjectIdAt`.
///
/// It is the only source of an object's real outline — `/print/objects` gives
/// a center point and nothing else.
class ObjectPickMask {
  const ObjectPickMask._(this.width, this.height, this._ids, this.shapes);

  final int width;
  final int height;

  /// Object id per pixel, row-major; 0 where the plate shows through.
  final Int32List _ids;

  final Map<int, PickedObjectShape> shapes;

  /// Decodes the mask PNG. Null when it holds no objects at all — the caller
  /// then falls back as it does for a server with no mask to give.
  static Future<ObjectPickMask?> decode(Uint8List png) async {
    final codec = await ui.instantiateImageCodec(png);
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (rgba == null) return null;
        return fromRgba(rgba.buffer.asUint8List(), image.width, image.height);
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  static ObjectPickMask? fromRgba(Uint8List rgba, int width, int height) {
    if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
      return null;
    }
    final ids = Int32List(width * height);
    for (var i = 0, p = 0; i < ids.length; i++, p += 4) {
      if (rgba[p + 3] == 0) continue;
      ids[i] = rgba[p] | (rgba[p + 1] << 8) | (rgba[p + 2] << 16);
    }
    final shapes = _buildShapes(ids, width, height);
    return shapes.isEmpty ? null : ObjectPickMask._(width, height, ids, shapes);
  }

  /// Where the mask lands inside [box] when painted with [BoxFit.contain] —
  /// the fit the top-down render uses, so the two stay registered and a tap
  /// resolves against the shape the user aimed at.
  ({double scale, Offset origin}) placementIn(Size box) {
    final scale = math.min(box.width / width, box.height / height);
    return (
      scale: scale,
      origin: Offset(
        (box.width - width * scale) / 2,
        (box.height - height * scale) / 2,
      ),
    );
  }

  /// Object id at [local] within [box]; null on the plate and on the letterbox
  /// bars, where clamping to the nearest edge would name a part nobody pointed
  /// at. [tolerance] (logical px) is finger slop: it only ever rescues a tap
  /// that hit no object at all.
  int? idAt(Offset local, Size box, {double tolerance = 0}) {
    final place = placementIn(box);
    if (!(place.scale > 0)) return null;
    final x = ((local.dx - place.origin.dx) / place.scale).floor();
    final y = ((local.dy - place.origin.dy) / place.scale).floor();
    if (x < 0 || y < 0 || x >= width || y >= height) return null;
    final id = _ids[y * width + x];
    if (id != 0) return id;
    final radius = (tolerance / place.scale).round();
    return radius <= 0 ? null : _nearestId(x, y, radius);
  }

  /// Closest object within [radius] mask px of ([x], [y]), searched as growing
  /// rings so the first hit is the closest one.
  int? _nearestId(int x, int y, int radius) {
    for (var r = 1; r <= radius; r++) {
      for (var dy = -r; dy <= r; dy++) {
        final py = y + dy;
        if (py < 0 || py >= height) continue;
        final row = py * width;
        // Only the ring's own edge: the inside was covered by smaller r.
        final step = (dy.abs() == r) ? 1 : 2 * r;
        for (var dx = -r; dx <= r; dx += step) {
          final px = x + dx;
          if (px < 0 || px >= width) continue;
          final id = _ids[row + px];
          if (id != 0) return id;
        }
      }
    }
    return null;
  }
}

/// Walks the mask row by row, collecting each object's scanline runs into a
/// fill path, its borders into loose segments, and its widest run as the label
/// anchor — one pass over the pixels for all three.
Map<int, PickedObjectShape> _buildShapes(Int32List ids, int width, int height) {
  final builders = <int, _ShapeBuilder>{};
  for (var y = 0; y < height; y++) {
    final row = y * width;
    var x = 0;
    while (x < width) {
      final id = ids[row + x];
      if (id == 0) {
        x++;
        continue;
      }
      var end = x + 1;
      while (end < width && ids[row + end] == id) {
        end++;
      }
      final shape = builders[id] ??= _ShapeBuilder(id);
      shape.addRun(x, y, end - x);
      // Vertical borders: the run is maximal, so both ends abut something else.
      shape.addSegment(x, y, x, y + 1);
      shape.addSegment(end, y, end, y + 1);
      // Horizontal borders are per pixel — the neighbouring row can change id
      // in the middle of this run.
      for (var px = x; px < end; px++) {
        if (y == 0 || ids[row - width + px] != id) {
          shape.addSegment(px, y, px + 1, y);
        }
        if (y == height - 1 || ids[row + width + px] != id) {
          shape.addSegment(px, y + 1, px + 1, y + 1);
        }
      }
      x = end;
    }
  }
  return {
    for (final builder in builders.values)
      builder.id: builder.build(
        (x, y) => ids[y.floor() * width + x.floor()] == builder.id,
      ),
  };
}

class _ShapeBuilder {
  _ShapeBuilder(this.id);

  final int id;
  final Path _fill = Path();
  final List<double> _outline = [];
  double _left = double.infinity, _top = double.infinity;
  double _right = 0, _bottom = 0;

  /// Widest run seen, and the first and last of the *adjoining* rows reaching
  /// that width — their midpoint keeps the label centred on a rectangular part,
  /// where every row ties and "the first widest" would pin it to the top edge.
  /// Rows across a gap are not tied in: on a ring the top and bottom edge are
  /// equally wide and their midpoint is the hole.
  int _span = 0;
  double _firstCenter = 0, _lastCenter = 0;
  int _firstRow = 0, _lastRow = 0;

  void addRun(int x, int y, int length) {
    _fill.addRect(
      Rect.fromLTWH(x.toDouble(), y.toDouble(), length.toDouble(), 1),
    );
    _left = math.min(_left, x.toDouble());
    _top = math.min(_top, y.toDouble());
    _right = math.max(_right, (x + length).toDouble());
    _bottom = math.max(_bottom, (y + 1).toDouble());
    if (length > _span) {
      _span = length;
      _firstCenter = _lastCenter = x + length / 2;
      _firstRow = _lastRow = y;
    } else if (length == _span && y == _lastRow + 1) {
      _lastCenter = x + length / 2;
      _lastRow = y;
    }
  }

  void addSegment(int x1, int y1, int x2, int y2) => _outline.addAll([
    x1.toDouble(),
    y1.toDouble(),
    x2.toDouble(),
    y2.toDouble(),
  ]);

  /// [covers] answers whether a mask point still belongs to this object — the
  /// midpoint of two rows can fall outside a part that zigzags between them,
  /// and a label drawn over the plate would point at nothing.
  PickedObjectShape build(bool Function(double x, double y) covers) {
    var anchor = Offset(
      (_firstCenter + _lastCenter) / 2,
      (_firstRow + _lastRow) / 2 + 0.5,
    );
    if (!covers(anchor.dx, anchor.dy)) {
      anchor = Offset(_firstCenter, _firstRow + 0.5);
    }
    return PickedObjectShape(
      id: id,
      bounds: Rect.fromLTRB(_left, _top, _right, _bottom),
      fill: _fill,
      outline: Float32List.fromList(_outline),
      labelAnchor: anchor,
      labelSpan: _span.toDouble(),
    );
  }
}
