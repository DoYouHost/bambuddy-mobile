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
    final ui = jsonl([
      header('2026-07-25T12:00:00.000Z'),
      record(500, 'from_ui'),
    ]);
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
      expect(
        mergeSessions(ui, jsonl([header('2026-07-25T12:00:00.000Z')])),
        ui,
      );
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

  group('which isolate wrote a record', () {
    test('stamps the secondary stream and leaves the primary bare', () {
      // After the merge the header says `merged`, so without this a request made
      // by the background service is indistinguishable from one made by the UI —
      // and both polling at once is a bug this log has already caught.
      final ui = jsonl([
        header('2026-07-25T12:00:00.000Z'),
        record(0, 'response', src: 'http'),
      ]);
      final fgs = jsonl([
        header('2026-07-25T12:00:00.000Z', stream: 'fgs'),
        record(10, 'response', src: 'http'),
      ]);

      final merged = parse(mergeSessions(ui, fgs));

      expect(merged[1].containsKey('iso'), isFalse);
      expect(merged[2]['iso'], 'fgs');
    });

    test('a third stream folds in with its own name', () {
      final ui = jsonl([header('2026-07-25T12:00:00.000Z'), record(0, 'tap')]);
      final fgs = jsonl([
        header('2026-07-25T12:00:00.000Z', stream: 'fgs'),
        record(10, 'cycle', src: 'fgs'),
      ]);
      final action = jsonl([
        header('2026-07-25T12:00:00.000Z', stream: 'action'),
        record(20, 'action', src: 'notif'),
      ]);

      final merged = parse(mergeSessions(mergeSessions(ui, fgs), action));

      expect(
        [for (final r in merged.skip(1)) r['iso']],
        [null, 'fgs', 'action'],
      );
      // The stamp from the first pass survives the second.
      expect([for (final r in merged.skip(1)) r['t']], [0, 10, 20]);
    });

    test('a stream calling itself ui is not stamped', () {
      final ui = jsonl([header('2026-07-25T12:00:00.000Z'), record(0, 'tap')]);
      final other = jsonl([
        header('2026-07-25T12:00:01.000Z'),
        record(0, 'tap'),
      ]);

      final merged = parse(mergeSessions(ui, other));

      expect(merged.skip(1).every((r) => !r.containsKey('iso')), isTrue);
    });
  });

  group('a background file the system killed mid-write', () {
    test(
      'a second header inside the stream is skipped, not read as a record',
      () {
        // A restarted foreground service can append to the file it already wrote.
        // Taken for a record, the stray header lands at t=0 — in front of
        // everything, with no source and no event name.
        final ui = jsonl([
          header('2026-07-25T12:00:00.000Z'),
          record(500, 'tap'),
        ]);
        final fgs = jsonl([
          header('2026-07-25T12:00:00.000Z', stream: 'fgs'),
          record(100, 'cycle', src: 'fgs'),
          header('2026-07-25T12:00:00.000Z', stream: 'fgs'), // second onStart
          record(200, 'cycle', src: 'fgs'),
        ]);

        final merged = parse(mergeSessions(ui, fgs));

        expect(merged, hasLength(4)); // header + 3 records, not 5
        expect(
          merged.every((r) => !r.containsKey('session') || r == merged.first),
          isTrue,
        );
        expect([for (final r in merged.skip(1)) r['t']], [100, 200, 500]);
      },
    );

    test('a record whose t is not a number costs itself and nothing else', () {
      // Without this the cast threw out of `mergeSessions`, out of `stop()`, and
      // the user got no log at all after five minutes of recording.
      final ui = jsonl([header('2026-07-25T12:00:00.000Z'), record(0, 'tap')]);
      final fgs = jsonl([
        header('2026-07-25T12:00:00.000Z', stream: 'fgs'),
        jsonEncode({'t': 'soon', 'src': 'fgs', 'evt': 'cycle'}),
        record(10, 'cycle', src: 'fgs'),
      ]);

      final merged = parse(mergeSessions(ui, fgs));

      expect(merged, hasLength(3));
      expect(merged.last['t'], 10);
    });
  });

  group('orderSession', () {
    test('puts the records in the order things happened, header first', () {
      // Arrival order is not event order: a tap is stamped with the moment the
      // finger went down and is written after the route change it caused.
      final file = jsonl([
        header('2026-07-25T12:00:00.000Z'),
        record(900, 'route'),
        record(100, 'tap'),
        record(500, 'response', src: 'http'),
      ]);

      final ordered = parse(orderSession(file));

      expect(ordered.first['session'], 's1');
      expect([for (final r in ordered.skip(1)) r['t']], [100, 500, 900]);
    });

    test('records sharing a millisecond keep the order they arrived in', () {
      final file = jsonl([
        header('2026-07-25T12:00:00.000Z'),
        record(5, 'first'),
        record(5, 'second'),
        record(5, 'third'),
      ]);

      final ordered = parse(orderSession(file));

      expect(
        [for (final r in ordered.skip(1)) r['evt']],
        ['first', 'second', 'third'],
      );
    });

    test('a torn last line costs itself and nothing else', () {
      // What a killed process leaves behind: half a record with no `t`.
      final file =
          '${jsonl([header('2026-07-25T12:00:00.000Z'), record(10, 'tap')])}{"t":20,"src":"ui","ev';

      final ordered = parse(orderSession(file));

      expect(ordered, hasLength(2));
      expect(ordered.last['evt'], 'tap');
    });

    test('a file with no usable records keeps only its header', () {
      final file = jsonl([header('2026-07-25T12:00:00.000Z'), 'not json']);

      // One line is how the caller reads "nothing here" and falls back to
      // the in-memory ring.
      expect(parse(orderSession(file)), hasLength(1));
    });

    test('nothing to order comes back untouched', () {
      final headerOnly = jsonl([header('2026-07-25T12:00:00.000Z')]);
      expect(orderSession(headerOnly), headerOnly);
      expect(orderSession(''), '');
      // No header means this is not a session, and rewriting it would only lose
      // whatever it actually is.
      final headerless = jsonl([record(10, 'tap'), record(0, 'tap')]);
      expect(orderSession(headerless), headerless);
    });
  });
}
