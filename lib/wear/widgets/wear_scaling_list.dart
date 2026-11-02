import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// A port of Wear Compose's `ScalingLazyColumn` (wear compose-foundation 1.7.1),
/// the list Google's Wear OS list guidance prescribes: items shrink and fade
/// toward the top and bottom of the screen, and the list is anchored on the
/// middle. Function and parameter names follow the Kotlin source so the two
/// can be read side by side; `docs/wear-geometry.md` says where each piece is.

/// Side margins of a list, as fractions of the screen width (Google's Wear OS
/// list guidance; Horologist's `ScalingLazyColumnDefaults`): every item sits
/// [wearListSideMargin] in, a text item a further [wearListTextMargin]
/// (`listTextPadding()`), and a title a further [wearListTitleMargin], "to
/// ensure titles don't clip".
const wearListSideMargin = 0.052;
const wearListTextMargin = 0.052;
const wearListTitleMargin = 0.073;

/// `ScalingLazyColumnDefaults.scalingParams()`.
const wearEdgeScale = 0.7;
const wearEdgeAlpha = 0.5;
const _minElementHeight = 0.2;
const _maxElementHeight = 0.6;
const _minTransitionArea = 0.35;
const _maxTransitionArea = 0.55;
const _scaleInterpolator = Cubic(0.3, 0, 0.7, 1);

double _lerp(double start, double stop, double fraction) =>
    start + (stop - start) * fraction;

double _inverseLerp(double start, double stop, double value) =>
    ((value - start) / (stop - start)).clamp(0.0, 1.0);

/// `calculateScaleAndAlpha`: how much an item spanning [itemTop]..[itemBottom]
/// of a [viewportHeight] viewport is scaled and faded.
({double scale, double alpha}) wearScaleAndAlpha({
  required double viewportHeight,
  required double itemTop,
  required double itemBottom,
}) {
  if (viewportHeight <= 0) return (scale: 1, alpha: 1);
  final itemEdgeDistanceFromViewPortEdge = math.min(
    viewportHeight - itemTop,
    itemBottom,
  );
  final itemEdgeAsFractionOfViewPort =
      itemEdgeDistanceFromViewPortEdge / viewportHeight;
  final heightAsFractionOfViewPort = (itemBottom - itemTop) / viewportHeight;
  final sizeRatio = _inverseLerp(
    _minElementHeight,
    _maxElementHeight,
    heightAsFractionOfViewPort,
  );
  final scalingLineAsFractionOfViewPort = _lerp(
    _minTransitionArea,
    _maxTransitionArea,
    sizeRatio,
  );
  if (itemEdgeAsFractionOfViewPort >= scalingLineAsFractionOfViewPort) {
    return (scale: 1, alpha: 1);
  }
  final scalingProgressRaw =
      1 - itemEdgeAsFractionOfViewPort / scalingLineAsFractionOfViewPort;
  final scalingInterpolated = _scaleInterpolator.transform(
    scalingProgressRaw.clamp(0.0, 1.0),
  );
  return (
    scale: _lerp(1, wearEdgeScale, scalingInterpolated),
    alpha: _lerp(1, wearEdgeAlpha, scalingInterpolated),
  );
}

/// Where an item is drawn: shifted by [dy] and scaled by [scale] about its top
/// centre (`graphicsLayer` with `TransformOrigin(0.5f, 0f)` and `translationY`).
class _ItemTransform {
  const _ItemTransform(this.dy, this.scale, this.alpha);
  final double dy;
  final double scale;
  final double alpha;

  Matrix4 matrix(double width) => Matrix4.identity()
    ..translateByDouble(width / 2, dy, 0, 1)
    ..scaleByDouble(scale, scale, 1, 1)
    ..translateByDouble(-width / 2, 0, 0, 1);
}

/// What the list needs from its owner for `AutoCenteringParams()`: the space
/// before the first and after the last child that lets [centerFromIndex] and
/// every later item reach the middle of the viewport. Null where the item it
/// depends on is not laid out yet — the bottom one until the end is near, as
/// the Compose list leaves it at 0 until its last item is visible.
typedef WearAutoCentering = ({double? top, double? bottom});

/// The children of a scaling list. The first and the last child are the
/// auto-centering spacers, which are neither scaled nor counted as items —
/// `discardAutoCenteringListItem`.
class WearScalingSliverList extends SliverList {
  const WearScalingSliverList({
    super.key,
    required super.delegate,
    required this.centerFromIndex,
    required this.gapIndices,
    required this.visible,
    required this.onAutoCentering,
    this.contentPadding,
  });

  /// `autoCentering = null` with this `contentPadding`, the way an
  /// `AlertDialog` lays out its `ScalingLazyColumn`: the space above and below
  /// the items is the padding, and a list shorter than the viewport is centred
  /// in it (`Arrangement.spacedBy(…, Alignment.CenterVertically)`).
  final ({double top, double bottom})? contentPadding;

  /// `AutoCenteringParams.itemIndex`, as a child index of this sliver.
  final int centerFromIndex;

  /// Children that are spacing (`verticalArrangement`) rather than items.
  final Set<int> gapIndices;

  /// False until the auto-centering space is known; items are drawn
  /// transparent until then, as `ScalingLazyColumn` does before it is
  /// initialised, so the list never shows itself at the wrong offset.
  final bool visible;

  final ValueChanged<WearAutoCentering> onAutoCentering;

  @override
  RenderWearScalingSliverList createRenderObject(BuildContext context) =>
      RenderWearScalingSliverList(
        childManager: context as SliverMultiBoxAdaptorElement,
        centerFromIndex: centerFromIndex,
        gapIndices: gapIndices,
        visible: visible,
        onAutoCentering: onAutoCentering,
        contentPadding: contentPadding,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderWearScalingSliverList renderObject,
  ) => renderObject
    ..centerFromIndex = centerFromIndex
    ..gapIndices = gapIndices
    ..visible = visible
    ..onAutoCentering = onAutoCentering
    ..contentPadding = contentPadding;
}

class RenderWearScalingSliverList extends RenderSliverList {
  // Named parameters may not start with `_`, as in `wear_transport.dart`.
  // ignore_for_file: prefer_initializing_formals
  RenderWearScalingSliverList({
    required super.childManager,
    required int centerFromIndex,
    required Set<int> gapIndices,
    required bool visible,
    required this.onAutoCentering,
    ({double top, double bottom})? contentPadding,
  }) : _contentPadding = contentPadding,
       _centerFromIndex = centerFromIndex,
       _gapIndices = gapIndices,
       _visible = visible;

  int get centerFromIndex => _centerFromIndex;
  int _centerFromIndex;
  set centerFromIndex(int value) {
    if (_centerFromIndex == value) return;
    _centerFromIndex = value;
    markNeedsLayout();
  }

  Set<int> get gapIndices => _gapIndices;
  Set<int> _gapIndices;
  set gapIndices(Set<int> value) {
    if (setEquals(_gapIndices, value)) return;
    _gapIndices = value;
    markNeedsLayout();
  }

  bool get visible => _visible;
  bool _visible;
  set visible(bool value) {
    if (_visible == value) return;
    _visible = value;
    markNeedsLayout();
  }

  ValueChanged<WearAutoCentering> onAutoCentering;

  ({double top, double bottom})? get contentPadding => _contentPadding;
  ({double top, double bottom})? _contentPadding;
  set contentPadding(({double top, double bottom})? value) {
    if (_contentPadding == value) return;
    _contentPadding = value;
    markNeedsLayout();
  }

  final _transforms = <RenderBox, _ItemTransform>{};

  bool _isSpacer(int index) =>
      index == 0 || index == (childManager.childCount - 1);

  @override
  void performLayout() {
    super.performLayout();
    _transforms.clear();
    final viewportHeight = constraints.viewportMainAxisExtent;
    // Where this sliver's scroll offset 0 sits in the viewport.
    final origin =
        viewportHeight -
        constraints.remainingPaintExtent -
        constraints.scrollOffset;
    final items = <(RenderBox, int, double)>[];
    bool isGap(int i) => _gapIndices.contains(items[i].$2);
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final index = indexOf(child);
      if (_isSpacer(index)) continue;
      items.add((child, index, origin + childScrollOffset(child)!));
    }
    _reportAutoCentering(viewportHeight, origin);
    if (items.isEmpty) return;

    final centerLine = (viewportHeight / 2).floorToDouble();
    // `findItemNearestCenter`: the first item reaching past the centre line.
    var central = 0;
    for (var i = 0; i < items.length; i++) {
      if (isGap(i)) continue;
      central = i;
      if (items[i].$3 + items[i].$1.size.height > centerLine) break;
    }

    // `calculateItemInfo`: scaled toward the centre line — an item above it
    // keeps its bottom edge, one below keeps its top.
    (double, double) place(int i, double start) {
      final size = items[i].$1.size.height;
      // A gap is `verticalArrangement` spacing: a fixed distance, not an item.
      final (:scale, :alpha) = isGap(i)
          ? (scale: 1.0, alpha: 1.0)
          : wearScaleAndAlpha(
              viewportHeight: viewportHeight,
              itemTop: start,
              itemBottom: start + size,
            );
      final scaledHeight = size * scale;
      final aboveLine = (start + start + size) < viewportHeight;
      final scaledTop = aboveLine ? start + size - scaledHeight : start;
      _transforms[items[i].$1] = _ItemTransform(
        scaledTop - items[i].$3,
        scale,
        _visible ? alpha : 0,
      );
      return (scaledTop, scaledHeight);
    }

    final (centerTop, centerHeight) = place(central, items[central].$3);
    // Go up, then down: each item placed against the scaled edge of the one
    // nearer the centre, so shrinking leaves no gaps.
    var nextItemBottom = centerTop;
    for (var i = central - 1; i >= 0; i--) {
      final (top, _) = place(i, nextItemBottom - items[i].$1.size.height);
      nextItemBottom = top;
    }
    var nextItemTop = centerTop + centerHeight;
    for (var i = central + 1; i < items.length; i++) {
      final (top, height) = place(i, nextItemTop);
      nextItemTop = top + height;
    }
    markNeedsSemanticsUpdate();
  }

  /// `calculateTopAutoCenteringPaddingPx` / `calculateBottomAutoCenteringPaddingPx`
  /// for the `ItemCenter` anchor: the room [centerFromIndex] needs above it, and
  /// the last item below it, to reach the centre line.
  void _reportAutoCentering(double viewportHeight, double origin) {
    if (_contentPadding case final padding?) {
      return _reportPadding(viewportHeight, padding);
    }
    final centerLine = (viewportHeight / 2).floorToDouble();
    double? top;
    double? bottom;
    var before = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final index = indexOf(child);
      if (index == 0) continue;
      if (index == _centerFromIndex) {
        top = math.max(0, centerLine - before - child.size.height / 2);
      }
      if (index < _centerFromIndex) before += child.size.height;
      if (index == childManager.childCount - 2) {
        bottom = math.max(
          0,
          viewportHeight - centerLine - child.size.height / 2,
        );
      }
    }
    if (top == null && bottom == null) return;
    final measured = (top: top, bottom: bottom);
    // Reported after layout: the owner sizes the spacers in a later frame.
    SchedulerBinding.instance.addPostFrameCallback(
      (_) => onAutoCentering(measured),
    );
  }

  /// The padding, plus half of whatever the viewport has left once every item
  /// is laid out — known only when the first and the last one are.
  void _reportPadding(
    double viewportHeight,
    ({double top, double bottom}) padding,
  ) {
    final last = childManager.childCount - 2;
    var content = 0.0;
    var seenFirst = false;
    var seenLast = false;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final index = indexOf(child);
      if (index == 0 || index > last) continue;
      seenFirst |= index == 1;
      seenLast |= index == last;
      content += child.size.height;
    }
    final extra = seenFirst && seenLast
        ? math.max(
                0.0,
                viewportHeight - padding.top - padding.bottom - content,
              ) /
              2
        : 0.0;
    final measured = (top: padding.top + extra, bottom: padding.bottom + extra);
    SchedulerBinding.instance.addPostFrameCallback(
      (_) => onAutoCentering(measured),
    );
  }

  _ItemTransform? _transformOf(RenderBox child) => _transforms[child];

  @override
  void paint(PaintingContext context, Offset offset) {
    for (var next = firstChild; next != null; next = childAfter(next)) {
      final child = next;
      final transform = _transformOf(child);
      final childOffset = offset + Offset(0, childMainAxisPosition(child));
      if (transform == null) {
        // A spacer: nothing to draw.
        continue;
      }
      if (transform.alpha <= 0 || transform.scale <= 0) continue;
      context.pushTransform(
        needsCompositing,
        childOffset,
        transform.matrix(child.size.width),
        (context, offset) {
          if (transform.alpha >= 1) {
            context.paintChild(child, offset);
          } else {
            context.pushOpacity(
              offset,
              (transform.alpha * 255).round(),
              (context, offset) => context.paintChild(child, offset),
            );
          }
        },
      );
    }
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    super.applyPaintTransform(child, transform);
    final item = _transformOf(child);
    if (item != null) transform.multiply(item.matrix(child.size.width));
  }

  @override
  bool hitTestChildren(
    SliverHitTestResult result, {
    required double mainAxisPosition,
    required double crossAxisPosition,
  }) {
    final boxResult = BoxHitTestResult.wrap(result);
    for (var next = lastChild; next != null; next = childBefore(next)) {
      final child = next;
      final item = _transformOf(child);
      if (item == null || item.alpha <= 0) continue;
      final transform = Matrix4.identity();
      applyPaintTransform(child, transform);
      final hit = boxResult.addWithPaintTransform(
        transform: transform,
        position: Offset(crossAxisPosition, mainAxisPosition),
        hitTest: (result, position) =>
            child.hitTest(result, position: position),
      );
      if (hit) return true;
    }
    return false;
  }
}
