import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bambuddy_mobile/core/diagnostics/relay_client.dart';
import 'package:bambuddy_mobile/core/diagnostics/relay_pow.dart';
import 'package:bambuddy_mobile/core/diagnostics/report_envelope.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captures the request instead of making one. The relay validates the envelope
/// key by key and answers a bad one with a flat rejection, so what this suite is
/// really about is the body: a mistake here reaches the user as "the relay
/// rejected this report" and says nothing about which field was wrong.
class _CapturingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      '{"url":"https://github.example/issues/1"}',
      201,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

RelayTicket _ticket() {
  final now = DateTime.now();
  return RelayTicket(
    ticket: 'signed',
    notBefore: now,
    expiresAt: now.add(const Duration(minutes: 30)),
    challenge: const PowChallenge(seed: 'seed', bits: 0),
    powNonce: '0',
  );
}

void main() {
  late _CapturingAdapter adapter;
  late RelayClient client;

  setUp(() {
    adapter = _CapturingAdapter();
    client = RelayClient(Dio()..httpClientAdapter = adapter);
  });

  Map<String, Object?> sentBody() =>
      (adapter.requests.single.data! as Map).cast<String, Object?>();

  Future<void> send({
    required ReportKind kind,
    String? log,
    int? logSchema,
  }) =>
      client.send(
        installId: '11111111-1111-4111-8111-111111111111',
        ticket: _ticket(),
        kind: kind,
        description: 'something',
        header: const {'app': '0.11.7+1107000'},
        logSchema: logSchema,
        log: log,
      );

  test('the app names itself in the path, not just in the payload', () {
    // One relay serves several applications and decides which repository a
    // report reaches from this prefix. A trailing slash would break both paths.
    expect(relayBaseUrl, 'https://app-relay.morganmlg.com/bambuddy');
    expect(relayBaseUrl, isNot(endsWith('/')));
  });

  test('both endpoints hang off that one base', () async {
    await send(kind: ReportKind.bug, log: 'line\n', logSchema: 1);
    expect(adapter.requests.single.uri.toString(), '$relayBaseUrl/report');
  });

  test('a bug report carries the log, gzipped and base64', () async {
    await send(kind: ReportKind.bug, log: 'line\n', logSchema: 1);

    final body = sentBody();
    expect(body['kind'], 'bug');
    expect(body['logSchema'], 1);
    // The relay never decompresses — it forwards these bytes to GitHub — so all
    // it can check cheaply is that they begin like a gzip member.
    final logGz = body['logGz']! as String;
    expect(logGz, startsWith('H4sI'));
    expect(utf8.decode(gzip.decode(base64Decode(logGz))), 'line\n');
  });

  test('a request omits the log fields rather than sending them empty',
      () async {
    await send(kind: ReportKind.feature);

    final body = sentBody();
    expect(body['kind'], 'feature');
    // Absent, not null and not empty. The relay refuses a kind that carries no
    // log but sends the keys anyway — "this kind carries no log" — so a null
    // here would be rejected outright.
    expect(body.keys, isNot(contains('logGz')));
    expect(body.keys, isNot(contains('logSchema')));
  });

  test('a change is its own kind, not a feature', () async {
    await send(kind: ReportKind.change);
    expect(sentBody()['kind'], 'change');
  });

  test('the ticket and its solved proof of work travel with every kind',
      () async {
    await send(kind: ReportKind.change);

    final body = sentBody();
    expect(body['ticket'], 'signed');
    // Solved while the user was writing; a second of hashing on the send tap
    // would read as the app having hung.
    expect(body['powNonce'], '0');
  });
}
