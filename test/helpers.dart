import 'dart:convert';
import 'dart:io';

import 'package:bambuddy_mobile/core/auth/credentials_store.dart';
import 'package:bambuddy_mobile/features/dashboard/firmware_providers.dart';
import 'package:bambuddy_mobile/features/maintenance/maintenance_providers.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

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
