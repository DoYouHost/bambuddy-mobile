import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Padding, margins and gaps go through `DashSpace`, never a number typed in
/// place — that is how the app ended up with 25 values and side margins that
/// did not line up from one row to the next.
///
/// Scans for a non-zero numeric literal inside an `EdgeInsets` constructor,
/// a child-less `SizedBox` gap, a `Wrap`/grid spacing argument and a
/// `Divider` indent.
/// Sizes (a 48 dp button, an icon) are not spacing and are not scanned.
void main() {
  test('spacing in lib/ comes from DashSpace', () {
    final literal = RegExp(
      r'EdgeInsets(?:Directional)?\.\w+\(([^()]*)\)'
      r'|SizedBox\((?:width|height): ([\d.]+)\)'
      r'|\b(?:runSpacing|spacing|crossAxisSpacing|mainAxisSpacing'
      r'|indent|endIndent): ([\d.]+)\b',
    );
    final number = RegExp(r'(?<![\w.])(\d+(?:\.\d+)?)(?![\w.])');
    final offenders = <String>[];

    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .where((f) => !f.path.contains('/l10n/'))) {
      final source = file.readAsStringSync();
      for (final m in literal.allMatches(source)) {
        final args = m.group(1) ?? m.group(2) ?? m.group(3)!;
        final nonZero = number
            .allMatches(args)
            .map((n) => double.parse(n.group(1)!))
            .any((v) => v != 0);
        if (nonZero) {
          final line = '\n'.allMatches(source.substring(0, m.start)).length;
          offenders.add('${file.path}:${line + 1}  ${m.group(0)}');
        }
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
