import 'dart:convert';

import 'package:bambuddy_mobile/core/diagnostics/log_event.dart';
import 'package:bambuddy_mobile/core/diagnostics/report_envelope.dart';
import 'package:flutter_test/flutter_test.dart';

/// A log the way a recording actually produces one: header line, then records.
String logWith(Map<String, Object?> header, {int records = 1}) => [
      jsonEncode(header),
      for (var i = 0; i < records; i++)
        jsonEncode({'t': i, 'src': 'app', 'lvl': 'info'}),
      '',
    ].join('\n');

void main() {
  group('header', () {
    test('is taken from the log line, not from anything alongside it', () {
      final envelope = reportEnvelope(
        logWith({
          'v': 1,
          'ts': '2026-07-31T10:00:00.000Z',
          'session': 'abc',
          'stream': 'ui',
          'app': '0.11.7+11700',
          'flavor': 'mobile',
          'os': 'Android 15',
          'scheme': 'https',
          'host_kind': 'name',
          'port': 443,
          'auth': 'apiKey',
        }),
      );

      expect(envelope.header['app'], '0.11.7+11700');
      expect(envelope.header['os'], 'Android 15');
      // The fingerprint is spread flat by LogHeader.toJson, so it arrives as
      // scalars the relay accepts rather than as a nested object it refuses.
      expect(envelope.header['scheme'], 'https');
      expect(envelope.header['port'], 443);
    });

    test('is empty when the log starts with a record instead of a header', () {
      // A header write may fail silently while the writes after it succeed.
      // Reading that first record as a session header would put one event's
      // fields in the issue as though they described the whole recording.
      final envelope = reportEnvelope('{"t":0,"src":"app","lvl":"info"}\n');
      expect(envelope.header, isEmpty);
      expect(envelope.logSchema, reportLogSchema);
    });

    test('is empty for an unreadable or missing first line', () {
      expect(reportEnvelope('').header, isEmpty);
      expect(reportEnvelope('not json at all\n').header, isEmpty);
      expect(reportEnvelope('[1,2,3]\n').header, isEmpty);
    });

    test('passes through what the relay would refuse, rather than repairing it', () {
      // The relay validates the header and is the authority on it. Reshaping it
      // here would mean the client quietly fixing headers the app should not be
      // producing — a bug that then never surfaces.
      final envelope = reportEnvelope(
        logWith({
          'app': '0.11.7',
          'nested': {'no': 'objects'},
          'Bad-Key': 'dashes are not allowed',
          'long': 'x' * 400,
          'multiline': '1.2.5\nauth: none',
        }),
      );

      expect(envelope.header['nested'], {'no': 'objects'});
      expect(envelope.header['Bad-Key'], 'dashes are not allowed');
      expect((envelope.header['long']! as String).length, 400);
      expect(envelope.header['multiline'], contains('\n'));
    });

    test('drops nulls, which the map cannot hold anyway', () {
      final envelope = reportEnvelope(
        logWith({'app': '0.11.7', 'device': null}),
      );

      expect(envelope.header.keys, ['app']);
    });
  });

  group('schema', () {
    test('matches the version the log itself carries', () {
      expect(reportEnvelope(logWith({'v': 1, 'app': '0.11.7'})).logSchema, 1);
    });

    test('reports an older recording under its own version, not this build', () {
      // A recording made before an update follows the schema it was written
      // with; whether that one is still accepted is the relay's decision.
      final envelope = reportEnvelope(logWith({'v': 7, 'app': '0.9.0'}));
      expect(envelope.logSchema, 7);
    });

    test('falls back to this build when the header does not say', () {
      expect(reportEnvelope(logWith({'app': '0.11.7'})).logSchema,
          reportLogSchema);
      expect(reportEnvelope(logWith({'v': 0})).logSchema, reportLogSchema);
      expect(reportEnvelope(logWith({'v': 'one'})).logSchema, reportLogSchema);
    });

    test('is the version the log is written with', () {
      // The number sent and the number in the log are the same constant. If this
      // fails, the relay is being told a schema the log does not follow.
      expect(reportLogSchema, LogHeader.formatVersion);
    });
  });

  test('a real header survives the round trip unchanged', () {
    final header = LogHeader(
      ts: DateTime.utc(2026, 7, 31, 10),
      session: 'a' * 32,
      app: '0.11.7+11700',
      flavor: 'mobile',
      os: 'Android 15 (SDK 35), build TQ3A.230805.001',
      locale: 'pl_PL',
      server: '0.2.5b3',
      serverUrl: const ServerFingerprint(
        scheme: 'https',
        hostKind: HostKind.name,
        port: 443,
      ),
      auth: 'apiKey',
    );

    final envelope = reportEnvelope('${header.toJsonLine()}\n');

    expect(envelope.logSchema, LogHeader.formatVersion);
    // Nothing the app puts in a header is dropped: every field is already a
    // short scalar under a key the relay accepts.
    expect(
      envelope.header.keys.toSet(),
      header.toJson().keys.toSet(),
    );
  });
}
