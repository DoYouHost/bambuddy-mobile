import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A `Wrap` that sets `spacing` and not `runSpacing` looks correct until the
/// day it wraps.
///
/// `spacing` is the gap *within* a run; the gap *between* runs is `runSpacing`,
/// which defaults to zero. So the buttons sit apart on a wide screen and touch
/// on a narrow one — or at a larger system text size, which is where this was
/// found: two buttons above the maintenance type list with no gap at all
/// between them, on a screen that had looked right since it was written.
///
/// Source-scanning rather than a layout test, for the same reason
/// `wear_type_scale_test` scans: the defect is a fact about the code, and
/// pinning it needs one assertion rather than a rendered case per `Wrap`. A
/// layout test would only cover the widths someone thought to write down.
void main() {
  test('every Wrap that sets spacing also sets runSpacing', () {
    final offenders = <String>[];

    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      for (final match in RegExp(r'\bWrap\(').allMatches(source)) {
        var depth = 0;
        var i = match.end - 1;
        for (; i < source.length; i++) {
          depth += switch (source[i]) {
            '(' => 1,
            ')' => -1,
            _ => 0,
          };
          if (depth == 0) break;
        }
        final arguments = source.substring(match.end, i);
        if (arguments.contains('spacing:') &&
            !arguments.contains('runSpacing:')) {
          final line = '\n'.allMatches(source.substring(0, match.start)).length;
          offenders.add('${file.path}:${line + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'These wrap onto a second line with no gap between the rows. Add '
          'runSpacing (usually the same value as spacing).',
    );
  });
}
