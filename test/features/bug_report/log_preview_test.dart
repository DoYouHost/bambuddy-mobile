import 'package:bambuddy_mobile/features/bug_report/log_preview.dart';
import 'package:flutter_test/flutter_test.dart';

/// A session-shaped log: header line, then [records] records of ~40 chars.
String session(int records) => [
      '{"v":1,"ts":"2026-07-29T08:00:00.000Z","session":"s1","app":"0.11.5"}',
      for (var i = 0; i < records; i++)
        '{"t":$i,"src":"ui","evt":"tap","id":"nav.queue"}',
    ].join('\n');

void main() {
  group('logPreview', () {
    test('a session that fits comes back whole', () {
      final log = session(5);

      final preview = logPreview(log);

      expect(preview.text, log);
      expect(preview.hiddenChars, 0);
    });

    test('a long session keeps its header and the tail of its records', () {
      final log = session(2000);

      final preview = logPreview(log, maxChars: 1024);

      expect(preview.text, startsWith('{"v":1,'),
          reason: 'the header is the context every record is read against');
      expect(preview.text, contains('"t":1999'),
          reason: 'the bug is at the end — that is where recording stops');
      expect(preview.text, isNot(contains('"t":0,')));
      expect(preview.text.length, lessThanOrEqualTo(1024));
      expect(preview.hiddenChars, greaterThan(0));
      // What was cut plus what is shown accounts for the whole log.
      expect(preview.hiddenChars + preview.text.length, log.length);
    });

    test('the window starts on a record boundary', () {
      final preview = logPreview(session(2000), maxChars: 1024);
      final firstRecord = preview.text.split('\n')[1];

      expect(firstRecord, startsWith('{"t":'));
      expect(firstRecord, endsWith('}'),
          reason: 'half a JSON line reads as a corrupted log');
    });

    test('a log with no line breaks is clipped as plain text', () {
      // Not a session — nothing here should be mistaken for a header.
      final preview = logPreview('x' * 5000, maxChars: 1000);

      expect(preview.text, hasLength(1000));
      expect(preview.hiddenChars, 4000);
    });

    test('a header longer than the window leaves the records out', () {
      final log = '${'h' * 200}\n${'r' * 200}';

      final preview = logPreview(log, maxChars: 100);

      expect(preview.text, '${'h' * 200}\n');
      expect(preview.hiddenChars, 200);
    });
  });
}
