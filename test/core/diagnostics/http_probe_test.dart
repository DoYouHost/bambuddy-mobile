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

import '../../helpers.dart';

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

/// A body dio actually decodes — the count only exists for parsed JSON, and so
/// is the error-body measuring, which is why the status is settable.
ResponseBody _json(String body, [int status = 200]) => ResponseBody.fromString(
  body,
  status,
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
      loadFacts: () async =>
          SessionFacts(app: '0.11.2+1102', flavor: 'mobile', secrets: secrets),
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

  test(
    'logs one line per call, with method, path, status and duration',
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
    },
  );

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
    final dio = dioAnswering((_) => _json('[{"id":1},{"id":2},{"id":3}]'));
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
      final dio = dioAnswering(
        (options) => _json(
          options.uri.query.contains('printing')
              ? '[${queueItem(status: 'printing', id: 9)}]'
              : '[${queueItem()}]',
        ),
      );
      await recorder.start();

      for (var i = 0; i < 2; i++) {
        await dio.get<dynamic>(
          '/api/v1/queue/',
          queryParameters: {'status': 'pending'},
        );
        await dio.get<dynamic>(
          '/api/v1/queue/',
          queryParameters: {'status': 'printing'},
        );
      }

      final records = await httpRecords();
      expect(
        records.take(2).every((r) => r.containsKey('first')),
        isTrue,
        reason: 'each query is new the first time it is asked',
      );
      expect(records.skip(2).map((r) => r['same']), [true, true]);
    });

    test('a token minted under an allowlisted prefix is never sampled', () async {
      // `/printers/camera/stream-token` sits inside `printers` and answers with
      // a camera token. A live recording logged `{"token":"[REDACTED]"}` — the
      // redactor caught it, and leaning on that is what the allowlist exists to
      // avoid.
      final dio = dioAnswering((_) => _json('{"token":"cam-tok-abc"}'));
      await recorder.start();

      await dio.post<dynamic>('/api/v1/printers/camera/stream-token');

      final response = (await httpRecords()).last;
      expect(response['evt'], 'response');
      expect(response.containsKey('first'), isFalse);
      expect(jsonEncode(response), isNot(contains('cam-tok')));
    });

    test(
      'a list that grew is not "same" just because its first record held',
      () async {
        // Straight off a live log: a POST added an item, the next poll answered
        // `n:2` with the same record on top, and `same` beside it read as
        // "nothing happened".
        var items = '{"id":180,"position":1,"status":"pending"}';
        final dio = dioAnswering((_) => _json('[$items]'));
        await recorder.start();

        await dio.get<dynamic>('/api/v1/queue/');
        items =
            '{"id":180,"position":1,"status":"pending"},'
            '{"id":181,"position":2,"status":"pending"}';
        await dio.get<dynamic>('/api/v1/queue/');

        final records = await httpRecords();
        expect(records.map((r) => r['n']), [1, 2]);
        expect(records.last.containsKey('same'), isFalse);
        expect((records.last['first'] as Map)['id'], 180);
      },
    );

    test('a peripheral endpoint contributes no record', () async {
      // Not on the allowlist: nothing here should ever carry a token into a log.
      final dio = dioAnswering((_) => _json('{"access_token":"secret-abc"}'));
      await recorder.start();

      await dio.get<dynamic>('/api/v1/users/me');

      final record = (await httpRecords()).single;
      expect(record.containsKey('first'), isFalse);
      expect(jsonEncode(record), isNot(contains('secret-abc')));
    });

    test('a record that fits stays a map, however big', () async {
      // A printer status is 4.6 kB on a live server and a maintenance overview
      // 3.2 kB; both used to degrade to escaped, truncated text, which lost the
      // half of each record anybody opens the log for.
      final dio = dioAnswering((_) => _json('{"id":1,"ams":"${'A' * 5000}"}'));
      await recorder.start();

      await dio.get<dynamic>('/api/v1/printers/1/status');

      expect(
        (await httpRecords()).single['first'],
        isA<Map<String, dynamic>>(),
      );
    });

    test('an inline thumbnail is measured, not carried and not clipped', () async {
      // A library entry can carry an inline thumbnail; an image does not belong
      // in a bug report. It used to be cut by the size ceiling, which meant the
      // first two kilobytes of the image went in. The sample rule gets there
      // first now: it is not technical, so only its length survives.
      final dio = dioAnswering(
        (_) => _json('[{"id":1,"thumb":"${'A' * 8000}"}]'),
      );
      await recorder.start();

      await dio.get<dynamic>('/api/v1/library/files');

      final first = (await httpRecords()).single['first']! as Map;
      expect(first['thumb'], '<str:8000>');
      expect(jsonEncode(first), isNot(contains('AAAA')));
    });

    test('a record too big even once measured goes in as clipped text', () async {
      // The ceiling still exists, for the record that is genuinely all content
      // the log is meant to keep: hundreds of numeric telemetry fields, none of
      // which the sample rule can shorten.
      final fields = [
        for (var i = 0; i < 900; i++) '"t$i":${i / 10}',
      ].join(',');
      final dio = dioAnswering((_) => _json('[{"id":1,$fields}]'));
      await recorder.start();

      await dio.get<dynamic>('/api/v1/printers/1/status');

      final first = (await httpRecords()).single['first'];
      expect(first, isA<String>());
      // Clipped well below the redactor's own 2000-character ceiling, so the
      // clip is marked once rather than twice.
      expect((first as String).length, lessThan(2100));
      expect(first, endsWith('…'));
    });

    test(
      'a 422 says which field failed without quoting what was sent',
      () async {
        // FastAPI echoes the offending input verbatim. The whole body used to go
        // in as text, so a file named after a person rode along on every failed
        // save — the same leak as the sampled record, one layer down.
        final dio = dioAnswering(
          (_) => _json(
            '{"detail":[{"type":"string_type","loc":["body","archive_name"],'
            '"input":"Prezent_dla_Ani_v3.3mf",'
            '"msg":"Input should be a valid string"}]}',
            422,
          ),
        );
        await recorder.start();

        // The call itself still throws; the probe's record is the point.
        await expectLater(
          dio.post<dynamic>('/api/v1/queue/', data: {'x': 1}),
          throwsA(isA<DioException>()),
        );

        final body =
            (await httpRecords()).firstWhere((r) => r['evt'] == 'error')['body']
                as String;
        // Which field, and how it was wrong — the two things the body is opened
        // for.
        expect(body, contains('string_type'));
        expect(body, contains('archive_name'));
        // And nothing of what the user typed.
        expect(body, isNot(contains('Prezent')));
        expect(body, contains('<str:22>'));
      },
    );

    test(
      'a proxy\'s error page is left readable, having nothing of anybody\'s',
      () async {
        // The other reason this field exists: an HTML page names the proxy in its
        // first few tags, and measuring it would answer `<str:300>`.
        final dio = dioAnswering(
          (_) =>
              _text('<html><head><title>502 Bad Gateway</title></head>', 502),
        );
        await recorder.start();

        await expectLater(
          dio.get<dynamic>('/api/v1/queue/'),
          throwsA(isA<DioException>()),
        );

        final body =
            (await httpRecords()).firstWhere((r) => r['evt'] == 'error')['body']
                as String;
        expect(body, contains('502 Bad Gateway'));
      },
    );

    test(
      'a plug keeps the wiring that explains it, and loses the house',
      () async {
        // The selectors were named as deliberately not secret — a JSON pointer
        // like `state.power` is a field name, not an address, and it is what
        // explains a plug reporting zero watts — and the sample rule measured
        // them away regardless, because a dotted token is not a word, a number or
        // a date. Caught only by running a whole real record through.
        final dio = dioAnswering(
          (_) => _json(
            '[{"id":4,"name":"Gniazdko w garażu",'
            '"plug_type":"homeassistant","ha_entity_id":"switch.szafa_biuro",'
            '"mqtt_power_path":"data.power","mqtt_state_path":"state.power",'
            '"mqtt_power_multiplier":1.0,"rest_method":"POST"}]',
          ),
        );
        await recorder.start();

        await dio.get<dynamic>('/api/v1/smart-plugs/');

        final first = (await httpRecords()).single['first']! as Map;
        expect(first['mqtt_power_path'], 'data.power');
        expect(first['mqtt_state_path'], 'state.power');
        expect(first['plug_type'], 'homeassistant');
        expect(first['rest_method'], 'POST');
        expect(first['mqtt_power_multiplier'], 1.0);
        // And the half that names somebody's home still goes.
        expect(first['ha_entity_id'], '[REDACTED]');
        expect(first['name'], '<str:17>');
        expect(jsonEncode(first), isNot(contains('szafa_biuro')));
      },
    );

    test('a location sensor keeps the reading and loses the room', () async {
      // The same split as the plug above, on the surface that shows a drybox's
      // humidity: what a report needs is the number, the device class and
      // whether the poller reached it. What it must not carry is the name of
      // the entity or of the shelf — a Home Assistant id names somebody's home
      // as surely as a plug's does.
      final dio = dioAnswering(
        (_) => _json(
          '[{"id":4,"name":"Szafa w sypialni",'
          '"entity_id":"sensor.sypialnia_wilgotnosc","kind":"numeric",'
          '"device_class":"humidity","unit":"%","state":"47.2","value":47.2,'
          '"alerting":true,"reachable":true,"alert_above":45.0}]',
        ),
      );
      await recorder.start();

      await dio.get<dynamic>('/api/v1/location-ha-sensors/');

      final first = (await httpRecords()).single['first']! as Map;
      expect(first['device_class'], 'humidity');
      expect(first['kind'], 'numeric');
      expect(first['value'], 47.2);
      expect(first['alerting'], true);
      expect(first['reachable'], true);
      expect(first['alert_above'], 45.0);
      // And the half that names somebody's home still goes.
      expect(first['entity_id'], '[REDACTED]');
      expect(jsonEncode(first), isNot(contains('sypialnia')));
    });

    test('what the user named is measured away, not published', () async {
      // The endpoints sampled here answer with what the user called things, and
      // the log ends up on a public branch. A denylist of field names never
      // covered these — `archive_name` and `printer_name` are not secrets by
      // name and not URLs, JWTs or serials by shape — so they went in verbatim
      // while the consent screen promised they never would.
      final dio = dioAnswering(
        (_) => _json(
          '[{"id":1,"status":"printing",'
          '"archive_name":"Prezent_dla_Ani_v3.gcode.3mf",'
          '"printer_name":"Drukarka w sypialni Kasi",'
          '"printer_serial":"20P0AA000000001"}]',
        ),
      );
      await recorder.start();

      await dio.get<dynamic>('/api/v1/queue/');

      final first = (await httpRecords()).single['first']! as Map;
      expect(first['archive_name'], '<str:28>');
      expect(first['printer_name'], '<str:24>');
      expect(first['printer_serial'], '[REDACTED]');
      // The schema is what the record is read for, and it survives whole: which
      // fields came back, and the ones that are the machine's own vocabulary.
      expect(first['id'], 1);
      expect(first['status'], 'printing');
      expect(jsonEncode(first), isNot(contains('Ani')));
      expect(jsonEncode(first), isNot(contains('Kasi')));
    });

    test('a record that only restamps itself counts as unchanged', () async {
      // A smart plug rewrites `last_checked` and `updated_at` on every poll. A
      // fingerprint taken over the whole record never matches, so its 1.5 kB
      // went into a live log five times in under a minute with nothing changed.
      var tick = 0;
      final dio = dioAnswering(
        (_) => _json(
          '[{"id":1,"last_state":"OFF",'
          '"last_checked":"2026-07-29T14:53:0${tick++}.914155",'
          '"updated_at":"2026-07-29T14:53:0$tick.892861"}]',
        ),
      );
      await recorder.start();

      await dio.get<dynamic>('/api/v1/smart-plugs/');
      await dio.get<dynamic>('/api/v1/smart-plugs/');

      final records = await httpRecords();
      expect(records.first.containsKey('first'), isTrue);
      expect(records.last['same'], isTrue);
      // The record that did get logged keeps its real timestamp — the
      // substitution belongs to the comparison, not to the log.
      expect(
        (records.first['first'] as Map)['last_checked'],
        '2026-07-29T14:53:00.914155',
      );
    });

    test(
      'the timestamp shapes a live server actually sends are covered',
      () async {
        // The captured plug record, re-polled with its stamps moved on — three
        // formats in one file: with a `Z`, without one, and microseconds either
        // way. A pattern that misses any of them puts 1.5 kB in the log per poll.
        final record =
            (readFixture('captured/smart_plugs.json') as List).first
                as Map<String, dynamic>;
        var polls = 0;
        final dio = dioAnswering((_) {
          polls++;
          return _json(
            jsonEncode([
              {
                ...record,
                'last_checked': '2026-07-29T14:53:0$polls.914155',
                'updated_at': '2026-07-29T14:53:0$polls.892861',
                'created_at': '2026-05-13T21:20:37.871673Z',
              },
            ]),
          );
        });
        await recorder.start();

        await dio.get<dynamic>('/api/v1/smart-plugs/');
        await dio.get<dynamic>('/api/v1/smart-plugs/');
        await dio.get<dynamic>('/api/v1/smart-plugs/');

        final records = await httpRecords();
        expect(records.first.containsKey('first'), isTrue);
        expect(records.skip(1).map((r) => r['same']), [true, true]);
      },
      // The only test here that needs a captured payload, and `captured/` is
      // untracked (test/fixtures/README.md). The timestamp shapes it checks are
      // written out in the body above; the fixture supplies the surrounding
      // record, which is why this one waits for a local capture instead of
      // being rewritten around an invented one.
      skip: File('test/fixtures/captured/smart_plugs.json').existsSync()
          ? null
          : 'brak test/fixtures/captured — tool/capture_fixtures.sh '
                'https://twój.serwer',
    );

    test('a real change is still a change, timestamps or not', () async {
      var state = 'OFF';
      var tick = 0;
      final dio = dioAnswering(
        (_) => _json(
          '[{"id":1,"last_state":"$state",'
          '"last_checked":"2026-07-29T14:53:0${tick++}.914155"}]',
        ),
      );
      await recorder.start();

      await dio.get<dynamic>('/api/v1/smart-plugs/');
      state = 'ON';
      await dio.get<dynamic>('/api/v1/smart-plugs/');

      final records = await httpRecords();
      expect((records.first['first'] as Map)['last_state'], 'OFF');
      expect((records.last['first'] as Map)['last_state'], 'ON');
    });

    test('a downloaded image is neither counted nor sampled', () async {
      // Bytes: its length is a byte count, and `n:34000` would read as records.
      final dio = dioAnswering(
        (_) => ResponseBody.fromBytes(
          Uint8List.fromList(List.filled(1000, 65)),
          200,
          headers: {
            Headers.contentTypeHeader: ['image/png'],
          },
        ),
      );
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
      final dio = dioAnswering(
        (_) => _json(
          '[{"id":1,"nested":{"access_token":"tok-123","key":"bb_realkey12"}}]',
        ),
      );
      await recorder.start();

      await dio.get<dynamic>('/api/v1/queue/');

      final encoded = jsonEncode((await httpRecords()).single);
      expect(encoded, isNot(contains('tok-123')));
      expect(encoded, isNot(contains('bb_realkey12')));
      expect(encoded, contains('[REDACTED]'));
    });

    test(
      'a new recording does not inherit the previous one\'s fingerprints',
      () async {
        final dio = dioAnswering((_) => _json('[${queueItem()}]'));
        await recorder.start();
        await dio.get<dynamic>('/api/v1/queue/');
        await stopAndParse();

        await useRecorder();
        await recorder.start();
        await dio.get<dynamic>('/api/v1/queue/');

        expect(
          (await httpRecords()).single.containsKey('first'),
          isTrue,
          reason: 'a session that starts with `same` starts with nothing',
        );
      },
    );
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
