import 'package:bambuddy_mobile/features/bug_report/log_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('logFileName', () {
    test('is sortable, second-precise and plain text', () {
      expect(
        logFileName(DateTime(2026, 7, 28, 14, 30, 5)),
        'bambuddy-log-20260728-143005.txt',
      );
    });

    test('pads every field so names of one day sort as one block', () {
      expect(
        logFileName(DateTime(2026, 1, 2, 3, 4, 5)),
        'bambuddy-log-20260102-030405.txt',
      );
    });

    test('two saves a second apart do not land on one file', () {
      final first = logFileName(DateTime(2026, 7, 28, 14, 30, 5));
      final second = logFileName(DateTime(2026, 7, 28, 14, 30, 6));
      expect(first, isNot(second));
    });
  });
}
