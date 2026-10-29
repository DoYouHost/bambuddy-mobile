import 'dart:async';
import 'dart:math' as math;

import 'package:app_report_ui/app_report_ui.dart';
import 'package:bambuddy_mobile/core/app_context.dart';
import 'package:bambuddy_mobile/core/demo/demo_backend.dart';
import 'package:bambuddy_mobile/core/settings/appearance_prefs.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/theme/app_brand.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/features/common/spool_colour_wheel.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';
import 'a11y_contrast_report.dart';

/// The shared half of the rendered-guideline tests: one surface, measured under
/// every accent and both brightnesses. The plan and the rules are in
/// docs/plans/a11y-guideline-tests.md; a feature's file only lists its surfaces.

/// The default, the lightest preset fill, and the exact-grey path.
const a11yAccents = [
  AccentSource.bambuddy,
  AccentSource.orange,
  AccentSource.graphite,
];

/// Tall enough that a lazy list builds most of a screen in one frame; the rest
/// is reached by [a11ySurface]'s scroll pass.
const a11yWindow = Size(411, 2000);

/// Text scales a surface is measured at besides 100 %. Layout, overflow and
/// tap-target findings come from the text size, not from the colours, so these run
/// under the first accent in the light theme only: AGENTS.md asks every layout
/// test to pass above 100 %, and this keeps it at two tests more per surface.
const a11yTextScales = [1.5, 2.0];

/// The demo backend's profile: the app's own fabricated server, so a screen
/// shows the data the demo promises without a mock per route. A surface that
/// needs another face of it (an API key, a labelled server) passes `profile:`
/// to [a11ySurface]; a second override in `overrides` would not win.
const a11yDemoProfile = ServerProfile(
  baseUrl: DemoConfig.baseUrl,
  authMode: AuthMode.none,
);

/// [a11yDemoProfile] as an override, for the few callers that build their own scope.
final a11yDemoProfileOverride = serverProfileOverride(a11yDemoProfile);

/// The platform notification plugin has no platform to ask in a test; this one
/// records what it is given and answers nothing.
final a11yQuietNotifications = notificationServiceProvider.overrideWithValue(
  RecordingNotifications(),
);

/// What a screen touches on its first frame that the demo backend cannot
/// answer: the notification plugin and the foreground service.
final a11yPlatformOverrides = [
  a11yQuietNotifications,
  inertBackgroundMonitorOverride,
];

/// Horizontal paint offset of the whole app, in dp. [a11yPump] applies it; the
/// contrast guideline moves it to re-measure a finding at another sub-pixel phase.
final a11yPhase = ValueNotifier<double>(0);

/// Pumps [home] under [accent] and [brightness] in Polish, then lets it settle.
///
/// Not `pumpAndSettle`: the demo is timed (a poll, a simulated print) and never
/// goes idle, so it runs [settleFor] of frames instead.
Future<void> a11yPump(
  WidgetTester tester,
  Widget home,
  AccentSource accent,
  Brightness brightness, {
  List<Override> overrides = const [],
  Size window = a11yWindow,
  Duration settleFor = const Duration(seconds: 2),
  Map<String, Object> prefs = const {},
  double textScale = 1,
}) async {
  useLogicalWindow(tester, window);
  SharedPreferences.setMockInitialValues(prefs);
  final sharedPrefs = await SharedPreferences.getInstance();
  a11yPhase.value = 0;
  final app = ProviderScope(
    retry: neverRetry,
    // A surface's own preferences win: Riverpod 3 refuses the same override twice.
    overrides: layerOverrides([
      sharedPreferencesProvider.overrideWithValue(sharedPrefs),
    ], overrides.isEmpty ? [noServerProfileOverride] : overrides),
    child: MaterialApp(
      theme: buildDashThemeData(brightness, brand: resolveBrand(accent, null)),
      locale: const Locale('pl'),
      localizationsDelegates: [
        AppLocalizations.delegate,
        ReportLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    ),
  );
  await tester.pumpWidget(
    ValueListenableBuilder<double>(
      valueListenable: a11yPhase,
      builder: (_, dx, child) =>
          Transform.translate(offset: Offset(dx, 0), child: child),
      child: app,
    ),
  );
  await a11ySettle(tester, settleFor);
}

/// Frames in 100 ms steps, so each timed answer lands before the next is asked.
Future<void> a11ySettle(WidgetTester tester, Duration total) async {
  for (
    var t = Duration.zero;
    t < total;
    t += const Duration(milliseconds: 100)
  ) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// `androidTapTargetGuideline` (48 dp) with exactly one exception: the arrow of a
/// filterable `dashCombo`, which is a button of its own beside a field that is the
/// real target. It is skipped only when it measures at least [floor] dp both ways,
/// so a shrunken arrow fails again. Nothing under [floor] is ever excused: that is a
/// bug to fix in the app, not a false positive.
class A11yTapTargets extends MinimumTapTargetGuideline {
  const A11yTapTargets()
    : super(
        size: const Size(48, 48),
        link:
            'https://support.google.com/accessibility/android/answer/7101858?hl=en',
      );

  static const floor = 40.0;

  /// The tag `InputDecorator` puts on its suffix icon.
  static const _suffixIcon = SemanticsTag('_InputDecoratorState.suffixIcon');

  @override
  bool shouldSkipNode(SemanticsNode node) =>
      super.shouldSkipNode(node) ||
      _cutByViewport(node) ||
      ((node.tags?.contains(_suffixIcon) ?? false) &&
          node.rect.width >= floor &&
          node.rect.height >= floor);

  /// A control a scrollable's viewport cuts. `SemanticsNode.rect` is already
  /// clipped, so a button half scrolled out reads as a small one and fails for a
  /// reason that is not in the app. Flutter's own guideline skips a node that
  /// touches *any* edge of a scrollable, sides included, so it hides a control
  /// flush with the left of a list and still misses one a scale moved. Here the
  /// node's rect and the viewport's paint clip are compared, both in the node's
  /// own coordinates.
  ///
  /// Only a node flush with its clip on the axis a scrollable above it scrolls is
  /// skipped, and
  /// [a11yMeetsAllWhileScrolling] pages with an overlap taller than any target, so
  /// every control stands whole in the viewport at some stop and is measured
  /// there. A control that is flush with the viewport at the very first or last
  /// stop is the one gap, as it is in Flutter's own guideline.
  static bool _cutByViewport(SemanticsNode node) {
    final clip = node.parentPaintClipRect;
    if (clip == null) return false;
    var vertical = false;
    var horizontal = false;
    for (var a = node.parent; a != null; a = a.parent) {
      final data = a.getSemanticsData();
      vertical |=
          data.hasAction(SemanticsAction.scrollUp) ||
          data.hasAction(SemanticsAction.scrollDown);
      horizontal |=
          data.hasAction(SemanticsAction.scrollLeft) ||
          data.hasAction(SemanticsAction.scrollRight);
    }
    if (!vertical && !horizontal) return false;
    // Both are in the node's own coordinates, so a scale above does not matter.
    final rect = node.rect;
    const eps = 0.01;
    // Only the edges the list scrolls across: a row as wide as the list is flush
    // with its sides all the time, and is not cut.
    return (vertical &&
            ((rect.top - clip.top).abs() < eps ||
                (rect.bottom - clip.bottom).abs() < eps)) ||
        (horizontal &&
            ((rect.left - clip.left).abs() < eps ||
                (rect.right - clip.right).abs() < eps));
  }
}

/// [labeledTapTargetGuideline] with one exception: whatever a [SpoolColourWheel]
/// draws. That is `flex_color_picker`'s own gesture node, which is a semantic
/// boundary of its own, so a name on a parent never reaches it and giving it one
/// means rebuilding the picker from its parts. Decided 2026-10-29 to leave it. The
/// rest of every dialog that holds one is still checked, and so are its sizes.
class A11yLabeledTapTargets extends AccessibilityGuideline {
  const A11yLabeledTapTargets();

  @override
  String get description => 'Tappable widgets should have a semantic label';

  @override
  FutureOr<Evaluation> evaluate(WidgetTester tester) {
    final wheels = [
      for (final e in find.byType(SpoolColourWheel).evaluate())
        if (e.renderObject case final RenderBox box)
          box.localToGlobal(Offset.zero) & box.size,
    ];
    var result = const Evaluation.pass();
    for (final view in tester.binding.renderViews) {
      result += _traverse(
        view.owner!.semanticsOwner!.rootSemanticsNode!,
        wheels,
      );
    }
    return result;
  }

  /// The node's rect in the window: each ancestor's transform applies in turn.
  static Rect _globalRect(SemanticsNode node) {
    var matrix = Matrix4.identity();
    for (SemanticsNode? n = node; n != null; n = n.parent) {
      final t = n.transform;
      if (t != null) matrix = t * matrix;
    }
    return MatrixUtils.transformRect(matrix, node.rect);
  }

  Evaluation _traverse(SemanticsNode node, List<Rect> wheels) {
    var result = const Evaluation.pass();
    node.visitChildren((child) {
      result += _traverse(child, wheels);
      return true;
    });
    if (node.isMergedIntoParent ||
        node.isInvisible ||
        node.flagsCollection.isHidden ||
        node.flagsCollection.isTextField) {
      return result;
    }
    final data = node.getSemanticsData();
    if (!data.hasAction(SemanticsAction.longPress) &&
        !data.hasAction(SemanticsAction.tap)) {
      return result;
    }
    if (data.label.isNotEmpty || data.tooltip.isNotEmpty) return result;
    final rect = _globalRect(node);
    if (wheels.any((w) => w.inflate(1).contains(rect.center))) return result;
    return result +
        Evaluation.fail(
          '$node: expected tappable node to have semantic label, '
          'but none was found.',
        );
  }
}

/// The three guidelines on what is laid out right now. All three run and every
/// finding is reported together: stopping at the first failing guideline hid
/// the tap-target and label findings behind the contrast ones.
Future<void> a11yMeetsAll(
  WidgetTester tester, {
  bool Function(SemanticsData data)? skipContrast,
}) async {
  final guidelines = <AccessibilityGuideline>[
    _ContrastBesideMisreads(skipContrast),
    const A11yTapTargets(),
    const A11yLabeledTapTargets(),
  ];
  var result = const Evaluation.pass();
  for (final guideline in guidelines) {
    result += await guideline.evaluate(tester);
  }
  expect(result.passed, isTrue, reason: result.reason);
}

/// Whether [finder] matches now. `.first` and `.last` finders throw instead of
/// matching nothing.
bool _built(Finder finder) {
  try {
    return finder.evaluate().isNotEmpty;
  } on StateError {
    return false;
  }
}

/// The list of the route on top: behind an open sheet, the first vertical
/// scrollable in the tree is the screen underneath, not the sheet.
ScrollPosition? _mainList() {
  final scrollables = find.byType(Scrollable).evaluate().where((e) {
    final state = (e as StatefulElement).state as ScrollableState;
    return state.position.axis == Axis.vertical &&
        (ModalRoute.of(e)?.isCurrent ?? true);
  });
  if (scrollables.isEmpty) return null;
  return ((scrollables.first as StatefulElement).state as ScrollableState)
      .position;
}

/// Pages the screen's list from the top until [finder] builds, and leaves it
/// where it was found. A lazy list holds no element for a row past the fold, and
/// one the list was already scrolled past is no more built than one below it.
Future<bool> _pageUntilBuilt(
  WidgetTester tester,
  Finder finder, {
  int maxPages = 12,
}) async {
  if (_built(finder)) return true;
  final position = _mainList();
  if (position == null) return false;
  if (position.pixels > 0) {
    position.jumpTo(0);
    await tester.pump(const Duration(milliseconds: 100));
  }
  for (var page = 0; page < maxPages && !_built(finder); page++) {
    if (position.pixels >= position.maxScrollExtent) break;
    position.jumpTo(
      (position.pixels + position.viewportDimension).clamp(
        0.0,
        position.maxScrollExtent,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  return _built(finder);
}

/// Whether [finder] builds, paging the screen's list to find out, then back to
/// the top. At a large text size the widget that proves a surface was reached can
/// be past the fold.
Future<bool> _reveal(WidgetTester tester, Finder finder) async {
  final found = await _pageUntilBuilt(tester, finder);
  final position = _mainList();
  if (position != null && position.pixels > 0) {
    position.jumpTo(0);
    await tester.pump(const Duration(milliseconds: 100));
  }
  return found;
}

/// How far one stop of [a11yMeetsAllWhileScrolling] overlaps the last: taller than
/// any target on a screen, so a control cut by the edge at one stop stands whole at
/// the next. The tap-target guideline skips a node the viewport cuts
/// ([A11yTapTargets]); the overlap is what keeps that from hiding it.
const _pageOverlap = 72.0;

/// Closes a menu that hangs off the list about to be paged, once the surface has
/// been measured with it open. The paging jumps that list; a field that scrolls out
/// of a lazy list takes the menu's anchor with it and Flutter lays the overlay out
/// at NaN. No finger can do that (the menu's barrier takes the first drag and only
/// closes it), and the form behind the menu is worth its scrolling pass all the
/// same. A menu on another route, behind a sheet that is the one being paged, is
/// left alone: Escape would close the sheet and leave that menu under a list that
/// then scrolls.
Future<void> _closeMenuOn(WidgetTester tester, ScrollPosition position) async {
  final route = ModalRoute.of(position.context.storageContext);
  final hangsOff = find
      .byType(MenuItemButton)
      .evaluate()
      .any((e) => ModalRoute.of(e) == route);
  if (!hangsOff) return;
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pump(const Duration(milliseconds: 300));
}

/// Scrolls the screen's main list one viewport less [_pageOverlap] at a time and
/// asserts at each stop: a guideline only sees what is built, and a lazy list
/// builds the viewport plus a little. A screen without a vertical scrollable has
/// nothing to do.
Future<void> a11yMeetsAllWhileScrolling(
  WidgetTester tester, {
  bool Function(SemanticsData data)? skipContrast,
  int maxPages = 16,
}) async {
  await a11yMeetsAll(tester, skipContrast: skipContrast);
  final position = _mainList();
  if (position == null) return;
  await _closeMenuOn(tester, position);
  // A tap on a target down the list leaves it scrolled; the pages above would
  // never be measured.
  if (position.pixels > 0) {
    position.jumpTo(0);
    await tester.pump(const Duration(milliseconds: 100));
    await a11yMeetsAll(tester, skipContrast: skipContrast);
  }
  // Never less than half a viewport, so a short one still advances.
  final step = math.max(
    position.viewportDimension - _pageOverlap,
    position.viewportDimension / 2,
  );
  for (var page = 0; page < maxPages; page++) {
    if (position.pixels >= position.maxScrollExtent) return;
    position.jumpTo(
      (position.pixels + step).clamp(0.0, position.maxScrollExtent),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await a11yMeetsAll(tester, skipContrast: skipContrast);
  }
}

/// Scrolls the first match into view, taps it and lets the animation it starts
/// finish. Not `pumpAndSettle`: the demo's poll timers never let the tree idle.
Future<void> a11yTap(
  WidgetTester tester,
  Finder finder, {
  Duration settle = const Duration(milliseconds: 700),
}) async {
  await _pageUntilBuilt(tester, finder);
  await _scrollIntoView(tester, finder);
  await tester.tap(finder.first);
  await a11ySettle(tester, settle);
}

/// Scrolls the first match to the middle of its scrollable and lays the frame out.
///
/// `ensureVisible` moves the scroll position but not the render tree: without a
/// frame the finder still answers with the old position, and a tap lands where the
/// control was, below the fold, on whatever is there. Its default puts the control
/// at the leading edge, which under a pinned header is a place nothing can be
/// tapped at; the middle is clear of the headers a screen pins.
Future<void> _scrollIntoView(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder.first), alignment: 0.5);
  await tester.pump();
}

Future<void> a11yLongPress(
  WidgetTester tester,
  Finder finder, {
  Duration settle = const Duration(milliseconds: 700),
}) async {
  await _scrollIntoView(tester, finder);
  await tester.longPress(finder.first);
  await a11ySettle(tester, settle);
}

/// A diagnostic id that only starts with [prefix] (`printer.ams_slot|1|2`):
/// `byLogId` matches whole ids, and a row's id carries what tells it apart.
Finder a11yByLogIdStarting(String prefix) => find.byWidgetPredicate(
  (w) => w is Semantics && (w.properties.identifier ?? '').startsWith(prefix),
);

/// Gives the real event loop a turn of [real]. Whatever completed outside the
/// test's fake zone (a big JSON decoded off the main isolate, an asset read, a
/// future finished in `setUpAll`) resumes only then; the frames after it let
/// the screen pick the answer up.
Future<void> a11yRealTime(
  WidgetTester tester, {
  Duration real = Duration.zero,
  Duration frames = const Duration(milliseconds: 500),
}) async {
  await tester.runAsync(() => Future<void>.delayed(real));
  await a11ySettle(tester, frames);
}

/// A host with one button that opens a surface the screen under test does not
/// show on its own: a sheet, a dialog or a pushed screen. [open] gets the
/// button's context. The tour wraps it in its own host.
class A11yLauncher extends StatelessWidget {
  const A11yLauncher(this.open, {super.key});

  /// What the button is labelled; [a11yOpenLauncher] finds it by this.
  static const label = 'open';

  final void Function(BuildContext context) open;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => open(context),
        child: const Text(label),
      ),
    ),
  );
}

/// Presses the [A11yLauncher] button, for an `arrange:`.
Future<void> a11yOpenLauncher(
  WidgetTester tester, {
  Duration settle = const Duration(milliseconds: 700),
}) => a11yTap(tester, find.text(A11yLauncher.label), settle: settle);

/// The device's time zone is asked over this channel by the stats requests.
/// Unanswered, the reply arrives on the real event loop and a request starts
/// after the test has ended (a pending timer).
const _clockChannel = MethodChannel(
  'page.codeberg.morganmlgman.bambuddy/clock',
);

void _answerClockChannel() => TestDefaultBinaryMessengerBinding
    .instance
    .defaultBinaryMessenger
    .setMockMethodCallHandler(_clockChannel, (call) async => null);

/// Registers one test per accent × brightness for a single surface.
///
/// * [home] builds the screen, [arrange] gets it into the state to measure (an
///   open sheet, a switched tab, a filled field);
/// * [overrides] default to the demo backend ([demo]); pass `demo: false` and
///   your own overrides for a surface the demo cannot reach;
/// * [skipContrast] narrows [textContrastGuideline] for a node it misreads —
///   a false positive only, and always with the reason in a comment. A real
///   violation is fixed in the app;
/// * [shows] must match something before anything is measured — what the
///   surface is about (its title, a row the demo seeds), never a placeholder;
/// * [profile] is the server the demo answers as (default [a11yDemoProfile]);
/// * [prefs] seeds SharedPreferences before the screen builds;
/// * [scroll] re-asserts after each viewport of the main list;
/// * [textScales] are the extra text sizes, see [a11yTextScales]. A surface that
///   cannot hold one passes a narrower list and says why in a comment, never
///   drops it silently.
void a11ySurface(
  String name, {
  required Widget Function() home,
  Future<void> Function(WidgetTester tester)? arrange,
  List<Override> overrides = const [],
  bool demo = true,
  Size window = a11yWindow,
  Duration settleFor = const Duration(seconds: 2),
  bool Function(SemanticsData data)? skipContrast,
  bool scroll = true,
  Finder? shows,
  Map<String, Object> prefs = const {},
  ServerProfile profile = a11yDemoProfile,
  List<double> textScales = a11yTextScales,
}) {
  final runs = <(AccentSource, Brightness, double)>[
    for (final accent in a11yAccents)
      for (final brightness in Brightness.values) (accent, brightness, 1),
    for (final scale in textScales)
      (a11yAccents.first, Brightness.light, scale),
  ];
  for (final (accent, brightness, scale) in runs) {
    final label = scale == 1 ? '' : ', text ${(scale * 100).round()}%';
    testWidgets('$name: ${accent.name}, ${brightness.name}$label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      // Process-wide and mutable (a mute, a performed task): without a reset
      // one surface's writes show in the next surface's data.
      DemoBackend.instance = DemoBackend.fresh();
      _answerClockChannel();
      await a11yPump(
        tester,
        home(),
        accent,
        brightness,
        overrides: [if (demo) serverProfileOverride(profile), ...overrides],
        window: window,
        settleFor: settleFor,
        prefs: prefs,
        textScale: scale,
      );
      if (arrange != null) {
        await arrange(tester);
        await a11ySettle(tester, const Duration(milliseconds: 500));
      }
      // Proves the surface was reached, so a failure below is a guideline
      // and not a screen that never built.
      if (shows != null && !await _reveal(tester, shows)) {
        expect(shows, findsWidgets);
      }
      if (scroll) {
        await a11yMeetsAllWhileScrolling(tester, skipContrast: skipContrast);
      } else {
        await a11yMeetsAll(tester, skipContrast: skipContrast);
      }
      // A request the scroll pass started would end the test in flight.
      await a11ySettle(tester, const Duration(milliseconds: 700));
      // A poll can start a request in the last frame; the demo answers after 120 ms
      // of fake time, so unmounting stops the polls and 200 ms lets that one finish.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 200));
      handle.dispose();
    });
  }
}

/// [textContrastGuideline] minus the nodes it misreads. It takes the text
/// colour from the commonest light and dark pixels of the node's whole rect,
/// and these fool it:
///
/// * a section header: a short label ("WYGLĄD") in a full-width row leaves too
///   few text pixels — 1.11:1 for the short label, a pass for the same header
///   with a long one. Its ink is `accentInk`, which `dashContrastAudit` holds
///   at 4.5:1 on every ground;
/// * the dashboard's "next available" line: 12 px grey on a grey ground, where
///   the anti-aliased edges outnumber the glyph cores — 3.82:1 read, 8.39:1
///   between its brightest glyph pixel and the ground (graphite, dark).
///
/// Beyond those two, a finding has to survive two more checks before it fails a
/// test: it must fail at every sub-pixel phase (see [phases]), and the text's
/// own colours must fail too ([judgeContrastFindings]). The pixel measure reads
/// 11-14 dp semi-transparent text badly (a large share of the findings were
/// text that passes at 5:1 by its own colours); a finding the colours back up,
/// or cannot judge, still fails.
///
/// [extra] is a surface's own narrowing, reason in its file.
class _ContrastBesideMisreads extends MinimumTextContrastGuideline {
  const _ContrastBesideMisreads([this.extra]);

  final bool Function(SemanticsData data)? extra;

  @override
  bool shouldSkipNode(SemanticsData data) =>
      super.shouldSkipNode(data) ||
      data.flagsCollection.isHeader ||
      data.label.startsWith(pl.nextAvailableLabel) ||
      (extra?.call(data) ?? false);

  /// Paint offsets, in dp, a finding is measured again at. The histogram's
  /// "commonest dark colour" depends on where a glyph's edge falls in a pixel:
  /// 13 px dark ink on a light chip read 1.37:1 at one x phase out of twenty and
  /// passed at the other nineteen. A real shortfall does not depend on the phase.
  static const phases = [0.37, 0.71];

  static final _nodeId = RegExp(r'SemanticsNode#(\d+)');

  /// One finding per node and element: a report is the nodes' messages one
  /// after another, and a node whose label several Texts share is reported once
  /// per Text. The same node's findings are numbered in the order they appear,
  /// which a re-measure of an unchanged tree keeps.
  static Map<String, String> _findings(Evaluation e) {
    final seen = <String, int>{};
    return {
      for (final part in (e.reason ?? '').split(
        RegExp(r'(?=SemanticsNode#\d+\()'),
      ))
        if (_nodeId.firstMatch(part) case final m?)
          '${m.group(1)}/${seen.update(m.group(1)!, (n) => n + 1, ifAbsent: () => 0)}':
              part,
    };
  }

  /// Fails only the nodes that fail at the shipped position and at every phase.
  /// Needs [a11yPhase] to move something: on a tree built without [a11yPump] the
  /// phases measure the same pixels and the findings stand.
  @override
  Future<Evaluation> evaluate(WidgetTester tester) async {
    final shipped = await super.evaluate(tester);
    if (shipped.passed) return shipped;
    final findings = _findings(shipped);
    for (final phase in phases) {
      a11yPhase.value = phase;
      await tester.pump();
      final again = _findings(await super.evaluate(tester));
      findings.removeWhere((id, _) => !again.containsKey(id));
      if (findings.isEmpty) break;
    }
    a11yPhase.value = 0;
    await tester.pump();
    // The guideline reads no colour; see [ContrastVerdict]. A finding stands
    // unless the text's own colours pass on every ground behind every paragraph
    // of the node.
    final judged = await judgeContrastFindings(tester, findings);
    reportContrastFindings(judged);
    findings.removeWhere(
      (k, _) => judged[k]?.verdict == ContrastVerdict.artefact,
    );
    return findings.isEmpty
        ? const Evaluation.pass()
        : Evaluation.fail(findings.values.join('\n'));
  }
}
