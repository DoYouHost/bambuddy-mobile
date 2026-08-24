import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bambuddy_mobile/core/auth/credentials_store.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/watch/watch_config_sync.dart';
import 'package:bambuddy_mobile/features/dashboard/firmware_providers.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/ams_history_sheet.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/heater_history_sheet.dart';
import 'package:bambuddy_mobile/features/maintenance/maintenance_providers.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/wear/wear_transport.dart';
import 'package:flutter/material.dart';
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
}) async {
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
      return wrapInApp ? plApp(child) : child;
    }),
  ));
  await tester.pumpAndSettle();
  return container;
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
