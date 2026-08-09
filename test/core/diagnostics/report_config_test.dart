import 'package:app_report_client/app_report_client.dart';
import 'package:bambuddy_mobile/core/diagnostics/log_event.dart';
import 'package:bambuddy_mobile/core/diagnostics/report_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// What `app_report_client` refuses to assume, and bambuddy therefore has to
/// get right on its own. Every value here is required over there precisely
/// because a wrong one is silent: the report still sends, into the wrong
/// repository or under a schema the relay throws away.
void main() {
  test('the app names itself in the relay path, not just in the payload', () {
    // One relay serves several applications and decides which repository a
    // report reaches from this prefix. A trailing slash would break both paths.
    expect(relayBaseUrl, 'https://app-relay.morganmlg.com/bambuddy');
    expect(relayBaseUrl, isNot(endsWith('/')));
  });

  test('the schema sent is the schema the log is written with', () {
    // The number sent and the number in the log are the same constant. If this
    // fails, the relay is being told a schema the log does not follow — and
    // schema numbers are per application, so nothing in the package can catch
    // it.
    expect(reportLogSchema, LogHeader.formatVersion);
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

    final envelope = reportEnvelope(
      '${header.toJsonLine()}\n',
      formatVersion: reportLogSchema,
    );

    expect(envelope.logSchema, LogHeader.formatVersion);
    // Nothing the app puts in a header is dropped: every field is already a
    // short scalar under a key the relay accepts.
    expect(envelope.header.keys.toSet(), header.toJson().keys.toSet());
  });
}
