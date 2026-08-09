import 'dart:convert';

import 'package:bambuddy_mobile/core/diagnostics/log_event.dart';
import 'package:app_report_client/app_report_client.dart';
import 'package:bambuddy_mobile/core/diagnostics/report_config.dart';
import 'package:bambuddy_mobile/core/diagnostics/log_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime.utc(2026, 7, 25, 12);
  late DateTime now;

  LogStore makeStore({
    int maxRecords = 4000,
    int maxChars = 512 * 1024,
    LogRedactor? redactor,
    void Function(String line)? onLine,
  }) =>
      LogStore(
        header: LogHeader(
          ts: start,
          session: 'test-session',
          app: '0.11.2+1102',
          flavor: 'mobile',
        ),
        redactor: redactor,
        maxRecords: maxRecords,
        maxChars: maxChars,
        clock: () => now,
        onLine: onLine,
      );

  setUp(() => now = start);

  List<Map<String, dynamic>> parse(String jsonl) => [
        for (final line in const LineSplitter().convert(jsonl))
          jsonDecode(line) as Map<String, dynamic>,
      ];

  test('exports in the order things happened, not the order they arrived', () {
    final store = makeStore();

    now = start.add(const Duration(milliseconds: 1000));
    // What a tap sets off is written first — the widget's handler runs before
    // the probe sees the finger lift — and the touch is stamped with when it
    // began.
    store.add(LogSource.ui, 'route', fields: const {'to': '/queue'});
    store.add(LogSource.ui, 'tap', at: 940, fields: const {'id': 'nav.queue'});

    final records = parse(store.export()).skip(1).toList();
    expect(records.map((r) => r['evt']), ['tap', 'route']);
    expect(records.map((r) => r['t']), [940, 1000]);
  });

  test('records sharing a millisecond keep the order they arrived in', () {
    final store = makeStore();

    store.add(LogSource.ui, 'tap');
    store.add(LogSource.ui, 'route');
    store.add(LogSource.http, 'request');

    final records = parse(store.export()).skip(1).toList();
    expect(records.map((r) => r['evt']), ['tap', 'route', 'request']);
  });

  test('export starts with the header, then the records in order', () {
    final store = makeStore();

    store.add(LogSource.ui, 'route', fields: const {'to': '/dashboard'});
    now = start.add(const Duration(milliseconds: 1843));
    store.add(LogSource.http, 'response',
        lvl: LogLevel.warn, fields: const {'status': 502});

    final lines = parse(store.export());

    expect(lines, hasLength(3));
    expect(lines.first['session'], 'test-session');
    expect(lines[1], containsPair('evt', 'route'));
    expect(lines[1], containsPair('t', 0));
    expect(lines[2], containsPair('t', 1843));
    expect(lines[2], containsPair('status', 502));
  });

  test('t is measured from the header timestamp', () {
    final store = makeStore();

    now = start.add(const Duration(seconds: 90));
    store.add(LogSource.app, 'user_marker');

    expect(parse(store.export())[1]['t'], 90000);
  });

  test('a clock jump backwards cannot produce negative offsets', () {
    final store = makeStore();

    now = start.subtract(const Duration(minutes: 5));
    store.add(LogSource.app, 'tick');

    expect(parse(store.export())[1]['t'], 0);
  });

  test('drops the oldest records past the record cap', () {
    final store = makeStore(maxRecords: 3);

    for (var i = 0; i < 6; i++) {
      now = start.add(Duration(milliseconds: i));
      store.add(LogSource.app, 'tick', fields: {'i': i});
    }

    final lines = parse(store.export());
    // header + truncation marker + 3 survivors
    expect(lines, hasLength(5));
    expect(store.recordCount, 3);
    expect(store.droppedCount, 3);
    expect([for (final l in lines.skip(2)) l['i']], [3, 4, 5]);
  });

  test('drops past the size cap as well', () {
    final store = makeStore(maxChars: 200);

    for (var i = 0; i < 40; i++) {
      store.add(LogSource.app, 'tick', fields: {'payload': 'x' * 20});
    }

    expect(store.approximateChars, lessThanOrEqualTo(200));
    expect(store.droppedCount, greaterThan(0));
  });

  test('the truncation marker points at where the gap is', () {
    final store = makeStore(maxRecords: 2);

    for (var i = 0; i < 5; i++) {
      now = start.add(Duration(milliseconds: i * 100));
      store.add(LogSource.app, 'tick', fields: {'i': i});
    }

    final marker = parse(store.export())[1];
    expect(marker['evt'], 'truncated');
    expect(marker['dropped'], 3);
    expect(marker['lvl'], 'warn');
    // Last dropped record was i=2 at t=200 — the gap ends there.
    expect(marker['t'], 200);
  });

  test('no marker when nothing was dropped', () {
    final store = makeStore();

    store.add(LogSource.app, 'tick');

    expect(store.export(), isNot(contains('truncated')));
  });

  test('an oversized single record is kept rather than looping forever', () {
    final store = makeStore(maxChars: 10);

    store.add(LogSource.err, 'uncaught', fields: {'msg': 'y' * 500});

    expect(store.recordCount, 1);
  });

  test('records are redacted on the way in', () {
    final redactor = bambuddyRedactor()..remember('my-secret-key', '[APIKEY]');
    final store = makeStore(redactor: redactor);

    store.add(LogSource.http, 'error', fields: const {
      'msg': 'rejected my-secret-key from 192.168.1.9',
      'token': 'raw-token',
    });

    final record = parse(store.export())[1];
    expect(record['msg'], 'rejected [APIKEY] from [IP]');
    expect(record['token'], '[REDACTED]');
  });

  test('onLine receives every encoded record for the durable sink', () {
    final mirrored = <String>[];
    final store = makeStore(onLine: mirrored.add);

    store.add(LogSource.fgs, 'cycle');
    store.add(LogSource.fgs, 'alert_suppressed');

    expect(mirrored, hasLength(2));
    expect(mirrored.first, contains('"evt":"cycle"'));
  });

  test('mark records a user marker', () {
    final store = makeStore();

    store.mark();

    final record = parse(store.export())[1];
    expect(record['src'], 'app');
    expect(record['evt'], 'user_marker');
  });

  test('a session ends itself at the size ceiling and says which one', () {
    // The other ceiling. It is also what catches a clock that stopped moving:
    // `_openMs` would stay at zero and the duration check would never fire.
    final closed = <String>[];
    final store = LogStore(
      header: LogHeader(
        ts: start,
        session: 'test-session',
        app: '0.11.3+1103',
        flavor: 'mobile',
      ),
      // Small ring on purpose: the byte count is about everything ever written,
      // not about what the ring still holds, so eviction must not buy more room.
      maxRecords: 2,
      maxBytes: 400,
      clock: () => now,
      onClosed: closed.add,
    );

    for (var i = 0; i < 40; i++) {
      store.add(LogSource.ws, 'frame', fields: {'n': i});
    }

    final records = parse(store.export()).skip(1).toList();
    expect(store.isClosed, isTrue);
    expect(records.last['evt'], 'limit_reached');
    expect(records.last['limit'], 'size');
    expect(records.last['mb'], 0); // 400 B rounds to zero whole megabytes
    expect(closed, ['size']); // once, and named
  });

  test('a session ends itself at the time ceiling', () {
    // The ring buffer bounds memory; only the ceiling bounds the file, which
    // gets every line and never gives one back.
    final mirrored = <String>[];
    final store = makeStore(onLine: mirrored.add);

    store.add(LogSource.ui, 'tap');
    now = start.add(recordingLimit).add(const Duration(seconds: 1));
    store.add(LogSource.ui, 'tap');
    store.add(LogSource.ui, 'tap');
    store.add(LogSource.app, 'recording_stopped');

    final records = parse(store.export()).skip(1).toList();
    expect(store.isClosed, isTrue);
    // One tap, then the line that says why there are no more.
    expect(records.map((r) => r['evt']), ['tap', 'limit_reached']);
    expect(records.last['lvl'], 'warn');
    expect(records.last['limit'], 'time');
    expect(records.last['minutes'], recordingLimit.inMinutes);
    // And the mirror on disk stopped growing with it.
    expect(mirrored, hasLength(2));
  });

  test('a store handed the session start inherits its deadline', () {
    // The foreground service is restarted by Android, so one recording can be
    // several stores. Without this each fresh store would begin the five minutes
    // again and a crash-looping service could record for an hour.
    now = start.add(recordingLimit - const Duration(seconds: 30));
    final store = LogStore(
      header: LogHeader(
        ts: start,
        session: 'test-session',
        app: '0.11.2+1102',
        flavor: 'mobile',
        stream: LogStream.fgs,
      ),
      clock: () => now,
      openedAt: start,
    );

    store.add(LogSource.fgs, 'start');
    now = start.add(recordingLimit).add(const Duration(seconds: 1));
    store.add(LogSource.ws, 'frame');

    final records = parse(store.export()).skip(1).toList();
    expect(records.map((r) => r['evt']), ['start', 'limit_reached']);
    // The limit reported is the session's, not what was left of it.
    expect(records.last['minutes'], recordingLimit.inMinutes);
  });

  test('clear resets records and the drop counter', () {
    final store = makeStore(maxRecords: 1);

    store
      ..add(LogSource.app, 'a')
      ..add(LogSource.app, 'b')
      ..clear();

    expect(store.recordCount, 0);
    expect(store.droppedCount, 0);
    expect(parse(store.export()), hasLength(1));
  });
}
