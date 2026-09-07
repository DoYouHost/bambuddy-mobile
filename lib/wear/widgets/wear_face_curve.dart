import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../wear_geometry.dart';

/// Shrinks its child as the child approaches the rim of a round face.
///
/// The alternative to giving a scrolling screen the rectangle inscribed in the
/// circle. That rectangle is easy to be sure of — nothing inside it can ever be
/// off the glass — but it costs 36% of the height of a display that had none to
/// spare, and it hands every row the width available at the *worst* point of
/// the viewport, including the rows crossing the middle where the whole diameter
/// is lit.
///
/// Here each item is instead scaled to the chord that is actually lit where it
/// currently is, which is what Wear OS itself does: `TransformingLazyColumn`
/// shrinks and fades items toward the edges "because they are more difficult to
/// see near the top and bottom of a round screen". An item at the middle is
/// untouched; one on its way out shrinks and leaves rather than being cut.
///
/// A scale and not a narrower inset, for a reason worth keeping: an inset
/// re-lays-out the child, so a printer name would re-wrap and ellipsize
/// differently on every frame of a scroll. A scale happens at paint time and the
/// text keeps the metrics it was laid out with.
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

/// The paint-time half of [WearFaceCurve].
///
/// Modelled on Flutter's own `RenderTransform`: the same three methods have to
/// agree about the matrix — [paint], [applyPaintTransform] (which is what
/// `localToGlobal` and therefore every test assertion reads) and
/// [hitTestChildren] (which is what decides where a tap lands). Getting one of
/// them wrong is a button that is drawn in one place and pressed in another.
class RenderWearFaceCurve extends RenderProxyBox {
  // Named parameters may not start with `_`, so the private fields are assigned
  // rather than declared as initializing formals — the same reason
  // `wear_transport.dart` waives this lint.
  // ignore_for_file: prefer_initializing_formals
  RenderWearFaceCurve({required Size face, required double cornerRadius})
    : _face = face,
      _cornerRadius = cornerRadius;

  /// Whether the curve can do anything for this item.
  ///
  /// An item taller than the radius has a corner past the chord wherever it
  /// stands — there is no scale that fits it, only one that shrinks it to
  /// nothing. A fault card with three lines of description and two buttons is
  /// one of these. Rather than leave it unscaled and free to paint past the
  /// bezel, it is clipped to the round-safe band, which is precisely what the
  /// rectangle viewport did for it before the curve existed: for these items
  /// nothing changes at all.
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

  /// Recomputed on every read rather than cached from the last [paint].
  ///
  /// A cached one goes stale the moment an item stops being painted, which is
  /// exactly what happens to the item scrolling off the top — and the transform
  /// is not only paint: `localToGlobal` reads it through [applyPaintTransform],
  /// so a stale scale reports an item as sitting somewhere it is no longer
  /// drawn. The walk it costs is a handful of matrices for the few items on a
  /// watch face.
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
