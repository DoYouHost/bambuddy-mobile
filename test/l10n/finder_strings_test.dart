import 'package:app_guards/app_guards.dart';
import 'package:flutter_test/flutter_test.dart';

/// A finder that spells out the app's own copy breaks on every wording change.
///
/// About 1,400 `find.text('…')` calls once hardcoded Polish UI strings, so
/// gluing one-letter words with U+00A0 meant editing literals in 22 files. The
/// text comes from `pl` (`test/helpers.dart`) instead — `find.text(pl.cancel)` —
/// and this test refuses a finder that goes back to a literal.
///
/// Source-scanning, like `wrap_run_spacing_test`: the defect is a fact about
/// the code, and one assertion covers every test file, present and future.
///
/// What is **not** copy and stays literal: whatever the server or a fixture
/// supplies (printer names, HMS text, announcement bodies) and the framework's
/// own strings. Those match no `.arb` value and carry no Polish diacritic, so
/// the rules never see them; the few that do are listed in `notAppCopy`.
void main() {
  /// Poland-only text that is data, not our copy, but would trip the
  /// diacritic rule. Every entry says where the text really comes from.
  const notAppCopy = <String>{
    'OK', // MaterialLocalizations: the stock date picker's button
    'Skończył się filament', // HMS description in the fixture catalogue
    'treść', // announcement body in a fixture
    'treść new', // announcement body in a fixture
    '1.23 zł', // currency formatted by intl, not an .arb string
    'Jak to działa', // app_report_ui's own sheet, not an .arb string
    // Vendor and fixture names that happen to sit inside a message.
    'Bambu Lab',
    'Home Assistant',
    'Administrators',
    // Fragments asserted ABSENT, where the whole message is not the point.
    'Aktywne błędy',
    'płyta główna',
    "wybierz 'Wznów'",
    'Wznów”',
    'Auto-suszenie',
    'Przywróć',
    'Slot',
    'Pokazujemy wartości domyślne', // opens four different messages
    'Zaktualizuj bambuddy', // closes two different messages
    // Fragment of a message that takes a parameter ("Brak wyników dla „x”").
    'Brak wyników',
    'Brak filamentów', // opens two messages, one of them parameterised
  };

  test('no finder in test/ spells out copy that lives in the .arb', () {
    final offenders = finderCopy(
      AppCopy.fromArb(
        'lib/l10n/app_pl.arb',
        prefix: 'pl',
        marks: RegExp('[ąćęłńóśźżĄĆĘŁŃÓŚŹŻ]'),
      ),
      allowed: notAppCopy,
      // This file quotes literals on purpose.
      skip: (path) => path.endsWith('finder_strings_test.dart'),
    );
    expect(
      offenders.join('\n'),
      isEmpty,
      reason:
          'These read their text from a literal. Use pl.<key> from '
          'test/helpers.dart; if the text is server data that happens to '
          'look like copy, add it to notAppCopy with its source.',
    );
  });
}
