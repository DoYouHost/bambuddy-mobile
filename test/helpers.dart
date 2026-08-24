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
import 'package:flutter/material.dart';
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
