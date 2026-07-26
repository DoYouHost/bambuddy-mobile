import 'dart:convert';

import 'package:bambuddy_mobile/core/diagnostics/log_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String jsonl(List<Map<String, Object?>> rows) =>
      '${rows.map(jsonEncode).join('\n')}\n';

  const header = {
    'v': 1,
    'ts': '2026-07-25T12:00:00.000Z',
    'session': 's1',
    'app': '0.11.2+1102',
  };

  test('splits the header off from the records', () {
    final summary = LogSummary.parse(jsonl([
      header,
      {'t': 0, 'src': 'app', 'evt': 'recording_started'},
      {'t': 10, 'src': 'ui', 'evt': 'tap'},
    ]));

    expect(summary.header['session'], 's1');
    expect(summary.lines, hasLength(2));
  });

  test('counts records per source, warnings, errors and markers', () {
    final summary = LogSummary.parse(jsonl([
      header,
      {'t': 1, 'src': 'http', 'evt': 'response', 'lvl': 'warn', 'status': 502},
      {'t': 2, 'src': 'http', 'evt': 'response', 'status': 200},
      {'t': 3, 'src': 'err', 'evt': 'uncaught', 'lvl': 'error'},
      {'t': 4, 'src': 'app', 'evt': 'user_marker'},
    ]));

    expect(summary.bySource, {'http': 2, 'err': 1, 'app': 1});
    expect(summary.warnings, 1);
    expect(summary.errors, 1);
    expect(summary.markers, 1);
  });

  test('orders the source chips by the enum, not by first appearance', () {
    final summary = LogSummary.parse(jsonl([
      header,
      {'t': 1, 'src': 'err', 'evt': 'uncaught'},
      {'t': 2, 'src': 'http', 'evt': 'response'},
      {'t': 3, 'src': 'ui', 'evt': 'tap'},
    ]));

    expect([for (final e in summary.sourceCounts) e.key], ['http', 'ui', 'err']);
  });

  test('flags a truncated session', () {
    final summary = LogSummary.parse(jsonl([
      header,
      {'t': 0, 'src': 'app', 'evt': 'truncated', 'dropped': 120},
    ]));

    expect(summary.truncated, isTrue);
  });

  test('survives a half-written last line', () {
    final summary = LogSummary.parse(
      '${jsonEncode(header)}\n'
      '{"t":1,"src":"ui","evt":"tap"}\n'
      '{"t":2,"src":"ui","evt":"ta',
    );

    expect(summary.lines, hasLength(1));
  });

  test('handles a stream with no header at all', () {
    final summary = LogSummary.parse(jsonl([
      {'t': 1, 'src': 'ui', 'evt': 'tap'},
    ]));

    expect(summary.header, isEmpty);
    expect(summary.lines, hasLength(1));
  });

  test('empty input is empty, not a throw', () {
    expect(LogSummary.parse('').isEmpty, isTrue);
    expect(LogSummary.parse('   \n\n').isEmpty, isTrue);
  });

  group('LogLine', () {
    test('splits extra fields from the record keys', () {
      final line = LogLine.fromJson(const {
        't': 1204,
        'src': 'http',
        'evt': 'response',
        'lvl': 'warn',
        'status': 502,
        'ms': 1204,
      });

      expect(line.fields, {'status': 502, 'ms': 1204});
      expect(line.detail, 'status=502 · ms=1204');
      expect(line.isWarning, isTrue);
    });

    test('formats the offset as minutes and seconds', () {
      expect(const LogLine(t: 0, src: 'app', evt: 'x').offset, '0:00.0');
      expect(const LogLine(t: 1204, src: 'app', evt: 'x').offset, '0:01.2');
      expect(const LogLine(t: 83400, src: 'app', evt: 'x').offset, '1:23.4');
      expect(const LogLine(t: 605000, src: 'app', evt: 'x').offset, '10:05.0');
    });
  });
}
