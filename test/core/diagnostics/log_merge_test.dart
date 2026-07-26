import 'dart:convert';

import 'package:bambuddy_mobile/core/diagnostics/log_merge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String header(String ts, {String stream = 'ui'}) => jsonEncode({
        'v': 1,
        'ts': ts,
        'session': 's1',
        'stream': stream,
        'app': '0.11.2+1102',
        'flavor': 'mobile',
      });

  String record(int t, String evt, {String src = 'ui'}) =>
      jsonEncode({'t': t, 'src': src, 'evt': evt});

  String jsonl(List<String> lines) => '${lines.join('\n')}\n';

  List<Map<String, dynamic>> parse(String out) => [
        for (final line in const LineSplitter().convert(out))
          jsonDecode(line) as Map<String, dynamic>,
      ];

  test('interleaves both streams on absolute time, not on raw offsets', () {
    // The isolate started 5 s after the UI, so its t=0 is the UI's t=5000.
    final ui = jsonl([
      header('2026-07-25T12:00:00.000Z'),
      record(1000, 'tap'),
      record(7000, 'tap'),
    ]);
    final fgs = jsonl([
      header('2026-07-25T12:00:05.000Z', stream: 'fgs'),
      record(0, 'cycle', src: 'fgs'),
      record(3000, 'alert', src: 'fgs'),
    ]);

    final merged = parse(mergeSessions(ui, fgs));

    expect(
      [for (final r in merged.skip(1)) '${r['evt']}@${r['t']}'],
      ['tap@1000', 'cycle@5000', 'tap@7000', 'alert@8000'],
    );
  });

  test('rebases onto the earliest header so no offset goes negative', () {
    // Here the isolate was already running before the UI session began.
    final ui = jsonl([
      header('2026-07-25T12:00:10.000Z'),
      record(0, 'recording_started'),
    ]);
    final fgs = jsonl([
      header('2026-07-25T12:00:00.000Z', stream: 'fgs'),
      record(0, 'cycle', src: 'fgs'),
    ]);

    final merged = parse(mergeSessions(ui, fgs));

    expect(merged.first['ts'], '2026-07-25T12:00:00.000Z');
    expect(merged.first['stream'], 'merged');
    expect([for (final r in merged.skip(1)) r['t']], [0, 10000]);
    expect(merged.every((r) => (r['t'] as int? ?? 0) >= 0), isTrue);
  });

  test('records sharing a millisecond keep primary before secondary', () {
    final ui = jsonl([header('2026-07-25T12:00:00.000Z'), record(500, 'from_ui')]);
    final fgs = jsonl([
      header('2026-07-25T12:00:00.000Z', stream: 'fgs'),
      record(500, 'from_fgs', src: 'fgs'),
    ]);

    final merged = parse(mergeSessions(ui, fgs));

    expect([for (final r in merged.skip(1)) r['evt']], ['from_ui', 'from_fgs']);
  });

  test('keeps the primary header fields, only retagging the stream', () {
    final ui = jsonl([header('2026-07-25T12:00:00.000Z'), record(0, 'tap')]);
    final fgs = jsonl([
      header('2026-07-25T12:00:00.000Z', stream: 'fgs'),
      record(0, 'cycle', src: 'fgs'),
    ]);

    final merged = parse(mergeSessions(ui, fgs)).first;

    expect(merged['app'], '0.11.2+1102');
    expect(merged['session'], 's1');
    expect(merged['stream'], 'merged');
  });

  group('a broken secondary never costs the primary', () {
    final ui = jsonl([header('2026-07-25T12:00:00.000Z'), record(0, 'tap')]);

    test('empty', () => expect(mergeSessions(ui, ''), ui));
    test('header only', () {
      expect(mergeSessions(ui, jsonl([header('2026-07-25T12:00:00.000Z')])), ui);
    });
    test('not json', () => expect(mergeSessions(ui, 'garbage\nmore\n'), ui));
    test('header without a timestamp', () {
      expect(mergeSessions(ui, jsonl(['{"v":1}', record(0, 'x')])), ui);
    });
    test('truncated record lines are skipped, not fatal', () {
      final fgs = jsonl([
        header('2026-07-25T12:00:00.000Z', stream: 'fgs'),
        '{"t":10,"src":"fgs","evt":"cyc',
        record(20, 'cycle', src: 'fgs'),
      ]);

      final merged = parse(mergeSessions(ui, fgs));
      expect(merged, hasLength(3));
      expect(merged.last['evt'], 'cycle');
    });
  });

  test('an empty primary is returned untouched', () {
    expect(mergeSessions('', 'anything'), '');
  });
}
