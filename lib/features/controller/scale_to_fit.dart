import 'dart:math' as math;

import 'package:dash_kit/dash_kit.dart';
import 'package:material_ui/material_ui.dart';

/// The smallest box the controller's body is laid out in: the body area of the
/// touch panel whose look the controller borrows. A floor, not the target — the
/// screens are designed for a phone in landscape
/// ([docs/single-printer-controller.md]). Below it the whole body shrinks, above
/// it the whole body grows — one factor for every tab, so a button, a font or a
/// gap is the same size wherever it appears.
const controllerBodySize = Size(800, 360);

/// From this system text size a tab that does not fit the box reflows: its
/// cards are rearranged, never scaled down.
const controllerReflowTextScale = dashLargeTextScale;

/// Whether the system text is large enough for [controllerReflowTextScale].
bool controllerLargeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1) >= controllerReflowTextScale;

/// Whether a tab lays itself out as a page of cards as tall as their content
/// ([ControllerPage]): from a large text size, or in a room shorter than the
/// design's. The one question every tab asks, so they switch together.
bool controllerPaged(BuildContext context) =>
    controllerLargeText(context) ||
    (context.dependOnInheritedWidgetOfExactType<ControllerScale>()?.paged ??
        false);

/// Room left over when a label is measured against the space it will get:
/// measuring and rendering can round apart, and a label that just fits would
/// wrap.
const controllerFitSlack = DashSpace.sm;

/// Material 3's size for the icon of a `FilledButton.icon`, which the controller
/// measures labels against and scales with the text.
const controllerButtonIconSize = 18.0;

/// The most the system text size enlarges an icon: the icon's own size, up to
/// 150% of it.
const controllerIconScaleCap = 1.5;

/// An icon's size at the system text size: it grows with the text up to
/// [controllerIconScaleCap], like the icons that take their size from the theme
/// ([ControllerScreen]).
double controllerIconSize(BuildContext context, double base) =>
    base *
    MediaQuery.textScalerOf(
      context,
    ).scale(1).clamp(1.0, controllerIconScaleCap);

/// The print-settings screen's body, laid out in this much room. The screen has a
/// bar above it, so it gets less room than a tab does, and at the tabs' height it
/// would be drawn at 0.95 and every touch target with it. 1.07 on the 891 x 411
/// window.
const controllerPrintBodySize = Size(800, 312);

/// A tab at a large text size: a page of cards as tall as their content, in a
/// scroll view at least as tall as the room. Nothing in [child] may be an
/// `Expanded` or ask for the room's height: a card handed a height of someone's
/// guess is squeezed the day a printer shows more than the guess allowed for, and
/// its buttons go under 48 dp. Always a scroll view, so a tab keeps its state when
/// the window's height crosses its content's.
class ControllerPage extends StatelessWidget {
  const ControllerPage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: box.maxHeight),
        child: child,
      ),
    ),
  );
}

/// Scales [child] uniformly to fill the room it is given: the factor is the
/// largest that keeps [minSize] inside the room (capped at [maxScale]), and
/// [child] is laid out in the room divided by that factor, so it fills the
/// room exactly and is never laid out smaller than [minSize].
///
/// One of these wraps the whole controller body; nothing inside scales on its
/// own, which is what keeps similar controls the same size across cards.
class ScaleToFit extends StatefulWidget {
  const ScaleToFit({
    super.key,
    required this.child,
    this.minSize = controllerBodySize,
    this.maxScale = 2,
    this.reflows = false,
  });

  final Size minSize;
  final double maxScale;

  /// Whether [child] lays itself out for a large text size, so the box need not
  /// grow with the text.
  final bool reflows;
  final Widget child;

  /// The factor [minSize] is scaled by to fit [room]. A side with no bound
  /// leaves the decision to the other; with neither bounded nothing scales.
  static double scaleFor(Size minSize, Size room, double maxScale) {
    final byWidth = room.width.isFinite
        ? room.width / minSize.width
        : double.infinity;
    final byHeight = room.height.isFinite
        ? room.height / minSize.height
        : double.infinity;
    final fit = math.min(byWidth, byHeight);
    return fit.isFinite ? math.min(fit, maxScale) : 1;
  }

  @override
  State<ScaleToFit> createState() => _ScaleToFitState();
}

class _ScaleToFitState extends State<ScaleToFit> {
  /// Whether the room is shorter than the design's for the text's size. Sticky
  /// across [_pageBack], so a height that hovers at the edge (a system bar
  /// sliding in) does not swap the tab's whole layout back and forth.
  bool _short = false;

  /// The share of the design's height a short room has to climb back to.
  static const _pageBack = 1.03;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final minSize = widget.minSize;
      final textScale = math.max(
        1.0,
        MediaQuery.textScalerOf(context).scale(1),
      );
      // The design is for text at its normal size. A larger system font makes
      // the same words need more room, so the box they are laid out in grows
      // with it; the whole is then scaled to fit, and nothing overflows. The
      // controller's tabs opt out ([reflows]): they rearrange their cards from
      // [controllerReflowTextScale], and scaling the whole body down instead
      // shrank every touch target below 48 dp.
      final text = widget.reflows ? 1.0 : textScale;
      final min = minSize * text;
      final fit = ScaleToFit.scaleFor(min, box.biggest, widget.maxScale);
      var paged = false;
      var scale = fit;
      if (widget.reflows) {
        // A tab is a page, as tall as its content, when the text is large or the
        // room is shorter than the design's grown by the text. The height then
        // never shrinks the body; the width still does, since a page scrolls
        // vertically only and the windows the controller is for are 780-890 dp
        // wide, a little under the design's 800 once the rail is taken off.
        final share = box.maxHeight.isFinite
            ? box.maxHeight / (minSize.height * textScale)
            : double.infinity;
        _short = share < (_short ? _pageBack : 1);
        paged = controllerLargeText(context) || _short;
        if (paged) {
          final byWidth = box.maxWidth.isFinite
              ? box.maxWidth / min.width
              : 1.0;
          scale = math.min(byWidth, widget.maxScale);
        }
      }
      final room = box.biggest;
      final layout = Size(
        room.width.isFinite ? room.width / scale : min.width,
        room.height.isFinite ? room.height / scale : min.height,
      );
      // A FittedBox under loose constraints keeps the child's own size rather
      // than growing it, so its box is given the scaled size outright.
      return Align(
        alignment: Alignment.topCenter,
        child: SizedBox.fromSize(
          size: layout * scale,
          child: FittedBox(
            child: SizedBox.fromSize(
              size: layout,
              child: ControllerScale(
                scale: scale,
                paged: paged,
                child: widget.child,
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// The factor the controller body is drawn at, for what it opens in a route of
/// its own — a keypad is laid over the screen, not inside it, and would
/// otherwise stay at the design size on a larger screen. 1 where nothing scales.
class ControllerScale extends InheritedWidget {
  const ControllerScale({
    super.key,
    required this.scale,
    this.paged = false,
    required super.child,
  });

  final double scale;

  /// Whether the tabs under this are pages as tall as their content, from a
  /// large text size or a room shorter than the design's ([ScaleToFit]).
  final bool paged;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ControllerScale>()?.scale ?? 1;

  @override
  bool updateShouldNotify(ControllerScale old) =>
      scale != old.scale || paged != old.paged;
}
