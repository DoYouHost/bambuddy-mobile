import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bambuddy_mobile/core/auth/credentials_store.dart';
import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/watch/watch_config_sync.dart';
import 'package:bambuddy_mobile/features/archive/archive_providers.dart';
import 'package:bambuddy_mobile/features/dashboard/firmware_providers.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/ams_history_sheet.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/heater_history_sheet.dart';
import 'package:bambuddy_mobile/features/maintenance/maintenance_providers.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/wear/wear_shape.dart';
import 'package:bambuddy_mobile/wear/wear_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_connectivity/watch_connectivity.dart';

/// Hands the app a temporary directory the test owns, so whatever a download
/// leaves in the cache can be listed afterwards.
///
/// Assign it to `PathProviderPlatform.instance` in `setUp` and delete the
/// directory in `tearDown`; there is nothing to restore, the app reads the
/// instance on every call.
class TempDirProvider extends PathProviderPlatform {
  TempDirProvider(this.path);

  final String path;

  @override
  Future<String?> getTemporaryPath() async => path;
}

/// Inert firmware for widget tests: the printer card reads firmware while it
/// renders and the tests do not assert on it — null keeps the fetch off the
/// network, which otherwise leaves a hanging Dio timer and fails the test.
final inertFirmwareOverride =
    printerFirmwareProvider.overrideWith((ref, id) => null);

/// Inert total print time for widget tests: the printer card reads it from the
/// maintenance overview while it renders. Null keeps that off the network, the
/// same trap as [inertFirmwareOverride].
final inertTotalPrintHoursOverride =
    printerTotalPrintHoursProvider.overrideWith((ref, id) => null);

/// Inert chamber ceiling for widget tests. The temperature tiles read the
/// server's `MAX_CHAMBER_TEMP_C` at render time, which otherwise hits
/// `/updates/version` and leaves a hanging Dio timer — the same trap as
/// [inertFirmwareOverride]. 60 is what an unknown version resolves to anyway,
/// so gauges and sliders behave exactly as they do before the probe lands.
final inertChamberMaxOverride =
    chamberMaxTargetProvider.overrideWith((ref) async => 60);

/// Inert history gating for widget tests. The temperature tiles and the AMS
/// humidity/temperature chips ask whether the server keeps history, which reads
/// the server version over the network — the same hanging-timer trap as
/// [inertFirmwareOverride]. `true` is what any current server answers, so the
/// shortcuts render exactly as they do in the app.
final inertHistorySupportOverrides = [
  heaterHistorySupportedProvider.overrideWith((ref) async => true),
  amsHistorySupportedProvider.overrideWith((ref) async => true),
];

/// Wraps a widget in a MaterialApp with Polish localization — the tests assert
/// Polish strings, so the locale is forced to `pl`.
///
/// [builder] goes to `MaterialApp.builder`, which is above the navigator: that is
/// the only place an inherited widget reaches a pushed route or a dialog as well
/// as `home`.
Widget plApp(Widget child, {TransitionBuilder? builder}) => MaterialApp(
      locale: const Locale('pl'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: builder,
      home: child,
    );

/// Pumps a fixed span in place of `pumpAndSettle`, for the screens it can never
/// finish on: a search field's cursor blinks forever, so no frame is ever free
/// of animation and settling waits for one that will not come.
///
/// Three frames of 350 ms — long enough for a sheet, a dialog or a snack to
/// finish opening, which is what every caller is actually waiting for. Written
/// out in five test files before it lived here, and it is the kind of thing
/// that gets copied with one frame fewer.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 350));
  }
}

/// Pumps a wear widget with what every wear test needs anyway: mock preferences,
/// an in-memory credentials store, and a handle on the container so a test can
/// read or seed providers.
///
/// [wrapInApp] is false for `WearApp`, which builds its own `MaterialApp` (and
/// therefore runs in the system locale, not `plApp`'s Polish); every other wear
/// widget needs the harness to have localizations at all.
///
/// The scope owns the container on purpose, rather than the test holding one and
/// handing it over: `wearFleetProvider` runs a poll timer, and a container that
/// outlives the widget tree keeps that timer alive past the end of the test —
/// which trips the framework's pending-timer check. Tearing the tree down
/// disposes the container, which cancels it.
Future<ProviderContainer> pumpWear(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  bool wrapInApp = true,
  WearShape shape = WearShape.round,
  Size face = wearFaceSmall,
}) async {
  useWatchFace(tester, shape, face);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  late ProviderContainer container;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      credentialsStoreProvider.overrideWithValue(InMemoryCredentialsStore()),
      ...overrides,
    ],
    child: Builder(builder: (context) {
      container = ProviderScope.containerOf(context, listen: false);
      return wrapInApp
          ? plApp(child, builder: wearShapeBuilder)
          : child;
    }),
  ));
  await tester.pumpAndSettle();
  return container;
}

/// [WearShapeScope] where `WearApp` puts it — above the navigator, so a dialog
/// or a pushed route reads the same shape as the screen that opened it.
///
/// Wrapping the *child* instead leaves the scope under `home`, and a route is
/// `home`'s sibling rather than its descendant: every dialog then silently fell
/// back to round, which is the one shape a test asking for a square face is not
/// looking for.
Widget wearShapeBuilder(BuildContext context, Widget? child) =>
    WearShapeScope(child: child!);

/// The two round faces worth testing against, in physical pixels at density 2.
///
/// The small one is the default here on purpose: it is what Wear emulators boot
/// with and what the smaller watches ship, and it is where a size written as a
/// number instead of a fraction of the display breaks — the confirm dialog's
/// button row fit 225 dp and overflowed 192 dp by 11 px, with every test green.
const wearFaceSmall = Size(384, 384);
const wearFaceLarge = Size(450, 450);

/// A real watch instead of the 800x600 phone surface every widget test defaults
/// to: the round-safe layout only means anything against a face this small.
///
/// The shape is answered on `MainActivity`'s `wear_shape` channel, the way the
/// platform answers it on a device.
void useWatchFace(WidgetTester tester, WearShape shape, Size face) {
  tester.view.physicalSize = face;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    wearShapeChannel,
    (call) async =>
        call.method == 'isScreenRound' ? shape == WearShape.round : null,
  );
  addTearDown(() => messenger.setMockMethodCallHandler(wearShapeChannel, null));
}

/// The channel [WearShapeQuery] talks to, so tests answer the same one the app
/// asks.
const wearShapeChannel =
    MethodChannel('page.codeberg.morganmlgman.bambuddy/wear_shape');

/// Brings [finder] onto the watch face, scrolling the screen if it has to.
///
/// On a 225 dp face most of a wear screen starts below the fold, and a
/// `ListView` does not build what is off-screen at all — so a finder that used
/// to match on the 800x600 default test surface now matches nothing until the
/// screen is scrolled. Reaching for a control the way a user does is the point:
/// it is the same scroll Google Play's reviewer had to make.
Future<void> revealOnWatch(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 40,
        scrollable: find.byType(Scrollable).first);
  }
  // Into the *middle* of the face, not merely into the viewport. A curved list
  // runs all the way to the rim, so "on screen" now includes the last few
  // degrees of the circle, where an item is scaled almost to nothing — existing
  // there is not the same as being readable or hittable, and `scrollUntilVisible`
  // stops at the first of those. A user scrolls what they want to the centre.
  await Scrollable.ensureVisible(finder.evaluate().first,
      alignment: 0.5, duration: Duration.zero);
  await tester.pumpAndSettle();
}

/// Fails unless every corner of [finder]'s box is on the round face's glass.
///
/// The check no wear test had, and the one the snackbar walked straight past: a
/// widget test is happy as long as nothing overflows the *square* the display
/// reports, while the watch only ever lights the circle inscribed in it. A bar
/// pinned to the bottom of that square is not an overflow — it is simply mostly
/// invisible, on the device and nowhere else.
///
/// Reach for it on anything the layout places rather than the scroll view: what
/// goes through `WearScrollView` is already inside the glass by construction.
void expectOnGlass(WidgetTester tester, Finder finder, {String? reason}) {
  final face = tester.view.physicalSize / tester.view.devicePixelRatio;
  final centre = Offset(face.width / 2, face.height / 2);
  final radius = face.shortestSide / 2;
  final box = tester.getRect(finder);
  for (final corner in [
    box.topLeft,
    box.topRight,
    box.bottomLeft,
    box.bottomRight,
  ]) {
    expect(
      (corner - centre).distance,
      lessThanOrEqualTo(radius),
      reason: reason ?? 'corner $corner of $box is off a ${radius * 2} dp face',
    );
  }
}

/// [revealOnWatch] and then tap, for the controls a test drives rather than
/// asserts on.
///
/// Settles the scroll before the tap but only pumps one frame after it: what a
/// tap starts is the test's business, and a watch action that puts a spinner up
/// would hang `pumpAndSettle` forever.
Future<void> tapOnWatch(WidgetTester tester, Finder finder) async {
  await revealOnWatch(tester, finder);
  await tester.tap(finder);
  await tester.pump();
}

/// Loads a fixture from test/fixtures/ — the path is relative to the package
/// root, which is where `flutter test` runs from.
dynamic readFixture(String name) => jsonDecode(readFixtureString(name));

/// A fixture's raw contents, for the parsers that take text (WS frames, say).
String readFixtureString(String name) =>
    File('test/fixtures/$name').readAsStringSync();

/// The phone→watch handoff, faked, with knobs for every shape the wear tests
/// need: what the Data Layer has latched, what it pushes live, and whether
/// persisting the result works.
///
/// One fake rather than one per test file: three of them had grown, each
/// re-deriving the same `super(...)` and stubbing a different third of the API.
class FakeWatchConfigSync extends WatchConfigSync {
  FakeWatchConfigSync({
    this.pending,
    StreamController<WatchConfig>? pushes,
    this.failsToApply = false,
    this.applyGate,
  })  : pushes = pushes ?? StreamController<WatchConfig>.broadcast(),
        super(
          watch: WatchConnectivity(),
          credentials: InMemoryCredentialsStore(),
        );

  /// What the phone has latched — what [latestPending] answers.
  final WatchConfig? pending;

  /// Live pushes. Add to it to act as a phone that pushed while the app is open.
  final StreamController<WatchConfig> pushes;

  /// Make [apply] throw, the way secure storage does when the Keystore no longer
  /// holds the key the secrets were written with.
  final bool failsToApply;

  /// When set, [apply] does not finish until the test completes it — that is how
  /// a write still in flight is held open while the screen goes away.
  final Completer<void>? applyGate;

  /// Every config [apply] was asked to persist, in order.
  final applied = <WatchConfig>[];

  @override
  Future<WatchConfig?> latestPending() async => pending;

  @override
  Stream<WatchConfig> configStream() => pushes.stream;

  @override
  Future<void> apply(WatchConfig config) async {
    applied.add(config);
    if (failsToApply) throw Exception('keystore is gone');
    if (applyGate != null) await applyGate!.future;
  }
}

/// An in-memory CredentialsStore, so the core tests never touch the plugin.
class InMemoryCredentialsStore implements CredentialsStore {
  String? jwt;
  String? apiKey;
  String? username;
  String? password;

  @override
  Future<String?> readJwt() async => jwt;

  @override
  Future<void> writeJwt(String token) async => jwt = token;

  @override
  Future<String?> readApiKey() async => apiKey;

  @override
  Future<void> writeApiKey(String key) async => apiKey = key;

  @override
  Future<({String username, String password})?> readRememberedLogin() async {
    final u = username;
    final p = password;
    if (u == null || p == null) return null;
    return (username: u, password: p);
  }

  @override
  Future<void> writeRememberedLogin(String username, String password) async {
    this.username = username;
    this.password = password;
  }

  @override
  Future<void> clearRememberedLogin() async {
    username = null;
    password = null;
  }

  @override
  Future<void> clearAll() async {
    jwt = null;
    apiKey = null;
    username = null;
    password = null;
  }
}

/// The host every test that needs a server talks to. Shared so a Dio adapter
/// and the profile a screen reads cannot drift apart.
const fakeServerBaseUrl = 'http://s.local:8000';

/// `serverProfileProvider` answering with [profile], or with "nothing
/// configured yet" when it is null.
///
/// One factory rather than a `_FakeProfileNotifier` per test file: there were 26
/// of those. Twelve were byte-identical `build() => null`, and every one of the
/// rest but the watch's settings screen pointed at [fakeServerBaseUrl] and
/// differed only in the auth mode.
///
/// The two left with their own are the two that need one: `current_user_provider`
/// drives the profile by hand mid-test, and the watch's settings screen overrides
/// `clear()` to record that it was called.
Override serverProfileOverride([ServerProfile? profile]) =>
    serverProfileProvider.overrideWith(() => _FixedServerProfile(profile));

/// No server configured, so nothing can be fetched — what a test that only
/// renders a screen wants.
///
/// Not optional in a widget test that renders anything reading the profile:
/// building the API client without one throws `UnimplementedError`, the widget
/// becomes an unbounded `ErrorWidget`, and the 100000 px overflow that follows
/// buries whatever the test was actually about.
final noServerProfileOverride = serverProfileOverride();

/// The fake server, reached over [authMode]. The mode is not decoration: screens
/// hide admin-only routes for an API key, and the auth interceptors differ.
Override fakeServerProfileOverride({AuthMode authMode = AuthMode.none}) =>
    serverProfileOverride(
      ServerProfile(baseUrl: fakeServerBaseUrl, authMode: authMode),
    );

class _FixedServerProfile extends ServerProfileNotifier {
  _FixedServerProfile(this._profile);

  final ServerProfile? _profile;

  @override
  ServerProfile? build() => _profile;
}

/// The archive list a screen renders, with nothing behind it: every load
/// answers [archives] and no request is made.
///
/// One factory rather than a `_FakeArchiveNotifier` per test file — there were
/// five, byte-identical down to the field name.
Override archiveListOverride(List<Archive> archives) =>
    archiveProvider.overrideWith(() => _FixedArchiveList(archives));

class _FixedArchiveList extends ArchiveNotifier {
  _FixedArchiveList(this._archives);

  final List<Archive> _archives;

  @override
  Future<List<Archive>> build() async => _archives;
}

/// The watch's other side, faked: a fixed [fleet] for every poll, a log of every
/// command that went through, and optionally one [error] thrown by all of it.
///
/// One fake rather than one per test file, the same reasoning as
/// [FakeWatchConfigSync]: four of them had grown — the two screen tests each
/// recording its own third of the API in its own string format, the transport
/// test using it as a stand-in for a whole leg of [HybridWearTransport].
///
/// Every method is implemented and logged as `name` / `name:printerId`, using
/// the real method names, so a stray command shows up in [calls] instead of
/// vanishing into a `noSuchMethod` that only throws for the routes one test
/// happened to think of. Assert the whole list, not a `contains`, and that
/// property holds.
class FakeWearTransport implements WearTransport {
  FakeWearTransport({this.fleet = const WearFleet(printers: []), this.error});

  /// What every `getFleet` answers.
  final WearFleet fleet;

  /// Thrown by every call when set — the phone refusing, or out of reach.
  final Exception? error;

  /// Every call in order, oldest first — [getFleet] included, which is what the
  /// transport's own tests are about.
  final List<String> calls = [];

  /// The commands only, without the fleet polls a screen runs on mount and
  /// again after every action. This is what a screen test means by "what did
  /// the watch send", and it still shows a stray command rather than swallowing
  /// it.
  List<String> get commands => [
        for (final call in calls)
          if (call != 'getFleet') call,
      ];

  Future<T> _log<T>(String call, T value) {
    calls.add(call);
    final e = error;
    if (e != null) throw e;
    return Future.value(value);
  }

  @override
  Future<WearFleet> getFleet() => _log('getFleet', fleet);

  @override
  Future<void> pause(int printerId) => _log('pause:$printerId', null);

  @override
  Future<void> resume(int printerId) => _log('resume:$printerId', null);

  @override
  Future<void> stop(int printerId) => _log('stop:$printerId', null);

  @override
  Future<void> clearPlate(int printerId) => _log('clearPlate:$printerId', null);

  @override
  Future<void> startNext(int printerId) => _log('startNext:$printerId', null);

  @override
  Future<void> clearHmsErrors(int printerId) =>
      _log('clearHmsErrors:$printerId', null);

  @override
  Future<void> executeHmsAction(
    int printerId, {
    required String printError,
    required String action,
    String? jobId,
  }) =>
      _log(
        'executeHmsAction:$printerId:$printError:$action:${jobId ?? ''}',
        null,
      );
}
