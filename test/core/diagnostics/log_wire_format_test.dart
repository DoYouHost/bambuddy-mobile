import 'dart:convert';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:bambuddy_mobile/core/diagnostics/session_facts.dart';

import '../../helpers.dart';

/// What a bambuddy log looks like on the wire, pinned.
///
/// Moving the recorder into `app_diagnostics` moved `flavor` and `auth` out of
/// `LogHeader`'s declared fields and into `SessionFacts.extra`. That is an
/// internal change and must stay one: the relay accepts a fixed window of
/// schemas, and every log already attached to a GitHub issue was written by a
/// build that spelled these keys exactly this way. A reader that stopped
/// finding `flavor` would not fail — it would quietly report every session as
/// coming from the phone.
///
/// So this test is about *keys and values*, not about the class that produces
/// them. Key **order** is not pinned and did change: nothing reads a JSON
/// object positionally, and `LogSummary` and the relay both decode first.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'bambuddy',
      packageName: 'pl.bambuddy.mobile',
      version: '0.14.0',
      buildNumber: '2028000',
      buildSignature: '',
    );
  });

  test('the header carries exactly the keys it always carried', () async {
    final facts = await loadSessionFacts(
      profile: const ServerProfile(
        baseUrl: 'https://bambuddy.local:8443',
        authMode: AuthMode.apiKey,
      ),
      credentials: InMemoryCredentialsStore(),
      readServerVersion: () async => '1.2.5.3',
    );

    final json =
        jsonDecode(
              facts
                  .toHeader(ts: DateTime.utc(2026, 9, 9), session: 'abc')
                  .toJsonLine(),
            )
            as Map<String, dynamic>;

    expect(json.keys.toSet(), {
      'v',
      'ts',
      'session',
      'stream',
      'app',
      'os',
      'locale',
      'server',
      'scheme',
      'host_kind',
      'port',
      // The two that moved into `extra`, still flat and still spelled the same.
      'flavor',
      'auth',
    });
    expect(json['v'], 1, reason: 'a bump has to be registered on the relay');
    expect(json['app'], '0.14.0+2028000');
    expect(json['flavor'], 'mobile');
    // `AuthMode.name` verbatim, camel case included.
    expect(json['auth'], 'apiKey');
    expect(json['scheme'], 'https');
    expect(json['host_kind'], 'name');
    expect(json['port'], 8443);
    expect(json['server'], '1.2.5.3');
    // The user's host is what the fingerprint exists to avoid carrying.
    expect(
      facts.toHeader(ts: DateTime.utc(2026), session: 'a').toJsonLine(),
      isNot(contains('bambuddy.local')),
    );
  });

  test('a record still spreads its fields flat beside t/src/evt', () async {
    final recorder = testRecorder();
    addTearDown(recorder.discard);
    await recorder.start();
    DiagnosticRecorder.active?.add(
      LogSource.http,
      'response',
      fields: const {'method': 'GET', 'status': 200},
    );

    final rows = [
      for (final line in const LineSplitter().convert(await recorder.stop()))
        jsonDecode(line) as Map<String, dynamic>,
    ];
    final response = rows.firstWhere((r) => r['evt'] == 'response');

    expect(response.keys.toSet(), {'t', 'src', 'evt', 'method', 'status'});
    expect(response['src'], 'http');
    // info is the default and is omitted, which is most of the file.
    expect(response.containsKey('lvl'), isFalse);
  });

  test('the stream files keep the names already on devices', () {
    // A phone updated mid-recording has to find the file the previous build
    // wrote, so these are not free to be tidied.
    expect(LogStream.values.map((s) => s.name), contains('fgs'));
    expect(LogStream.values.map((s) => s.name), contains('action'));
  });
}
