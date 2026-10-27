import 'dart:async';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import '../wall/wall_screen.dart';
import 'tour_beacon.dart';
import 'tour_sandbox.dart';

/// One card of the guided tour.
class TourStep {
  const TourStep({
    required this.id,
    required this.location,
    required this.text,
    this.targets = const [],
    this.requires = const {},
    this.wallPreview = false,
    this.prepare,
  });

  /// Diagnostic id, logged as `tour.<id>`.
  final String id;

  /// Where the app is put when the step starts.
  final String location;

  final String Function(AppLocalizations l10n) text;

  /// What the spotlight falls on — the first of them that is on screen.
  final List<String> targets;

  /// Every beacon event the user has to cause before "Next" appears. Empty is
  /// a step that only shows something. `route:<path>` is reported by the tour
  /// itself whenever its router lands on `<path>`.
  final Set<String> requires;

  /// Shows a miniature of the wall under the text.
  final bool wallPreview;

  /// Opens what the step points into, once the app is at [location].
  final void Function(TourBeacon beacon)? prepare;
}

/// The dashboard's drawer, found through the button that opens it.
void _openDrawer(TourBeacon beacon) {
  final button = beacon.contextOf('chrome.drawer');
  if (button != null) Scaffold.maybeOf(button)?.openDrawer();
}

/// The dashboard's ⋮ menu, as if tapped.
void _openMenu(TourBeacon beacon) {
  PopupMenuButtonState<Object?>? menu;
  void find(Element element) {
    if (element is StatefulElement && element.state is PopupMenuButtonState) {
      menu = element.state as PopupMenuButtonState<Object?>;
      return;
    }
    element.visitChildElements(find);
  }

  (beacon.contextOf('dashboard.menu') as Element?)?.visitChildElements(find);
  menu?.showButtonMenu();
}

/// The tour, in the order agreed for it. Item ids are the demo's fixtures
/// (`DemoBackend`): printer 1 is the one printing, queue jobs 101–103 are all
/// pending, archive 41 is the Benchy.
final tourSteps = <TourStep>[
  TourStep(
    id: 'tabs',
    location: '/',
    text: (l10n) => l10n.tourStepTabs,
    targets: const ['shell.nav'],
    requires: const {
      'route:/queue',
      'route:/archive',
      'route:/maintenance',
      'route:/inventory',
    },
  ),
  TourStep(
    id: 'drawer',
    location: '/',
    text: (l10n) => l10n.tourStepDrawer,
    targets: const ['chrome.drawer'],
    requires: const {'dashboard.drawer'},
  ),
  TourStep(
    id: 'edit_printer',
    location: '/',
    text: (l10n) => l10n.tourStepEditPrinter,
    targets: const ['printer.edit.1'],
    requires: const {'printer.edit'},
  ),
  TourStep(
    id: 'reorder',
    location: '/queue',
    text: (l10n) => l10n.tourStepReorder,
    targets: const ['queue.reorder.102'],
    requires: const {'queue.reorder'},
  ),
  TourStep(
    id: 'swipe',
    location: '/queue',
    text: (l10n) => l10n.tourStepSwipe,
    targets: const ['queue.swipe_delete.103'],
    requires: const {'queue.swipe_delete'},
  ),
  TourStep(
    id: 'select',
    location: '/archive',
    text: (l10n) => l10n.tourStepSelect,
    targets: const ['archive.item.41'],
    requires: const {'archive.select'},
  ),
  TourStep(
    id: 'wall',
    location: '/',
    text: (l10n) => l10n.tourStepWall,
    targets: const ['dashboard.wall_mode'],
    wallPreview: true,
    prepare: _openMenu,
  ),
  TourStep(
    id: 'stats',
    location: '/',
    text: (l10n) => l10n.tourStepStats,
    // The button as a fallback: Back closes the drawer, and the user must be
    // able to open it again.
    targets: const ['drawer.stats', 'chrome.drawer'],
    requires: const {'route:/stats'},
    prepare: _openDrawer,
  ),
  TourStep(id: 'done', location: '/', text: (l10n) => l10n.tourStepDone),
];

/// Hosts the guided tour above the app's own navigator.
///
/// Above it, not on it: a route pushed there would sit under the app's root
/// navigator, and every dialog and sheet the demo opens with
/// `useRootNavigator` — the swipe's delete confirmation among them — would land
/// on that navigator instead, over the tour and under the app's real
/// `ProviderScope`. Up here the tour's navigator is the only one in reach. The
/// app is kept, offstage and paused, until the tour ends.
class TourHost extends StatefulWidget {
  const TourHost({super.key, this.backButtonDispatcher, required this.child});

  /// The app router's, so the tour answers Back before the app does.
  final BackButtonDispatcher? backButtonDispatcher;
  final Widget child;

  /// Runs the tour; completes when it ends, finished or skipped.
  static Future<void> open(BuildContext context) =>
      context.findAncestorStateOfType<_TourHostState>()!._open();

  @override
  State<TourHost> createState() => _TourHostState();
}

class _TourHostState extends State<TourHost> {
  Completer<void>? _running;

  Future<void> _open() {
    final running = _running;
    if (running != null) return running.future;
    final started = Completer<void>();
    setState(() => _running = started);
    return started.future;
  }

  void _end() {
    final running = _running;
    setState(() => _running = null);
    running?.complete();
  }

  @override
  Widget build(BuildContext context) {
    final on = _running != null;
    return Stack(
      fit: StackFit.expand,
      children: [
        TickerMode(
          enabled: !on,
          child: Offstage(offstage: on, child: widget.child),
        ),
        if (on)
          TourScreen(
            parentBackButton: widget.backButtonDispatcher,
            onEnd: _end,
          ),
      ],
    );
  }
}

/// The guided tour: the app itself, running over the demo in a sandbox
/// ([TourSandbox]), with a spotlight on the control each step is about.
///
/// The user does each gesture for real — the demo is theirs to break — and
/// everything outside the spotlight is blocked until they have.
class TourScreen extends StatefulWidget {
  const TourScreen({super.key, required this.onEnd, this.parentBackButton});

  final VoidCallback onEnd;
  final BackButtonDispatcher? parentBackButton;

  @override
  State<TourScreen> createState() => _TourScreenState();
}

class _TourScreenState extends State<TourScreen>
    with SingleTickerProviderStateMixin {
  final _steps = tourSteps;
  late final TourSandbox _sandbox = TourSandbox(onEvent: _onEvent);
  final _keys = newNavigatorKeys();
  late final GoRouter _router = buildAppRouter(
    keys: _keys,
    initialLocation: _steps.first.location,
    hasProfile: true,
  );
  late final _TourBackButton? _backButton = switch (widget.parentBackButton) {
    final parent? => _TourBackButton(parent, () => _end('back')),
    null => null,
  };
  int _index = 0;
  final _seen = <String>{};

  /// Which edge the card sits on. Kept while the target is missing for a
  /// frame (a drag, a route on its way in) — worked out per frame, the card
  /// jumped every time — and moved only once the target is well into the
  /// card's half ([tourCardAtTop]).
  bool? _cardAtTop;

  /// [_frames] when the step started: the card waits for its target this
  /// long before showing at the bottom anyway.
  int _stepStartFrame = 0;
  static const _waitForTargetFrames = 30;

  // The target moves with scrolling and layout; the spotlight and the card
  // follow it every frame.
  final _frames = ValueNotifier(0);
  late final Ticker _ticker;

  TourStep get _step => _steps[_index];
  bool get _stepDone => _step.requires.every(_seen.contains);

  /// The user did what the step asked, so the demo is theirs to explore
  /// until "Next". A step that only shows something keeps its spotlight.
  bool get _released => _step.requires.isNotEmpty && _stepDone;

  @override
  void initState() {
    super.initState();
    _router.routerDelegate.addListener(_onRoute);
    _ticker = createTicker((_) => _frames.value++)..start();
    _log('start');
    // Only once the tour's router has registered with it.
    SchedulerBinding.instance.addPostFrameCallback(
      (_) => _backButton?.takePriority(),
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frames.dispose();
    _router.routerDelegate.removeListener(_onRoute);
    _router.dispose();
    _sandbox.dispose();
    super.dispose();
  }

  void _log(String action) => DiagnosticRecorder.active?.add(
    LogSource.ui,
    'tour',
    fields: {'step': _step.id, 'action': action},
  );

  void _onRoute() =>
      _onEvent('route:${_router.routerDelegate.state.matchedLocation}');

  void _onEvent(String event) {
    if (!mounted || _seen.contains(event)) return;
    // A beacon fires from inside a build or a gesture callback.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final wasDone = _stepDone;
      setState(() => _seen.add(event));
      if (!wasDone && _stepDone) _log('done');
    });
  }

  void _next() {
    if (_index == _steps.length - 1) return _end('finish');
    _log('next');
    setState(() {
      _index++;
      _seen.clear();
      _cardAtTop = null;
      _stepStartFrame = _frames.value;
    });
    _resetTo(_step.location);
    final prepare = _step.prepare;
    if (prepare != null) {
      // After the router has put the step's screen up.
      SchedulerBinding.instance.addPostFrameCallback(
        (_) => prepare(_sandbox.beacon),
      );
    }
  }

  void _end(String action) {
    _log(action);
    widget.onEnd();
  }

  /// Puts the app where the step starts: drawer shut, anything pushed or
  /// opened over a screen closed, then the step's location.
  void _resetTo(String location) {
    final drawerButton = _sandbox.beacon.contextOf('chrome.drawer');
    if (drawerButton != null) Scaffold.maybeOf(drawerButton)?.closeDrawer();
    for (final key in [_keys.root, ..._keys.branches]) {
      key.currentState?.popUntil((route) => route.settings is Page);
    }
    _router.go(location);
  }

  @override
  Widget build(BuildContext context) {
    return UncontrolledProviderScope(
      container: _sandbox.container,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: Theme.of(context),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Localizations.localeOf(context),
        routerDelegate: _router.routerDelegate,
        routeInformationParser: _router.routeInformationParser,
        routeInformationProvider: _router.routeInformationProvider,
        backButtonDispatcher: _backButton,
        builder: (context, child) => Stack(
          children: [
            ?child,
            Positioned.fill(
              child: _Scrim(
                holeOf: () =>
                    _released ? null : _sandbox.beacon.rectOf(_step.targets),
                // Once the gesture is done the demo is free to explore
                // until "Next".
                passThrough: _released,
                // A step that only shows something keeps even the spotlit
                // control shut: the menu it would open lands outside the hole,
                // where nothing could close it again.
                holeTouchable: _step.requires.isNotEmpty,
                // Dark enough to tell apart on the dark theme, where the
                // screen under it is nearly black already.
                color: Colors.black.withValues(alpha: 0.72),
                ring: DashTokens.of(context).accentGreen,
                repaint: _frames,
              ),
            ),
            ListenableBuilder(
              listenable: _frames,
              builder: (context, _) {
                final hole = _sandbox.beacon.rectOf(_step.targets);
                final height = MediaQuery.sizeOf(context).height;
                if (hole != null) {
                  _cardAtTop = tourCardAtTop(
                    _cardAtTop,
                    hole.center.dy / height,
                  );
                }
                // Not drawn on the wrong side for the frame or two before the
                // target (or the menu holding it) is laid out.
                final waiting =
                    _cardAtTop == null &&
                    _step.targets.isNotEmpty &&
                    _frames.value - _stepStartFrame < _waitForTargetFrames;
                if (waiting) return const SizedBox.shrink();
                return _TourCard(
                  step: _step,
                  number: _index + 1,
                  total: _steps.length,
                  done: _stepDone,
                  atTop: _cardAtTop ?? false,
                  onNext: _next,
                  onSkip: () => _end('skip'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Whether the card goes to the top, given where it is now ([current], null
/// before the first decision) and the target's centre as a share of the
/// screen height. Opposite the target, and moved only once the target is
/// well into the card's half: the card does not cross the screen for a drag
/// that ends a few pixels past the middle.
@visibleForTesting
bool tourCardAtTop(bool? current, double targetShare) => switch (current) {
  null => targetShare > 0.5,
  true => targetShare > _flipShare,
  false => targetShare > 1 - _flipShare,
};

const _flipShare = 0.25;

/// Back inside the tour: the demo's own screens first (a form, a dialog),
/// and once there is nothing left to close, the end of the tour — never the
/// app's screens hidden under it.
class _TourBackButton extends ChildBackButtonDispatcher {
  _TourBackButton(super.parent, this.onUnhandled);

  final VoidCallback onUnhandled;

  @override
  Future<bool> notifiedByParent(Future<bool> defaultValue) async {
    if (await super.notifiedByParent(defaultValue)) return true;
    onUnhandled();
    return true;
  }
}

/// Dims everything but [holeOf] and keeps touches out of the dimmed part.
class _Scrim extends LeafRenderObjectWidget {
  const _Scrim({
    required this.holeOf,
    required this.passThrough,
    required this.holeTouchable,
    required this.color,
    required this.ring,
    required this.repaint,
  });

  final Rect? Function() holeOf;
  final bool passThrough;
  final bool holeTouchable;
  final Color color;

  /// Drawn round the hole: dimming alone barely shows on a dark screen.
  final Color ring;
  final Listenable repaint;

  @override
  _RenderScrim createRenderObject(BuildContext context) =>
      _RenderScrim(holeOf, passThrough, color, repaint)
        ..holeTouchable = holeTouchable
        ..ring = ring;

  @override
  void updateRenderObject(BuildContext context, _RenderScrim render) => render
    ..holeOf = holeOf
    ..passThrough = passThrough
    ..holeTouchable = holeTouchable
    ..ring = ring
    ..color = color;
}

class _RenderScrim extends RenderBox {
  _RenderScrim(this.holeOf, this._passThrough, this._color, this._repaint);

  Rect? Function() holeOf;
  bool holeTouchable = true;
  Color ring = const Color(0x00000000);
  final Listenable _repaint;

  bool _passThrough;
  set passThrough(bool value) {
    if (value == _passThrough) return;
    _passThrough = value;
    markNeedsPaint();
  }

  Color _color;
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  static const _holePadding = DashSpace.xs;
  static const _ringWidth = 2.0;
  static const _glowWidth = 8.0;
  static const _holeRadius = Radius.circular(16);

  /// The hole in this box's own coordinates, padded.
  Rect? get _hole {
    final global = holeOf();
    if (global == null) return null;
    final topLeft = globalToLocal(global.topLeft);
    // Clipped to the screen: a control at its edge (the tab bar, the ⋮ menu)
    // would otherwise be ringed partly off the glass.
    final hole = (topLeft & global.size)
        .inflate(_holePadding)
        .intersect(Offset.zero & size);
    // Wholly off the screen (a drawer still sliding in): nothing to ring, and
    // the intersection is an inverted rectangle.
    return hole.isEmpty ? null : hole;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _repaint.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _repaint.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool hitTestSelf(Offset position) {
    if (_passThrough) return false;
    if (!holeTouchable) return true;
    return !(_hole?.contains(position) ?? false);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_passThrough) return;
    final screen = Path()..addRect(offset & size);
    final hole = _hole;
    if (hole != null) {
      screen
        ..addRRect(RRect.fromRectAndRadius(hole.shift(offset), _holeRadius))
        ..fillType = PathFillType.evenOdd;
    }
    context.canvas.drawPath(screen, Paint()..color = _color);
    if (hole == null) return;
    final ring = RRect.fromRectAndRadius(hole.shift(offset), _holeRadius);
    context.canvas
      ..drawRRect(
        ring,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _glowWidth
          ..color = this.ring.withValues(alpha: 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      )
      ..drawRRect(
        ring,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _ringWidth
          ..color = this.ring,
      );
  }
}

class _TourCard extends StatelessWidget {
  const _TourCard({
    required this.step,
    required this.number,
    required this.total,
    required this.done,
    required this.atTop,
    required this.onNext,
    required this.onSkip,
  });

  final TourStep step;
  final int number;
  final int total;
  final bool done;

  /// Opposite the spotlight, so the card never covers what it talks about.
  final bool atTop;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  /// The wall's own breakpoint-free size for a phone in landscape, scaled to
  /// the card's width.
  static const _wallPreviewSize = Size(800, 450);

  /// Of the screen's height, leaving the rest for what the card points at.
  static const _maxHeightShare = 0.6;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final screen = MediaQuery.sizeOf(context);
    final last = number == total;
    final card = Container(
      padding: const EdgeInsets.all(DashSpace.lg),
      decoration: BoxDecoration(
        color: t.overlaySurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.cardBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Skip as a corner ✕ rather than a second full-width button: the
          // card covered too much of the screen it is explaining.
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.tourStepCounter(number, total),
                  style: t.label,
                ),
              ),
              // A label, not a tooltip: the card sits beside the navigator,
              // where there is no overlay for a tooltip to open in.
              IconButton.outlined(
                onPressed: onSkip,
                style: IconButton.styleFrom(
                  foregroundColor: t.dangerInk,
                  side: BorderSide(color: t.danger),
                ),
                icon: Icon(Icons.close, semanticLabel: l10n.tourSkip),
              ).tagged('tour.skip'),
            ],
          ),
          Text(step.text(l10n), style: t.bodyStrong),
          if (step.wallPreview) ...[
            const SizedBox(height: DashSpace.md),
            Center(
              // Held to a share of the screen: in landscape a full-width
              // 16:9 wall would make the card taller than the screen.
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: screen.height * 0.3),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio:
                        _wallPreviewSize.width / _wallPreviewSize.height,
                    child: IgnorePointer(
                      child: FittedBox(
                        child: SizedBox.fromSize(
                          size: _wallPreviewSize,
                          child: MediaQuery(
                            data: MediaQuery.of(context).copyWith(
                              size: _wallPreviewSize,
                              padding: EdgeInsets.zero,
                              viewPadding: EdgeInsets.zero,
                            ),
                            // The card sits beside the navigator, not in it,
                            // and the wall's tooltips need an overlay.
                            child: Overlay(
                              initialEntries: [
                                OverlayEntry(
                                  builder: (_) =>
                                      const WallScreen(preview: true),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: DashSpace.sm),
          Text(l10n.tourDemoNote, style: t.microSoft),
          if (done) ...[
            const SizedBox(height: DashSpace.md),
            FilledButton.icon(
              onPressed: onNext,
              icon: Icon(last ? Icons.check : Icons.arrow_forward),
              label: Text(last ? l10n.tourFinish : l10n.tourNext),
            ).tagged(last ? 'tour.finish' : 'tour.next'),
          ],
        ],
      ),
    );
    return Positioned(
      left: 0,
      right: 0,
      top: atTop ? 0 : null,
      bottom: atTop ? null : 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(DashSpace.gutter),
          // Scrolls rather than overflows: a phone on its side, or a large
          // system text size, leaves less height than the card wants.
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: screen.height * _maxHeightShare,
            ),
            child: SingleChildScrollView(
              child: Material(type: MaterialType.transparency, child: card),
            ),
          ),
        ),
      ),
    );
  }
}
