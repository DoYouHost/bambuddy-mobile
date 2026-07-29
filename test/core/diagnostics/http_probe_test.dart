import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bambuddy_mobile/core/api/api_client.dart';
import 'package:bambuddy_mobile/core/diagnostics/diagnostic_recorder.dart';
import 'package:bambuddy_mobile/core/diagnostics/session_facts.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers every request with whatever the test hands it: a [ResponseBody] to
/// reply, a [DioException] to fail. Failing from the adapter is the only honest
/// way to get a `connectionError` — the real one never reaches a status.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.reply);

  final Object Function(RequestOptions options) reply;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final answer = reply(options);
    if (answer is DioException) throw answer;
    return answer as ResponseBody;
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _text(String body, int status) => ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: ['text/plain'],
      },
    );

/// A body dio actually decodes — the count only exists for parsed JSON.
ResponseBody _json(String body) => ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const host = 's.local';
  const baseUrl = 'http://$host:8000';

  late DiagnosticRecorder recorder;

  Future<void> useRecorder({Map<String, String> secrets = const {}}) async {
    SharedPreferences.setMockInitialValues({});
    recorder = DiagnosticRecorder(
      settings: SettingsRepository(await SharedPreferences.getInstance()),
      loadFacts: () async => SessionFacts(
        app: '0.11.2+1102',
        flavor: 'mobile',
        secrets: secrets,
      ),
      resolveDirectory: () async => null,
    );
    addTearDown(recorder.discard);
  }

  Dio dioAnswering(Object Function(RequestOptions options) reply) =>
      createBareDio()
        ..options.baseUrl = baseUrl
        ..httpClientAdapter = _ScriptedAdapter(reply);

  Future<List<Map<String, dynamic>>> stopAndParse() async {
    final jsonl = await recorder.stop();
    return [
      for (final line in const LineSplitter().convert(jsonl))
        jsonDecode(line) as Map<String, dynamic>,
    ];
  }

  Future<List<Map<String, dynamic>>> httpRecords() async =>
      (await stopAndParse()).where((r) => r['src'] == 'http').toList();

  setUp(useRecorder);

  test('logs one line per call, with method, path, status and duration',
      () async {
    final dio = dioAnswering((_) => _text('[]', 200));
    await recorder.start();

    await dio.get<dynamic>('/api/v1/printers');

    final records = await httpRecords();
    expect(records, hasLength(1));
    expect(records.single['evt'], 'response');
    expect(records.single['method'], 'GET');
    expect(records.single['path'], '/api/v1/printers');
    expect(records.single['status'], 200);
    expect(records.single['ms'], isA<int>());
    // info is the default level and is left out of the encoded record.
    expect(records.single.containsKey('lvl'), isFalse);
  });

  test('keeps the query string out of the log', () async {
    // Where the camera and thumbnail tokens live. The path is logged, the query
    // is dropped before redaction ever has to catch it.
    final dio = dioAnswering((_) => _text('img', 200));
    await recorder.start();

    await dio.get<dynamic>('/api/v1/archives/5/thumbnail?token=s3cr3t-token');

    final records = await httpRecords();
    expect(records.single['path'], '/api/v1/archives/5/thumbnail');
    expect(jsonEncode(records.single), isNot(contains('s3cr3t')));
  });

  test('counts the records a list endpoint answered with', () async {
    // "The queue is empty" versus "the queue came back full and the app showed
    // none of it" is the same 200 without this count.
    final dio = dioAnswering(
      (_) => _json('[{"id":1},{"id":2},{"id":3}]'),
    );
    await recorder.start();

    await dio.get<dynamic>('/api/v1/queue/');

    expect((await httpRecords()).single['n'], 3);
  });

  test('a read that answered 200 with nothing says so', () async {
    // dio gives a null body for an empty response that claims JSON, and the
    // data layer turns that into an empty list — the quiet way a dropped answer
    // reads as "nothing here". `n:0` (a real empty array) must not look the same.
    final dio = dioAnswering((_) => _json(''));
    await recorder.start();

    await dio.get<dynamic>('/api/v1/queue/');

    final record = (await httpRecords()).single;
    expect(record['empty'], isTrue);
    expect(record.containsKey('n'), isFalse);
  });

  test('a write with no body is not reported as empty', () async {
    // The normal answer to a save; flagging it would bury the reads that matter.
    final dio = dioAnswering((_) => _json(''));
    await recorder.start();

    await dio.post<dynamic>('/api/v1/queue/5/start');

    final response = (await httpRecords()).last;
    expect(response['evt'], 'response');
    expect(response.containsKey('empty'), isFalse);
  });

  test('an object body has no count to report', () async {
    final dio = dioAnswering((_) => _json('{"state":"RUNNING"}'));
    await recorder.start();

    await dio.get<dynamic>('/api/v1/printers/3/status');

    expect((await httpRecords()).single.containsKey('n'), isFalse);
  });

  group('one record of the answer', () {
    String queueItem({String status = 'pending', int id = 1}) =>
        '{"id":$id,"position":1,"status":"$status","printer_name":"X2D"}';

    test('a list contributes its first record whole, plus the count', () async {
      // The whole point: `n:2` with a `completed` first record is a different
      // bug from `n:2` with a `pending` one, and the same 200 either way.
      final dio = dioAnswering(
        (_) => _json('[${queueItem(status: 'completed')},${queueItem(id: 2)}]'),
      );
      await recorder.start();

      await dio.get<dynamic>('/api/v1/queue/');

      final record = (await httpRecords()).single;
      expect(record['n'], 2);
      expect(record['first'], isA<Map<String, dynamic>>());
      expect((record['first'] as Map)['status'], 'completed');
      expect((record['first'] as Map)['id'], 1);
    });

    test('an object answer is the record', () async {
      final dio = dioAnswering((_) => _json('{"id":3,"state":"RUNNING"}'));
      await recorder.start();

      await dio.get<dynamic>('/api/v1/printers/3/status');

      final record = (await httpRecords()).single;
      expect((record['first'] as Map)['state'], 'RUNNING');
      expect(record.containsKey('n'), isFalse);
    });

    test('an unchanged answer says so instead of repeating itself', () async {
      final dio = dioAnswering((_) => _json('[${queueItem()}]'));
      await recorder.start();

      await dio.get<dynamic>('/api/v1/queue/');
      await dio.get<dynamic>('/api/v1/queue/');
      await dio.get<dynamic>('/api/v1/queue/');

      final records = await httpRecords();
      expect(records.first.containsKey('first'), isTrue);
      expect(records.skip(1).map((r) => r['same']), [true, true]);
      expect(records.skip(1).any((r) => r.containsKey('first')), isFalse);
      // The count still comes with every answer — `same` is about the record.
      expect(records.map((r) => r['n']), [1, 1, 1]);
    });

    test('a changed record is logged again', () async {
      var status = 'pending';
      final dio = dioAnswering((_) => _json('[${queueItem(status: status)}]'));
      await recorder.start();

      await dio.get<dynamic>('/api/v1/queue/');
      status = 'printing';
      await dio.get<dynamic>('/api/v1/queue/');

      final records = await httpRecords();
      expect((records.first['first'] as Map)['status'], 'pending');
      expect((records.last['first'] as Map)['status'], 'printing');
    });

    test('two answers behind one path dedupe against themselves', () async {
      // `/queue/?status=pending` and `?status=printing` share a path, and the
      // query is deliberately absent from the log. Deduping them together would
      // hide every second answer behind a `same` that is not true.
      final dio = dioAnswering((options) => _json(
            options.uri.query.contains('printing')
                ? '[${queueItem(status: 'printing', id: 9)}]'
                : '[${queueItem()}]',
          ));
      await recorder.start();

      for (var i = 0; i < 2; i++) {
        await dio.get<dynamic>('/api/v1/queue/',
            queryParameters: {'status': 'pending'});
        await dio.get<dynamic>('/api/v1/queue/',
            queryParameters: {'status': 'printing'});
      }

      final records = await httpRecords();
      expect(records.take(2).every((r) => r.containsKey('first')), isTrue,
          reason: 'each query is new the first time it is asked');
      expect(records.skip(2).map((r) => r['same']), [true, true]);
    });

    test('a peripheral endpoint contributes no record', () async {
      // Not on the allowlist: nothing here should ever carry a token into a log.
      final dio = dioAnswering((_) => _json('{"access_token":"secret-abc"}'));
      await recorder.start();

      await dio.get<dynamic>('/api/v1/users/me');

      final record = (await httpRecords()).single;
      expect(record.containsKey('first'), isFalse);
      expect(jsonEncode(record), isNot(contains('secret-abc')));
    });

    test('a record too big for the log goes in as clipped text', () async {
      // A library entry can carry an inline thumbnail; an image does not belong
      // in a bug report.
      final dio = dioAnswering(
        (_) => _json('[{"id":1,"thumb":"${'A' * 4000}"}]'),
      );
      await recorder.start();

      await dio.get<dynamic>('/api/v1/library/files');

      final first = (await httpRecords()).single['first'];
      expect(first, isA<String>());
      expect((first as String).length, lessThan(2100));
      expect(first, endsWith('…'));
    });

    test('a downloaded image is neither counted nor sampled', () async {
      // Bytes: its length is a byte count, and `n:34000` would read as records.
      final dio = dioAnswering((_) => ResponseBody.fromBytes(
            Uint8List.fromList(List.filled(1000, 65)),
            200,
            headers: {
              Headers.contentTypeHeader: ['image/png'],
            },
          ));
      await recorder.start();

      await dio.get<List<int>>(
        '/api/v1/archives/5/thumbnail',
        options: Options(responseType: ResponseType.bytes),
      );

      final record = (await httpRecords()).single;
      expect(record.containsKey('n'), isFalse);
      expect(record.containsKey('first'), isFalse);
    });

    test('a token inside a sampled body is redacted', () async {
      // The allowlist keeps token endpoints out, but a body is server-shaped and
      // the redactor is what makes that safe rather than lucky.
      final dio = dioAnswering((_) => _json(
            '[{"id":1,"nested":{"access_token":"tok-123","key":"bb_realkey12"}}]',
          ));
      await recorder.start();

      await dio.get<dynamic>('/api/v1/queue/');

      final encoded = jsonEncode((await httpRecords()).single);
      expect(encoded, isNot(contains('tok-123')));
      expect(encoded, isNot(contains('bb_realkey12')));
      expect(encoded, contains('[REDACTED]'));
    });

    test('a new recording does not inherit the previous one\'s fingerprints',
        () async {
      final dio = dioAnswering((_) => _json('[${queueItem()}]'));
      await recorder.start();
      await dio.get<dynamic>('/api/v1/queue/');
      await stopAndParse();

      await useRecorder();
      await recorder.start();
      await dio.get<dynamic>('/api/v1/queue/');

      expect((await httpRecords()).single.containsKey('first'), isTrue,
          reason: 'a session that starts with `same` starts with nothing');
    });
  });

  test('announces a write before its answer', () async {
    // The only witness that a save left the phone when the answer never comes.
    final dio = dioAnswering((_) => _text('{}', 200));
    await recorder.start();

    await dio.post<dynamic>('/api/v1/queue', data: {'file': 'x'});

    final records = await httpRecords();
    expect(records.map((r) => r['evt']), ['request', 'response']);
    expect(records.first['method'], 'POST');
    expect(records.first['path'], '/api/v1/queue');
    expect(records.first['lvl'], 'debug');
    // The request line says nothing about what was sent.
    expect(jsonEncode(records.first), isNot(contains('file')));
  });

  test('does not announce a read', () async {
    // The dashboard polls; doubling every poll would burn the buffer.
    final dio = dioAnswering((_) => _text('{}', 200));
    await recorder.start();

    await dio.get<dynamic>('/api/v1/printers/3/status');

    expect((await httpRecords()).map((r) => r['evt']), ['response']);
  });

  test("records the server's error body, clipped", () async {
    final dio = dioAnswering((_) => _text('detail: ${'x' * 500}', 502));
    await recorder.start();

    await expectLater(
      dio.get<dynamic>('/api/v1/printers/3/status'),
      throwsA(isA<DioException>()),
    );

    final error = (await httpRecords()).single;
    expect(error['evt'], 'error');
    expect(error['status'], 502);
    expect(error['type'], 'badResponse');
    // The server answered, so this is its problem to explain, not a failure of
    // the app's own.
    expect(error['lvl'], 'warn');
    expect(error['body'], startsWith('detail: xxx'));
    expect((error['body'] as String).length, lessThan(320));
    expect(error['body'], endsWith('…'));
  });

  test('reports the size of a failed download instead of its bytes', () async {
    final dio = dioAnswering((_) => _text('not an image', 404));
    await recorder.start();

    await expectLater(
      dio.get<dynamic>(
        '/api/v1/archives/5/cover',
        options: Options(responseType: ResponseType.bytes),
      ),
      throwsA(isA<DioException>()),
    );

    expect((await httpRecords()).single['body'], '<12 bytes>');
  });

  test('says what broke when there is no response', () async {
    // Built the way dio builds it for a dead server, boilerplate and all.
    final dio = dioAnswering(
      (options) => DioException.connectionError(
        requestOptions: options,
        reason: "Failed host lookup: '$host'",
        error: SocketException(
          "Failed host lookup: '$host'",
          osError: const OSError('No address associated with hostname', 7),
        ),
      ),
    );
    await recorder.start();

    await expectLater(
      dio.get<dynamic>('/api/v1/printers'),
      throwsA(isA<DioException>()),
    );

    final error = (await httpRecords()).single;
    expect(error['type'], 'connectionError');
    expect(error['cause'], 'SocketException');
    // The OS error and errno, which dio drops when it reformats the message.
    expect(error['msg'], startsWith('Failed host lookup'));
    expect(error['msg'], contains('errno = 7'));
    // Neither the class (it is the `cause`) nor dio's closing sentence.
    expect(error['msg'], isNot(contains('SocketException')));
    expect(error['msg'], isNot(contains('cannot be solved')));
    // Nothing came back, so the app owns the failure.
    expect(error['lvl'], 'error');
    expect(error.containsKey('status'), isFalse);
    expect(error.containsKey('body'), isFalse);
  });

  test('masks the server host inside a failure message', () async {
    // "Failed host lookup: 'printer.lan'" is a socket message, not a URL, so it
    // only stays out of a public issue because the host is a known secret.
    await useRecorder(secrets: {host: '[HOST]'});
    // No underlying exception this time, so the record falls back to dio's own
    // message — the one carrying the sentence that has to go.
    final dio = dioAnswering(
      (options) => DioException.connectionError(
        requestOptions: options,
        reason: "Failed host lookup: '$host'",
      ),
    );
    await recorder.start();

    await expectLater(
      dio.get<dynamic>('/api/v1/printers'),
      throwsA(isA<DioException>()),
    );

    final error = (await httpRecords()).single;
    expect(error['msg'], contains('[HOST]'));
    expect(error['msg'], isNot(contains(host)));
    expect(error['msg'], isNot(contains('cannot be solved')));
    expect(error['msg'], endsWith("'[HOST]'"));
  });

  test('a cancelled request is not a failure', () async {
    // A screen closed while it was still loading.
    final dio = dioAnswering(
      (options) => DioException.requestCancelled(
        requestOptions: options,
        reason: 'closed',
      ),
    );
    await recorder.start();

    await expectLater(
      dio.get<dynamic>('/api/v1/printers'),
      throwsA(isA<DioException>()),
    );

    final error = (await httpRecords()).single;
    expect(error['type'], 'cancel');
    expect(error.containsKey('lvl'), isFalse);
  });

  test('logs nothing while no recording runs', () async {
    final dio = dioAnswering((_) => _text('[]', 200));

    await dio.get<dynamic>('/api/v1/printers');
    await recorder.start();

    expect(await httpRecords(), isEmpty);
  });
}
