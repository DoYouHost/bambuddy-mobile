import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../wear_shape.dart';
import 'wear_face.dart';
import 'wear_scaling_list.dart';
import 'wear_scroll_indicator.dart';

/// The one scrolling surface on the watch: a viewport cut down to the rectangle
/// inscribed in the face, plus the scroll indicator Wear OS expects. Both of Google
/// Play's layout rejections live here, so no screen builds a [ListView] of its own.
///
/// **A list scales** ([curved]): the viewport is the whole face and the items
/// shrink and fade toward its top and bottom the way Wear OS's `ScalingLazyColumn`
/// does ([WearScalingSliverList]). **A panel keeps the rectangle**: anything with a
/// [centerWhenShort] is a fixed layout. Why, and why the insets go on
/// the viewport rather than on the content, is in `docs/wear-geometry.md`.
class WearScrollView extends StatefulWidget {
  const WearScrollView({
    super.key,
    required this.children,
    this.onRefresh,
    this.centerWhenShort = false,
    this.curved = false,
    this.contentPadding,
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

  /// Lay the children out as Wear OS's `ScalingLazyColumn` ([WearScalingSliverList]):
  /// the whole face, items shrinking and fading toward its top and bottom, and the
  /// second item and every later one able to reach the middle.
  final bool curved;

  /// For a [curved] list laid out as Wear OS lays out a dialog: no
  /// auto-centering, this space above and below the items, and the items
  /// centred when they fit ([WearScalingSliverList.contentPadding]).
  final ({double top, double bottom})? contentPadding;

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

  /// The auto-centering space of the scaling list as measured so far. Its
  /// items are not drawn until the top one is known.
  double? _centerTop;
  double? _centerBottom;

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

  /// Bring the indicator up and start the countdown that takes it away. `forward()`
  /// only when not already on its way up: the events arrive several times per frame,
  /// and restarting the fade each time left it at zero opacity for a whole scroll.
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

  /// Content grew or shrank without anyone scrolling, e.g. a list that just became
  /// scrollable. Only on a real change; dispatched from a microtask after layout, so
  /// the `setState` is legal.
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
    // panel held still is not a list.
    final curved =
        widget.curved && shape == WearShape.round && !widget.centerWhenShort;

    Widget content = NotificationListener<ScrollMetricsNotification>(
      onNotification: _onMetrics,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        // Inside the refresh indicator, so its spinner is not masked as it
        // comes down. The edge mask is for the rectangle only: a scaling list
        // fades its own items.
        child: widget.centerWhenShort
            ? _faded(_centered())
            : (curved ? _scalingList(face) : _faded(_list())),
      ),
    );
    if (widget.onRefresh != null) {
      content = RefreshIndicator(onRefresh: widget.onRefresh!, child: content);
    }

    return Stack(
      children: [
        if (curved)
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: face.width * wearListSideMargin,
            ),
            child: content,
          )
        else
          WearFace(child: content),
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

  /// `ScalingLazyColumn` with its defaults. The children's empty [SizedBox]es
  /// are its `verticalArrangement` spacing: they keep their size and are not
  /// counted as items, so `AutoCenteringParams()` — item 1 — is the second
  /// real item, as on a Compose list whose gaps are not items at all.
  Widget _scalingList(Size face) {
    // A text item gets `listTextPadding()` on top of the list's own margin.
    final children = [
      for (final child in widget.children)
        if (child is Text)
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: face.width * wearListTextMargin,
            ),
            child: child,
          )
        else
          child,
    ];
    bool isGap(Widget child) => child is SizedBox && child.child == null;
    final items = [
      for (var i = 0; i < children.length; i++)
        if (!isGap(children[i])) i,
    ];
    // Child indices of the sliver are one higher: the top spacer is child 0.
    final centerFrom = items.isEmpty
        ? 1
        : items[math.min(1, items.length - 1)] + 1;
    return CustomScrollView(
      controller: _controller,
      physics: _physics,
      slivers: [
        WearScalingSliverList(
          delegate: SliverChildListDelegate([
            SizedBox(height: _centerTop ?? 0),
            ...children,
            SizedBox(height: _centerBottom ?? 0),
          ]),
          centerFromIndex: centerFrom,
          gapIndices: {
            for (var i = 0; i < children.length; i++)
              if (isGap(children[i])) i + 1,
          },
          contentPadding: widget.contentPadding,
          visible: _centerTop != null,
          onAutoCentering: (centering) {
            bool moved(double? old, double? now) =>
                now != null && (old == null || (old - now).abs() >= 0.5);
            if (!mounted ||
                !(moved(_centerTop, centering.top) ||
                    moved(_centerBottom, centering.bottom))) {
              return;
            }
            setState(() {
              _centerTop = centering.top ?? _centerTop;
              _centerBottom = centering.bottom ?? _centerBottom;
            });
          },
        ),
      ],
    );
  }

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

  /// Softens the viewport's own edge, where a row scrolling out would otherwise be cut
  /// across. Only where something can cross it: content that fits never reaches it, so
  /// the mask would buy an offscreen pass per frame for a gradient nobody can see.
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
