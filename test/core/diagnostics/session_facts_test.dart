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

  test('server version lands in session facts', () async {
    final f = await facts(readServerVersion: () async => '1.2.5.1');

    expect(f.server, '1.2.5.1');
    expect(f.app, '0.11.6+1106');
  });

  test('the log header carries it along', () async {
    final f = await facts(readServerVersion: () async => '0.2.4.9');
    final header = f.toHeader(ts: DateTime(2026, 7, 30), session: 'abc');

    expect(header.server, '0.2.4.9');
  });

  test('no version read: recording starts without it', () async {
    // The probe is optional — from the settings screen there is nothing yet to ask.
    final f = await facts();

    expect(f.server, isNull);
    expect(
      f.app,
      isNotEmpty,
      reason: 'the rest of the facts must still be gathered',
    );
  });

  test('a probe error does not crash the start of recording', () async {
    // The server being unreachable at the moment a report starts is a normal
    // situation — often exactly why the user is recording it.
    final f = await facts(
      readServerVersion: () async => throw Exception('no network'),
    );

    expect(f.server, isNull);
    expect(f.app, '0.11.6+1106');
    expect(
      f.serverUrl?.scheme,
      'https',
      reason: 'the rest of the facts are gathered normally',
    );
  });
}
