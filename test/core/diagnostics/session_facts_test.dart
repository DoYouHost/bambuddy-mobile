import 'package:bambuddy_mobile/core/diagnostics/session_facts.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../helpers.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'bambuddy',
      packageName: 'pl.bambuddy.mobile',
      version: '0.11.6',
      buildNumber: '1106',
      buildSignature: '',
    );
  });

  const profile = ServerProfile(
    baseUrl: 'https://bambuddy.local:8000',
    authMode: AuthMode.apiKey,
  );

  Future<SessionFacts> facts({Future<String?> Function()? readServerVersion}) =>
      loadSessionFacts(
        profile: profile,
        credentials: InMemoryCredentialsStore(),
        readServerVersion: readServerVersion,
      );

  test('wersja serwera trafia do faktów sesji', () async {
    final f = await facts(readServerVersion: () async => '1.2.5.1');

    expect(f.server, '1.2.5.1');
    expect(f.app, '0.11.6+1106');
  });

  test('nagłówek logu niesie ją dalej', () async {
    final f = await facts(readServerVersion: () async => '0.2.4.9');
    final header = f.toHeader(ts: DateTime(2026, 7, 30), session: 'abc');

    expect(header.server, '0.2.4.9');
  });

  test('brak odczytu wersji: nagrywanie startuje bez niej', () async {
    // Sonda jest opcjonalna — z ekranu ustawień nie ma jeszcze czego pytać.
    final f = await facts();

    expect(f.server, isNull);
    expect(f.app, isNotEmpty, reason: 'reszta faktów musi się zebrać');
  });

  test('błąd sondy nie przewraca startu nagrywania', () async {
    // Serwer niedostępny w chwili startu zgłoszenia to normalna sytuacja —
    // często właśnie dlatego user je nagrywa.
    final f = await facts(
      readServerVersion: () async => throw Exception('brak sieci'),
    );

    expect(f.server, isNull);
    expect(f.app, '0.11.6+1106');
    expect(
      f.serverUrl?.scheme,
      'https',
      reason: 'pozostałe fakty zebrane normalnie',
    );
  });
}
