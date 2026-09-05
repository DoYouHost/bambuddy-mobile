import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the two `.arb` files against the failure that JSON cannot report.
///
/// A key defined twice is legal JSON: the later one wins silently, so
/// `gen-l10n` is happy, the analyzer is happy, and the string the app shows is
/// not the one anybody wrote. `archivePlate` sat like that for weeks — a line
/// meant for the detail sheet ("Plate 4 of a multi-plate file") shadowed the
/// short one, and the archive card's single-line meta strip spent its whole
/// width on it, pushing the material, the weight and the date past the ellipsis.
///
/// Read as text on purpose: `jsonDecode` collapses the duplicate before a test
/// could see it.
void main() {
  final files = ['lib/l10n/app_en.arb', 'lib/l10n/app_pl.arb'];

  /// Top-level keys in the order they are written, `@`-entries included.
  List<String> keysOf(String path) => RegExp(r'^  "([^"]+)":', multiLine: true)
      .allMatches(File(path).readAsStringSync())
      .map((m) => m.group(1)!)
      .toList();

  for (final path in files) {
    final name = path.split('/').last;

    test('$name defines every key once', () {
      final keys = keysOf(path);
      final seen = <String>{};
      final twice = [
        for (final key in keys)
          if (!seen.add(key)) key,
      ];
      expect(twice, isEmpty, reason: '$name defines $twice more than once');
      // A guard on the guard: a file that stopped being readable this way would
      // let the assertion pass over an empty list.
      expect(keys.length, greaterThan(100));
    });
  }

  test('both languages carry the same strings', () {
    // Not about duplicates, but the same class of silence: a key only one file
    // has is a screen that falls back to English without saying so.
    Set<String> stringsOf(String path) =>
        (jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>)
            .keys
            .where((k) => !k.startsWith('@'))
            .toSet();

    final en = stringsOf(files.first);
    final pl = stringsOf(files.last);
    expect(en.difference(pl), isEmpty, reason: 'missing from Polish');
    expect(pl.difference(en), isEmpty, reason: 'missing from English');
  });
}
