import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../wear_geometry.dart';
import '../wear_shape.dart';
import 'wear_face.dart';
import 'wear_face_curve.dart';
import 'wear_scroll_indicator.dart';

/// The one scrolling surface on the watch: a viewport cut down to the rectangle
/// inscribed in the face, plus the scroll indicator Wear OS expects.
///
/// Both of Google Play's layout rejections live here, which is why no screen
/// builds a [ListView] of its own — a per-screen padding literal is how the
/// first list row ended up under the bezel, and a per-screen scroll view is how
/// four of them ended up with no indicator.
///
/// **A list curves** ([curved]): the viewport is the whole face and each item is
/// scaled to the chord lit where it sits. **A panel keeps the rectangle**:
/// anything with a [footer] or [centerWhenShort] is a fixed layout, and a
/// confirmation whose buttons are pinned at the bottom of the *face* would pin
/// them where the circle has no width left. Which costs what, and why the
/// insets go on the viewport rather than on the content, is in
/// `docs/wear-geometry.md`.
class WearScrollView extends StatefulWidget {
  const WearScrollView({
    super.key,
    required this.children,
    this.onRefresh,
    this.centerWhenShort = false,
    this.curved = false,
    this.itemCornerRadius = 0,
    this.contentWidthFraction,
    this.resetKey,
    this.footer,
  });

  final List<Widget> children;

  /// Pull-to-refresh, where the screen has something to re-fetch. Also what
  /// makes the view scrollable even when the content fits, so the gesture is
  /// available on a half-empty face.
  final Future<void> Function()? onRefresh;

  /// Hold short content in the middle of the face rather than under the top
  /// margin. For the screens that are one message and a button; a list reads
  /// better from the top.
  final bool centerWhenShort;

  /// Run the viewport across the whole face and let the items carry the
  /// geometry, shrinking toward the rim ([WearFaceCurve]).
  ///
  /// **Only for a list of short rows.** An item taller than the face's radius
  /// has a corner past the chord wherever it stands, so a paragraph or a fault
  /// card cannot be rescued by shrinking — only cut, which is the rejection this
  /// file exists because of. Those screens keep the rectangle.
  final bool curved;

  /// How round this list's items are, where they are all one shape.
  ///
  /// Otherwise the scale is decided by the corner of a box: a 20 dp round row
  /// shrank to 0.85 for a corner it never paints, and scaled text is
  /// re-rasterised — same advances, different pixels — so it reads as different
  /// letter spacing. Left at nothing unless the items really are all that round.
  final double itemCornerRadius;

  /// How much of the face this screen's content actually needs, if less than all
  /// of it — see [wearNarrowWidthFraction]. Narrower content is allowed a taller
  /// viewport, because the circle takes its width back nearer the edges.
  final double? contentWidthFraction;

  /// Held at the bottom of the viewport, inside the same insets, while
  /// [children] scroll above it. For the one thing a screen cannot afford to
  /// put below the fold: a confirmation's two buttons, which on a 192 dp face
  /// needed a scroll before they were pinned here.
  final Widget? footer;

  /// Changing this scrolls back to the top. For a screen that swaps its content
  /// under the user — the setup flow moves between handoff, offer and manual
  /// entry — which otherwise leaves them partway down a page whose top they have
  /// never seen, because the old scroll offset survives the swap.
  final Object? resetKey;

  @override
  State<WearScrollView> createState() => _WearScrollViewState();
}

class _WearScrollViewState extends State<WearScrollView>
    with SingleTickerProviderStateMixin {
  final _controller = ScrollController();
  late final AnimationController _fade;
  Timer? _idle;

  /// How long the indicator stays up after the last scroll event.
  static const _linger = Duration(milliseconds: 1200);

  /// How far inside the viewport the content starts, and how long the fade at
  /// the viewport's edge is. The two are the same number on purpose: at rest the
  /// first row sits exactly where the fade ends, so it is drawn at full
  /// strength, and a row only fades once it has actually started to leave.
  static const _leadIn = 12.0;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      reverseDuration: const Duration(milliseconds: 350),
    );
    // Show it once the first frame is measured: someone landing on a screen that
    // scrolls should see that it does, without having to try.
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  @override
  void didUpdateWidget(WearScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetKey != oldWidget.resetKey && _controller.hasClients) {
      _controller.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _idle?.cancel();
    _fade.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Bring the indicator up and start the countdown that takes it away again.
  ///
  /// `forward()` only when it is not already on its way up: called again mid
  /// fade-in it restarts the animation from where it is, and the events that
  /// land here arrive several times per frame — the indicator sat at zero
  /// opacity for the whole of a scroll, permanently one frame from appearing.
  void _reveal() {
    if (!mounted) return;
    if (!_fade.isForwardOrCompleted) _fade.forward();
    _idle?.cancel();
    _idle = Timer(_linger, () {
      if (mounted) _fade.reverse();
    });
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification ||
        notification is ScrollStartNotification ||
        notification is OverscrollNotification) {
      _reveal();
    }
    return false;
  }

  /// How much there was to scroll last time the metrics were announced.
  double _scrollableExtent = 0;

  /// Whether the content can move at all — what the edge fade is for, and false
  /// until the first metrics land (the notification always fires once, since the
  /// position has no previous metrics to compare the first layout against).
  bool _scrolls = false;

  /// Content grew or shrank without anyone scrolling — a list that has just
  /// become scrollable (the fleet landed, a fault appeared) is worth saying so.
  /// Only on a real change: this fires on frames where nothing moved.
  ///
  /// Dispatched from a microtask after layout, never during it, so the rebuild
  /// below is a legal `setState` rather than a mid-layout one.
  bool _onMetrics(ScrollMetricsNotification notification) {
    final extent = notification.metrics.maxScrollExtent;
    if (extent > 0 && extent != _scrollableExtent) _reveal();
    _scrollableExtent = extent;
    final scrolls = extent > 0;
    if (scrolls != _scrolls) setState(() => _scrolls = scrolls);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final shape = wearShapeOf(context);
    final face = MediaQuery.sizeOf(context);
    // A square face keeps its corners and has nothing to curve away from; a
    // panel (a footer to pin, or content held still) is not a list.
    final curved =
        widget.curved &&
        shape == WearShape.round &&
        widget.footer == null &&
        !widget.centerWhenShort;

    Widget content = NotificationListener<ScrollMetricsNotification>(
      onNotification: _onMetrics,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        // Inside the refresh indicator, so its spinner is not masked as it
        // comes down. The edge mask is for the rectangle only: where the items
        // curve, shrinking to nothing at the rim *is* the fade, and a mask over
        // it would buy an offscreen pass per frame on the flavour that exists
        // because of the battery.
        child: widget.centerWhenShort
            ? _faded(_centered())
            : (curved ? _list(face: face) : _faded(_list())),
      ),
    );
    if (widget.onRefresh != null) {
      content = RefreshIndicator(onRefresh: widget.onRefresh!, child: content);
    }
    if (widget.footer case final footer?) {
      content = Column(
        children: [
          Expanded(child: content),
          footer,
        ],
      );
    }

    return Stack(
      children: [
        if (curved)
          // The width a row gets is unchanged — this buys height, and a row
          // that re-wrapped as well would make every scroll a relayout.
          Padding(
            padding: wearFaceInsets(
              shape,
              face,
              widthFraction: widget.contentWidthFraction,
            ).copyWith(top: 0, bottom: 0),
            child: content,
          )
        else
          WearFace(widthFraction: widget.contentWidthFraction, child: content),
        // Outside the insets: the indicator belongs on the glass the content
        // just gave up, hugging the bezel where nothing else may go.
        Positioned.fill(
          child: IgnorePointer(
            child: WearScrollIndicator(
              controller: _controller,
              opacity: _fade,
              shape: shape,
            ),
          ),
        ),
      ],
    );
  }

  /// [face] non-null means the curved mode: the items carry the geometry, so
  /// the list runs the whole height and only holds the first and last back far
  /// enough to come to rest near full size.
  Widget _list({Size? face}) => ListView(
    controller: _controller,
    physics: _physics,
    padding: EdgeInsets.symmetric(
      vertical: face == null
          ? _leadIn
          : face.shortestSide * roundCurveEndFraction,
    ),
    children: [
      for (final child in widget.children)
        if (face == null)
          child
        else
          WearFaceCurve(
            face: face,
            cornerRadius: widget.itemCornerRadius,
            child: child,
          ),
    ],
  );

  Widget _centered() => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      controller: _controller,
      physics: _physics,
      padding: const EdgeInsets.symmetric(vertical: _leadIn),
      child: ConstrainedBox(
        // Fills the viewport when the content is short — that is what puts
        // the column in the middle — and gives way to it when it isn't.
        constraints: BoxConstraints(
          minHeight: math.max(0, constraints.maxHeight - _leadIn * 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: widget.children,
        ),
      ),
    ),
  );

  /// Softens the viewport's own edge, where a row scrolling out would otherwise
  /// be cut across in the middle of the black face.
  ///
  /// Only where something can actually cross that edge. Content that fits never
  /// reaches it — at rest the first and last rows sit exactly where the gradient
  /// is already opaque ([_leadIn]) — so on a screen that does not scroll the
  /// mask buys an offscreen compositing pass per frame for a gradient nobody
  /// can see, on the flavour that exists because of the battery.
  Widget _faded(Widget child) => LayoutBuilder(
    builder: (context, constraints) {
      final height = constraints.maxHeight;
      if (!_scrolls || !height.isFinite || height <= _leadIn * 3) {
        return child;
      }
      final fade = _leadIn / height;
      return ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          // Alpha is all a `dstIn` mask reads; the colours are named
          // rather than spelled in hex so they say "keep" and "drop".
          colors: const [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: [0, fade, 1 - fade, 1],
        ).createShader(bounds),
        child: child,
      );
    },
  );

  /// Scrollable even when the content fits, so pull-to-refresh works on a
  /// half-empty face; the platform default where there is nothing to refresh.
  ScrollPhysics? get _physics =>
      widget.onRefresh == null ? null : const AlwaysScrollableScrollPhysics();
}
