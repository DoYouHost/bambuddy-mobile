import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// The two things [ChipsOrSelect] holds; public only because its type names it.
enum ChipsOrSelectSlot { chips, select }

/// [chips] while they fit in [maxRows] rows, the [select] once they do not.
///
/// A row of choice chips is the quickest pick for a few options and takes the
/// screen for many: the fleet of one person is two rows and of another is six,
/// and at a large text size the same fleet is twice that. Whether the chips fit
/// depends on their labels, the width and the text scale, so it is **measured
/// from the real layout** and not guessed from a count: the chips are laid out,
/// their rows counted, and the select takes their place when there are too many.
///
/// Both are built and both laid out, so that neither is left without a size for
/// whatever walks the render tree; only the shown one is painted, hit-tested,
/// read by a screen reader and reachable with a keyboard. The keyboard part
/// trails the layout by one frame: the render object says which is shown, and
/// the other is then excluded from focus.
///
/// **Limits:** it needs a bounded width, and a parent that lays its child out
/// normally (a `Column`, a `Padding`), since it answers no dry layout, intrinsic
/// size or baseline. [chips] is a horizontal [Wrap] aligned to the start, whose
/// runs are counted by the offsets its children land at.
class ChipsOrSelect extends StatefulWidget {
  ChipsOrSelect({
    super.key,
    required this.chips,
    required this.select,
    this.maxRows = 2,
  }) : assert(
         chips.direction == Axis.horizontal &&
             chips.crossAxisAlignment == WrapCrossAlignment.start,
         'rows are counted by the offsets of a start-aligned horizontal Wrap',
       );

  final Wrap chips;
  final Widget select;
  final int maxRows;

  @override
  State<ChipsOrSelect> createState() => _ChipsOrSelectState();
}

class _ChipsOrSelectState extends State<ChipsOrSelect> {
  /// Which one the focus is open to, as of the last frame.
  bool _selectShown = false;

  /// Which one the last layout showed, and whether a frame's end is already
  /// waiting to catch [_selectShown] up with it. Layout can run more than once
  /// before that, so the callback reads the latest answer, not the one it was
  /// queued for.
  bool _wantSelect = false;
  bool _catchUpQueued = false;

  void _onShown({required bool select}) {
    _wantSelect = select;
    if (_catchUpQueued || select == _selectShown) return;
    _catchUpQueued = true;
    // Called from layout: the rebuild waits for the end of the frame.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _catchUpQueued = false;
      if (mounted && _wantSelect != _selectShown) {
        setState(() => _selectShown = _wantSelect);
      }
    });
  }

  @override
  Widget build(BuildContext context) => _Slots(
    chips: ExcludeFocus(excluding: _selectShown, child: widget.chips),
    select: ExcludeFocus(excluding: !_selectShown, child: widget.select),
    maxRows: widget.maxRows,
    onShown: _onShown,
  );
}

class _Slots
    extends SlottedMultiChildRenderObjectWidget<ChipsOrSelectSlot, RenderBox> {
  const _Slots({
    required this.chips,
    required this.select,
    required this.maxRows,
    required this.onShown,
  });

  final Widget chips;
  final Widget select;
  final int maxRows;
  final void Function({required bool select}) onShown;

  @override
  Iterable<ChipsOrSelectSlot> get slots => ChipsOrSelectSlot.values;

  @override
  Widget? childForSlot(ChipsOrSelectSlot slot) => switch (slot) {
    ChipsOrSelectSlot.chips => chips,
    ChipsOrSelectSlot.select => select,
  };

  @override
  SlottedContainerRenderObjectMixin<ChipsOrSelectSlot, RenderBox>
  createRenderObject(BuildContext context) =>
      _RenderChipsOrSelect(maxRows, onShown);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderChipsOrSelect)
        ..maxRows = maxRows
        ..onShown = onShown;
}

class _RenderChipsOrSelect extends RenderBox
    with SlottedContainerRenderObjectMixin<ChipsOrSelectSlot, RenderBox> {
  _RenderChipsOrSelect(this._maxRows, this.onShown);

  int _maxRows;
  set maxRows(int value) {
    if (value == _maxRows) return;
    _maxRows = value;
    markNeedsLayout();
  }

  void Function({required bool select}) onShown;

  RenderBox? _shown;

  /// The [RenderWrap] under [box]: the chips sit inside the focus exclusion.
  static RenderWrap? _wrapUnder(RenderObject box) {
    if (box is RenderWrap) return box;
    RenderWrap? found;
    box.visitChildren((child) => found ??= _wrapUnder(child));
    return found;
  }

  /// The runs of [wrap]: the distinct offsets its children were put at.
  static int _rows(RenderWrap wrap) {
    final tops = <double>{};
    for (var c = wrap.firstChild; c != null;) {
      final data = c.parentData! as WrapParentData;
      tops.add(data.offset.dy);
      c = data.nextSibling;
    }
    return tops.length;
  }

  @override
  void performLayout() {
    assert(
      constraints.hasBoundedWidth,
      'ChipsOrSelect needs a bounded width: the select fills it',
    );
    final chips = childForSlot(ChipsOrSelectSlot.chips)!
      ..layout(constraints.loosen(), parentUsesSize: true);
    // Both are laid out, so that neither is left without a size for whatever
    // walks the render tree (a test finder, the semantics and debug tools);
    // only one is shown.
    final select = childForSlot(ChipsOrSelectSlot.select)!
      ..layout(
        constraints.loosen().tighten(width: constraints.maxWidth),
        parentUsesSize: true,
      );
    final showSelect = _rows(_wrapUnder(chips)!) > _maxRows;
    final shown = showSelect ? select : chips;
    _shown = shown;
    onShown(select: showSelect);
    // The width of the slot, so a short row of chips starts at the left as the
    // wrap alone would have.
    size = constraints.constrain(Size(constraints.maxWidth, shown.size.height));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final shown = _shown;
    if (shown != null) context.paintChild(shown, offset);
  }

  @override
  bool paintsChild(RenderBox child) => child == _shown;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      _shown?.hitTest(result, position: position) ?? false;

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    final shown = _shown;
    if (shown != null) visitor(shown);
  }
}
