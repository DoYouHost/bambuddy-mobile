import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../wear_geometry.dart';
import '../wear_shape.dart';
import 'wear_scroll_indicator.dart';

/// The one scrolling surface on the watch: a viewport cut down to the rectangle
/// inscribed in the face, plus the scroll indicator Wear OS expects.
///
/// Both of Google Play's layout rejections live here, which is why the screens
/// no longer build a [ListView] of their own — a per-screen padding literal is
/// exactly how the first list row ended up under the bezel, and a per-screen
/// scroll view is how four of them ended up with no indicator.
///
/// The insets go on the **viewport**, not on the content: padding the content
/// only settles where the first and last item come to rest, while everything
/// between them still crosses the top and bottom of the circle as the screen
/// scrolls. A viewport that is itself inside the glass cannot paint outside it
/// at any offset. What it can do is cut a row in half at its own edge, so the
/// content fades over the same distance it starts at ([_leadIn]) — nothing is
/// dimmed at rest, and anything scrolling out leaves rather than being sliced.
class WearScrollView extends StatefulWidget {
  const WearScrollView({
    super.key,
    required this.children,
    this.onRefresh,
    this.centerWhenShort = false,
    this.contentWidthFraction,
    this.resetKey,
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

  /// How much of the face this screen's content actually needs, if less than all
  /// of it — see [wearNarrowWidthFraction]. Narrower content is allowed a taller
  /// viewport, because the circle takes its width back nearer the edges.
  final double? contentWidthFraction;

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

  /// Content grew or shrank without anyone scrolling — a list that has just
  /// become scrollable (the fleet landed, a fault appeared) is worth saying so.
  /// Only on a real change: this fires on frames where nothing moved.
  bool _onMetrics(ScrollMetricsNotification notification) {
    final extent = notification.metrics.maxScrollExtent;
    if (extent > 0 && extent != _scrollableExtent) _reveal();
    _scrollableExtent = extent;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final shape = wearShapeOf(context);
    final insets = wearFaceInsets(shape, MediaQuery.sizeOf(context),
        widthFraction: widget.contentWidthFraction);

    Widget content = NotificationListener<ScrollMetricsNotification>(
      onNotification: _onMetrics,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        // Inside the refresh indicator, so its spinner is not masked as it
        // comes down.
        child: _faded(widget.centerWhenShort ? _centered() : _list()),
      ),
    );
    if (widget.onRefresh != null) {
      content = RefreshIndicator(onRefresh: widget.onRefresh!, child: content);
    }

    return Stack(
      children: [
        Padding(padding: insets, child: content),
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

  Widget _list() => ListView(
        controller: _controller,
        physics: _physics,
        padding: const EdgeInsets.symmetric(vertical: _leadIn),
        children: widget.children,
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
  Widget _faded(Widget child) => LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          if (!height.isFinite || height <= _leadIn * 3) return child;
          final fade = _leadIn / height;
          return ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const [
                Color(0x00FFFFFF),
                Color(0xFFFFFFFF),
                Color(0xFFFFFFFF),
                Color(0x00FFFFFF),
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
