import 'package:app_report_ui/app_report_ui.dart';
import 'package:bambuddy_mobile/core/app_context.dart';
import 'package:bambuddy_mobile/core/demo/demo_backend.dart';
import 'package:bambuddy_mobile/core/settings/appearance_prefs.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/theme/app_brand.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
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
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sharedPrefs),
      ...overrides.isEmpty ? [noServerProfileOverride] : overrides,
    ],
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
      ((node.tags?.contains(_suffixIcon) ?? false) &&
          node.rect.width >= floor &&
          node.rect.height >= floor);
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
    labeledTapTargetGuideline,
  ];
  var result = const Evaluation.pass();
  for (final guideline in guidelines) {
    result += await guideline.evaluate(tester);
  }
  expect(result.passed, isTrue, reason: result.reason);
}

/// Scrolls the screen's main list one viewport at a time and asserts at each
/// stop: a guideline only sees what is built, and a lazy list builds the
/// viewport plus a little. A screen without a vertical scrollable has nothing to do.
Future<void> a11yMeetsAllWhileScrolling(
  WidgetTester tester, {
  bool Function(SemanticsData data)? skipContrast,
  int maxPages = 12,
}) async {
  await a11yMeetsAll(tester, skipContrast: skipContrast);
  // The list of the route on top: behind an open sheet, the first vertical
  // scrollable in the tree is the screen underneath, not the sheet.
  final scrollables = find.byType(Scrollable).evaluate().where((e) {
    final state = (e as StatefulElement).state as ScrollableState;
    return state.position.axis == Axis.vertical &&
        (ModalRoute.of(e)?.isCurrent ?? true);
  });
  if (scrollables.isEmpty) return;
  final state = (scrollables.first as StatefulElement).state as ScrollableState;
  final position = state.position;
  for (var page = 0; page < maxPages; page++) {
    if (position.pixels >= position.maxScrollExtent) return;
    position.jumpTo(
      (position.pixels + position.viewportDimension).clamp(
        0.0,
        position.maxScrollExtent,
      ),
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
  await tester.ensureVisible(finder.first);
  await tester.tap(finder.first);
  await a11ySettle(tester, settle);
}

Future<void> a11yLongPress(
  WidgetTester tester,
  Finder finder, {
  Duration settle = const Duration(milliseconds: 700),
}) async {
  await tester.ensureVisible(finder.first);
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
      if (shows != null) expect(shows, findsWidgets);
      if (scroll) {
        await a11yMeetsAllWhileScrolling(tester, skipContrast: skipContrast);
      } else {
        await a11yMeetsAll(tester, skipContrast: skipContrast);
      }
      // A request the scroll pass started would end the test in flight.
      await a11ySettle(tester, const Duration(milliseconds: 700));
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

  /// One finding per node: a report is the nodes' messages one after another.
  static Map<String, String> _findings(Evaluation e) => {
    for (final part in (e.reason ?? '').split(
      RegExp(r'(?=SemanticsNode#\d+\()'),
    ))
      if (_nodeId.firstMatch(part) case final m?) m.group(1)!: part,
  };

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
    return findings.isEmpty
        ? const Evaluation.pass()
        : Evaluation.fail(findings.values.join('\n'));
  }
}
