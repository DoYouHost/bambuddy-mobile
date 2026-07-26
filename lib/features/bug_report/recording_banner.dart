import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import 'bug_report_controller.dart';

/// Route of the report screen. Named here because the banner has to know
/// whether it is already showing before it pushes.
const bugReportRoute = '/settings/bug-report';

/// Gap kept between the bar and the edges of the screen.
const _edgeMargin = 8.0;

/// `m:ss` for the bar's clock. Minutes are not padded — a recording is
/// minutes long, and "0:07" reads better than "00:07" at this size.
String formatElapsed(Duration d) {
  final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '${d.inMinutes}:$seconds';
}

/// Wraps the whole app so the recording controls survive navigation — the bug
/// gets reproduced on the dashboard, not on the report screen. Also the
/// "visible indicator" the plan asks for: nobody should be able to leave a
/// recording running without noticing.
class RecordingBannerScaffold extends ConsumerWidget {
  const RecordingBannerScaffold({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recording = ref.watch(
      bugReportProvider.select((s) => s.isRecording),
    );
    return Stack(
      children: [
        child,
        // Covers the screen but hit-tests only where the bar actually is: a
        // Stack reports no hit for its empty areas, so every other tap reaches
        // the app underneath untouched.
        if (recording) const Positioned.fill(child: _RecordingLayer()),
      ],
    );
  }
}

/// The bar floats: no layout of the app below is shifted for it, and the user
/// drags it aside wherever it covers something they need. Position and collapsed
/// state deliberately live in memory only — a recording is short, and restoring
/// them across restarts is not worth the storage.
class _RecordingLayer extends ConsumerStatefulWidget {
  const _RecordingLayer();

  @override
  ConsumerState<_RecordingLayer> createState() => _RecordingLayerState();
}

class _RecordingLayerState extends ConsumerState<_RecordingLayer> {
  final _layerKey = GlobalKey();
  final _barKey = GlobalKey();

  Timer? _ticker;

  /// Null until the first drag: the bar starts centred at the top, over the app
  /// bar's title rather than over its buttons.
  Offset? _position;
  bool _collapsed = false;

  /// Last measured size of the bar, used to keep it inside the screen. Read
  /// after a frame or from a gesture handler — never during build, where a
  /// render object's size is not allowed to be queried.
  Size? _barSize;

  @override
  void initState() {
    super.initState();
    // Only the clock changes; a second is as precise as this needs to be.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _measureAfterFrame();
  }

  void _measureAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measure();
    });
  }

  void _measure() {
    final size = _barKey.currentContext?.size;
    if (size != null && size != _barSize) setState(() => _barSize = size);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _elapsed(DateTime? startedAt) => startedAt == null
      ? formatElapsed(Duration.zero)
      : formatElapsed(DateTime.now().difference(startedAt));

  /// Where the bar sits right now, in layer coordinates — the anchor the first
  /// drag continues from, so it does not jump out of the centred position.
  Offset _currentTopLeft() {
    final bar = _barKey.currentContext?.findRenderObject();
    final layer = _layerKey.currentContext?.findRenderObject();
    if (bar is RenderBox && layer is RenderBox && bar.hasSize && layer.hasSize) {
      return layer.globalToLocal(bar.localToGlobal(Offset.zero));
    }
    return const Offset(_edgeMargin, _edgeMargin);
  }

  void _startDrag() {
    _measure();
    setState(() => _position ??= _currentTopLeft());
  }

  void _setCollapsed(bool value) {
    setState(() => _collapsed = value);
    // The pill and the full bar are different sizes; re-measure so clamping
    // works against the one on screen.
    _measureAfterFrame();
  }

  void _drag(DragUpdateDetails details) {
    setState(() => _position = (_position ?? _currentTopLeft()) + details.delta);
  }

  /// Keeps the bar reachable: it may not be dragged under the status bar or off
  /// an edge. Applied on every build, so rotation or a keyboard cannot strand it
  /// outside the screen either.
  Offset _clamp(Offset p, Size area, EdgeInsets safe) {
    final bar = _barSize ?? const Size(240, 48);
    final maxX = math.max(_edgeMargin, area.width - bar.width - _edgeMargin);
    final maxY = math.max(
      safe.top,
      area.height - bar.height - safe.bottom - _edgeMargin,
    );
    return Offset(p.dx.clamp(_edgeMargin, maxX), p.dy.clamp(safe.top, maxY));
  }

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    final elapsed = _elapsed(ref.watch(bugReportProvider).startedAt);

    return LayoutBuilder(
      key: _layerKey,
      builder: (context, constraints) {
        final bar = _collapsed ? _pill(context, elapsed) : _bar(context, elapsed);
        final position = _position;
        return Stack(
          children: [
            if (position == null)
              Positioned(
                left: _edgeMargin,
                right: _edgeMargin,
                top: safe.top + _edgeMargin,
                child: Center(child: bar),
              )
            else
              () {
                final p = _clamp(position, constraints.biggest, safe);
                return Positioned(left: p.dx, top: p.dy, child: bar);
              }(),
          ],
        );
      },
    );
  }

  /// Common chrome. The identifier names the whole bar so the interaction probe
  /// can tell its own UI from the app's.
  Widget _shell(BuildContext context, Widget child) {
    final t = DashTokens.of(context);
    return Semantics(
      container: true,
      identifier: 'bug_report.bar',
      label: AppLocalizations.of(context).bugReportBannerLabel,
      child: Material(
        key: _barKey,
        color: t.overlaySurface,
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: t.danger.withValues(alpha: 0.5)),
        ),
        child: child,
      ),
    );
  }

  // Static dot: the ticking clock next to it already reads as "live", and an
  // endless animation would repaint for the whole session on the very screen the
  // user is reproducing a bug on.
  Widget _dot(DashTokens t) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: t.danger, shape: BoxShape.circle),
      );

  Widget _clock(DashTokens t, String elapsed) => Text(
        elapsed,
        style: TextStyle(
          fontFamily: DashTokens.fontMono,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: t.textSecondary,
        ),
      );

  Widget _bar(BuildContext context, String elapsed) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);

    return _shell(
      context,
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 5, 6, 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              identifier: 'bug_report.move',
              label: l10n.bugReportBarMove,
              child: GestureDetector(
                onPanStart: (_) => _startDrag(),
                onPanUpdate: _drag,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Icon(
                    Icons.drag_indicator,
                    size: 18,
                    color: t.textSecondary,
                  ),
                ),
              ),
            ),
            _dot(t),
            const SizedBox(width: 8),
            _clock(t, elapsed),
            const SizedBox(width: 4),
            Semantics(
              identifier: 'bug_report.mark',
              // Label instead of `tooltip:` — a tooltip needs an Overlay, and
              // this bar lives in `MaterialApp.builder`, above the Navigator
              // that provides one. The label covers both the screen reader and
              // the log's naming of this button.
              label: l10n.bugReportMark,
              child: _iconButton(
                icon: Icons.bookmark_add_outlined,
                color: t.textSecondary,
                onPressed: () {
                  ref.read(bugReportProvider.notifier).mark();
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(content: Text(l10n.bugReportMarked)),
                    );
                },
              ),
            ),
            const SizedBox(width: 2),
            Semantics(
              identifier: 'bug_report.stop',
              // The full sentence for the screen reader; the button itself has
              // room for one word only.
              label: l10n.bugReportStop,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: t.danger,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 32),
                  textStyle: const TextStyle(
                    fontFamily: DashTokens.fontUi,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: () => _finish(context, ref),
                child: Text(l10n.bugReportStopShort),
              ),
            ),
            const SizedBox(width: 2),
            Semantics(
              identifier: 'bug_report.collapse',
              label: l10n.bugReportBarCollapse,
              child: _iconButton(
                icon: Icons.close_fullscreen_rounded,
                color: t.textSecondary,
                onPressed: () => _setCollapsed(true),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Collapsed form: dot plus clock, still draggable, one tap to bring the
  /// controls back. Nothing here can end the recording — the pill is small
  /// enough to be tapped by accident.
  Widget _pill(BuildContext context, String elapsed) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);

    return _shell(
      context,
      Semantics(
        identifier: 'bug_report.expand',
        label: l10n.bugReportBarExpand,
        button: true,
        child: GestureDetector(
          onTap: () => _setCollapsed(false),
          onPanStart: (_) => _startDrag(),
          onPanUpdate: _drag,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dot(t),
                const SizedBox(width: 8),
                _clock(t, elapsed),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) =>
      IconButton(
        icon: Icon(icon, size: 19),
        color: color,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        onPressed: onPressed,
      );

  Future<void> _finish(BuildContext context, WidgetRef ref) async {
    await ref.read(bugReportProvider.notifier).stop();
    // The report screen renders whatever phase the controller is in, so it
    // only needs pushing when the user is somewhere else.
    final navigator = rootNavigatorKey.currentContext;
    if (navigator == null || !navigator.mounted) return;
    final location = GoRouter.of(navigator).state.uri.path;
    if (location != bugReportRoute) navigator.push(bugReportRoute);
  }
}
