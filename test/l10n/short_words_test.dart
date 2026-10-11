import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The same rules as tool/glue_short_words.py. A letter on its own — not the
/// "h" of "1h" or "{hours}h", not the tail of "don't" — followed by a plain
/// space a line could break at; except a unit right after its number, which
/// is glued to the number instead and may end a line.
final _breakableShortWord = RegExp(
  r"(?<![\p{L}\p{N}_'’}])"
  r"(?:(?<![0-9}][ \u00A0])\p{L}|[^\P{L}hsdgjW]) ",
  unicode: true,
);

/// …and a one-letter unit split from its number: "24 h", "{grams} g".
final _breakableUnit = RegExp(
  r"[0-9}] [hsdgjW](?![\p{L}\p{N}_'’])",
  unicode: true,
);

void main() {
  test('no translation leaves a one-letter word at a line end', () {
    final offenders = <String>[];
    for (final file in Directory('lib/l10n').listSync()) {
      if (!file.path.endsWith('.arb')) continue;
      final arb = jsonDecode(File(file.path).readAsStringSync()) as Map;
      arb.forEach((key, value) {
        if (key.toString().startsWith('@') || value is! String) return;
        final hit =
            _breakableShortWord.firstMatch(value) ??
            _breakableUnit.firstMatch(value);
        if (hit != null) {
          offenders.add('${file.path} $key: "…${value.substring(hit.start)}"');
        }
      });
    }
    expect(
      offenders,
      isEmpty,
      reason: 'run `just l10n-glue` to fix:\n${offenders.join('\n')}',
    );
  });
}
