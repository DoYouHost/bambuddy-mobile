import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../wear_geometry.dart';

/// Shrinks its child as the child approaches the rim of a round face: each item is
/// scaled to the chord that is actually lit where it currently is, as Wear OS's own
/// `TransformingLazyColumn` does. A scale, not a narrower inset, because an inset
/// re-lays-out the child (a printer name would re-wrap on every frame of a scroll)
/// while a scale happens at paint time. What it replaces, the rectangle inscribed in
/// the circle, and what each costs is in `docs/wear-geometry.md`.
class WearFaceCurve extends SingleChildRenderObjectWidget {
  const WearFaceCurve({
    super.key,
    required this.face,
    required super.child,
    this.cornerRadius = 0,
  });

  /// The whole display, not the viewport: the curve is a fact about the glass,
  /// and the item has to know where it sits on it rather than where it sits in
  /// whatever box it is being scrolled through.
  final Size face;

  /// How round the items in this list are — see [roundScaleFor]. Nothing by
  /// default: claiming a radius an item does not have puts its square corner
  /// past the chord.
  final double cornerRadius;

  @override
  RenderWearFaceCurve createRenderObject(BuildContext context) =>
      RenderWearFaceCurve(face: face, cornerRadius: cornerRadius);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderWearFaceCurve renderObject,
  ) => renderObject
    ..face = face
    ..cornerRadius = cornerRadius;
}

/// The paint-time half of [WearFaceCurve], modelled on `RenderTransform`: [paint],
/// [applyPaintTransform] and [hitTestChildren] must agree about the matrix, or a
/// button is drawn in one place and pressed in another.
class RenderWearFaceCurve extends RenderProxyBox {
  // Named parameters may not start with `_`, so the private fields are assigned
  // rather than declared as initializing formals — the same reason
  // `wear_transport.dart` waives this lint.
  // ignore_for_file: prefer_initializing_formals
  RenderWearFaceCurve({required Size face, required double cornerRadius})
    : _face = face,
      _cornerRadius = cornerRadius;

  /// Whether the curve can do anything for this item. One taller than the radius has a
  /// corner past the chord wherever it stands, so no scale fits it: it is clipped to
  /// the round-safe band instead, as the rectangle viewport did before the curve.
  bool get clipsToFace => size.height >= _face.shortestSide / 2;

  double get cornerRadius => _cornerRadius;
  double _cornerRadius;
  set cornerRadius(double value) {
    if (_cornerRadius == value) return;
    _cornerRadius = value;
    markNeedsPaint();
  }

  Size get face => _face;
  Size _face;
  set face(Size value) {
    if (_face == value) return;
    _face = value;
    markNeedsPaint();
  }

  /// Recomputed on every read, not cached from the last [paint]: a cached one goes
  /// stale for an item that stopped being painted, and `localToGlobal` reads it too
  /// through [applyPaintTransform].
  Matrix4 get _effectiveTransform {
    if (clipsToFace) return Matrix4.identity();

    final top = localToGlobal(Offset.zero).dy - _face.height / 2;
    final bottom = top + size.height;
    final scale = roundScaleFor(
      diameter: _face.shortestSide,
      itemWidth: size.width,
      top: top,
      bottom: bottom,
      cornerRadius: _cornerRadius,
    );
    // Held by the edge facing the middle of the face, so the item gives way
    // outwards and keeps peeking in from the rim; centred horizontally, because
    // sideways there is nowhere to give way to.
    final anchor = roundCurveAnchor(top, bottom) - top;
    return Matrix4.identity()
      ..translateByDouble(size.width / 2, anchor, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-size.width / 2, -anchor, 0, 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (clipsToFace) return _paintClipped(context, offset);
    final transform = _effectiveTransform;
    final scale = transform.getMaxScaleOnAxis();
    // Past the rim there is no glass to draw on and no scale that would help.
    if (scale <= 0) {
      layer = null;
      return;
    }
    if (scale >= 1) {
      layer = null;
      return super.paint(context, offset);
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      transform,
      super.paint,
      oldLayer: layer is TransformLayer ? layer! as TransformLayer : null,
    );
  }

  /// The band an uncurvable item may paint in, in this item's own coordinates.
  ///
  /// `globalToLocal` rather than arithmetic on the paint offset: the item sits
  /// under a scrolling viewport that has pushed layers of its own, and the band
  /// is a fact about the display.
  Rect get _band {
    final margin = _face.shortestSide * roundEdgeFraction;
    return Rect.fromLTRB(
      0,
      globalToLocal(Offset(0, margin)).dy,
      size.width,
      globalToLocal(Offset(0, _face.height - margin)).dy,
    );
  }

  void _paintClipped(PaintingContext context, Offset offset) {
    layer = context.pushClipRect(
      needsCompositing,
      offset,
      _band,
      super.paint,
      oldLayer: layer is ClipRectLayer ? layer! as ClipRectLayer : null,
    );
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      hitTestChildren(result, position: position);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    // A clip that paint honours and hit testing does not is a button nobody can
    // see and anybody can press — on this screen the invisible one would be
    // "stop the print". The viewport used to clip both, because it clipped the
    // whole scroll; an item clipping itself has to do the same.
    if (clipsToFace) {
      final band = _band;
      if (position.dy < band.top || position.dy > band.bottom) return false;
      return super.hitTestChildren(result, position: position);
    }
    return result.addWithPaintTransform(
      transform: _effectiveTransform,
      position: position,
      hitTest: (result, position) =>
          super.hitTestChildren(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.multiply(_effectiveTransform);
}
