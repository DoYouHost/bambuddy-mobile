import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bambuddy_mobile/core/auth/credentials_store.dart';
import 'package:bambuddy_mobile/core/watch/watch_config_sync.dart';
import 'package:bambuddy_mobile/features/dashboard/firmware_providers.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/ams_history_sheet.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/heater_history_sheet.dart';
import 'package:bambuddy_mobile/features/maintenance/maintenance_providers.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/wear/wear_shape.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_connectivity/watch_connectivity.dart';

/// Inertny firmware dla testów widgetów: karta drukarki czyta firmware przy
/// renderze, a testy go nie sprawdzają — zwracamy null, by nie bić po sieci
/// (inaczej fetch zostawia wiszący timer Dio i wywraca test).
final inertFirmwareOverride =
    printerFirmwareProvider.overrideWith((ref, id) => null);

/// Inertny łączny czas druku dla testów widgetów: karta drukarki czyta go z
/// przeglądu konserwacji przy renderze. Zwracamy null, by nie odpytywać sieci
/// (analogicznie do [inertFirmwareOverride]).
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

/// Owija widżet w MaterialApp z polską lokalizacją — testy asertują
/// polskie stringi, więc wymuszamy locale `pl`.
Widget plApp(Widget child) => MaterialApp(
      locale: const Locale('pl'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

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
  _useWatchFace(tester, shape, face);
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
      return wrapInApp ? plApp(WearShapeScope(child: child)) : child;
    }),
  ));
  await tester.pumpAndSettle();
  return container;
}

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
void _useWatchFace(WidgetTester tester, WearShape shape, Size face) {
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
  } else {
    await tester.ensureVisible(finder);
  }
  await tester.pumpAndSettle();
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

/// Wczytuje fixture z test/fixtures/ (ścieżka względem korzenia pakietu —
/// tak uruchamia testy `flutter test`).
dynamic readFixture(String name) => jsonDecode(readFixtureString(name));

/// Surowa zawartość fixture'a (do parserów przyjmujących tekst, np. ramki WS).
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

/// CredentialsStore w pamięci — testy rdzenia nie dotykają pluginu.
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
