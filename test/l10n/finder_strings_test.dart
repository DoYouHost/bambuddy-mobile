import 'dart:convert';
import 'dart:io';

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
/// the rules below never see them; the few that do are listed in [_notAppCopy].
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

  group('finder literals', () {
    final copy = _PolishCopy.fromArb('lib/l10n/app_pl.arb');

    test('no finder in test/ spells out copy that lives in the .arb', () {
      final offenders = <String>[];
      for (final file in _testFiles()) {
        final source = file.readAsStringSync();
        for (final hit in finderLiterals(source)) {
          final why = copy.explain(hit.text, allowed: notAppCopy);
          if (why != null) {
            final line = '\n'.allMatches(source.substring(0, hit.at)).length;
            offenders.add(
              '${file.path}:${line + 1}  ${jsonEncode(hit.text)}'
              '  →  $why',
            );
          }
        }
      }
      expect(
        offenders.join('\n'),
        isEmpty,
        reason:
            'These read their text from a literal. Use pl.<key> from '
            'test/helpers.dart; if the text is server data that happens to '
            'look like copy, add it to notAppCopy with its source.',
      );
    });

    test('the rules do catch a literal (so the scan above is not vacuous)', () {
      expect(copy.explain('Anuluj', allowed: {}), isNotNull);
      expect(copy.explain('Zaznaczono: 2', allowed: {}), isNotNull);
      expect(copy.explain('Pominięto cokolwiek', allowed: {}), isNotNull);
      expect(
        copy.explain('przestanie działać natychmiast', allowed: {}),
        'part of pl.apiKeysRevokeBody',
        reason: 'a fragment names its message even when it has diacritics',
      );
      expect(copy.explain('X1C Warsztat', allowed: {}), isNull);
      expect(copy.explain('part-1.3mf', allowed: {}), isNull);
    });
  });

  group('finderLiterals', () {
    List<String> texts(String source) => [
      for (final hit in finderLiterals(source)) hit.text,
    ];

    test('reads the first argument of each text finder', () {
      expect(
        texts(
          "find.text('a'); find.textContaining(\"b\"); find.byTooltip('c'); "
          "find.bySemanticsLabel('d');",
        ),
        ['a', 'b', 'c', 'd'],
      );
    });

    test('reads every text property of matchesSemantics, in any order', () {
      expect(texts("matchesSemantics(label: 'a', isButton: true)"), ['a']);
      expect(texts("matchesSemantics(isButton: true, label: 'a')"), ['a']);
      expect(
        texts("matchesSemantics(tooltip: 'a', hint: 'b', isEnabled: true)"),
        ['a', 'b'],
      );
      expect(texts('matchesSemantics(isButton: true)'), isEmpty);
    });

    test('reads the second argument of widgetWithText', () {
      expect(texts("find.widgetWithText(FilledButton, 'Zapisz')"), ['Zapisz']);
      expect(
        texts("find.widgetWithText(List<int>, 'x')"),
        ['x'],
        reason: 'a comma inside generics is not the argument separator',
      );
    });

    test('decodes escapes and joins adjacent literals', () {
      expect(texts(r"find.text('a b\'c\n')"), ['a b\'c\n']);
      expect(texts("find.text('one '\n    'two')"), ['one two']);
      expect(texts(r"find.text('w\xa0tle')"), ['w\u00A0tle']);
      expect(texts(r"find.text(r'\n')"), [r'\n']);
    });

    test('skips what it cannot know', () {
      expect(texts('find.text(l10n.cancel)'), isEmpty);
      expect(texts(r"find.text('a $b')"), isEmpty);
      expect(texts(r"find.text('a ${b}')"), isEmpty);
      expect(texts("find.text('a' + b)"), isEmpty);
      expect(texts('find.text('), isEmpty);
    });
  });
}

Iterable<File> _testFiles() => Directory('test')
    .listSync(recursive: true)
    .whereType<File>()
    .where(
      (f) =>
          f.path.endsWith('.dart') &&
          // This file quotes literals on purpose.
          !f.path.endsWith('finder_strings_test.dart'),
    );

/// One string literal found as a finder's text argument.
typedef FinderLiteral = ({String text, int at});

final _finder = RegExp(
  r'find\.(text|textContaining|byTooltip|bySemanticsLabel|widgetWithText)\(|'
  r'(matchesSemantics)\(',
);

final _semanticsText = RegExp(r'\b(?:label|tooltip|hint|value):');

/// The text argument of every `find.text(…)`-style call (and the first
/// property of a `matchesSemantics(…)`) in [source]; calls whose
/// text is not one plain literal (a variable, an interpolation, `'a' + b`) are
/// skipped, because there is nothing to compare.
List<FinderLiteral> finderLiterals(String source) {
  final found = <FinderLiteral>[];
  for (final match in _finder.allMatches(source)) {
    var i = match.end;
    if (match.group(2) != null) {
      // Any order, any number of the text properties.
      final call = source.substring(
        i,
        _endOfArgument(source, i, stopAtComma: false),
      );
      for (final property in _semanticsText.allMatches(call)) {
        final literal = _readLiterals(call, property.end);
        if (literal != null) found.add((text: literal.$1, at: match.start));
      }
      continue;
    }
    if (match.group(1) == 'widgetWithText') {
      i = _endOfArgument(source, i);
      if (i >= source.length) continue;
      i++; // the comma
    }
    final literal = _readLiterals(source, i);
    if (literal != null) found.add((text: literal.$1, at: match.start));
  }
  return found;
}

/// Index of the comma that ends the argument starting at [from] (or the
/// closing parenthesis), ignoring commas nested in `()`, `[]`, `{}` and `<>`.
int _endOfArgument(String s, int from, {bool stopAtComma = true}) {
  var depth = 0;
  for (var i = from; i < s.length; i++) {
    switch (s[i]) {
      case '(' || '[' || '{' || '<':
        depth++;
      case ')' || ']' || '}' || '>':
        if (depth == 0) return i;
        depth--;
      case ',' when depth == 0 && stopAtComma:
        return i;
    }
  }
  return s.length;
}

/// Adjacent string literals from [from], joined — and the index after them —
/// when they are the whole argument; null otherwise.
(String, int)? _readLiterals(String s, int from) {
  final out = StringBuffer();
  var i = from;
  var read = 0;
  while (true) {
    while (i < s.length && s[i].trim().isEmpty) {
      i++;
    }
    final one = _readLiteral(s, i);
    if (one == null) break;
    out.write(one.$1);
    i = one.$2;
    read++;
  }
  if (read == 0) return null;
  // `'a' + b` and `'a' ? …` are not a plain literal.
  if (i < s.length && s[i] != ',' && s[i] != ')') return null;
  return (out.toString(), i);
}

const _escapes = {
  'n': '\n',
  't': '\t',
  'r': '\r',
  "'": "'",
  '"': '"',
  r'\': r'\',
  r'$': r'$',
};

(String, int)? _readLiteral(String s, int from) {
  var i = from;
  var raw = false;
  if (i < s.length && s[i] == 'r') {
    raw = true;
    i++;
  }
  if (i >= s.length || (s[i] != "'" && s[i] != '"')) return null;
  final quote = s[i++];
  final out = StringBuffer();
  while (i < s.length) {
    final c = s[i];
    if (c == quote) return (out.toString(), i + 1);
    if (!raw && c == r'$') return null; // interpolated: not a fixed text
    if (!raw && c == r'\') {
      final n = s[i + 1];
      if (n == 'u') {
        final braced = s[i + 2] == '{';
        final end = braced ? s.indexOf('}', i) : i + 6;
        final hex = s.substring(braced ? i + 3 : i + 2, end);
        out.writeCharCode(int.parse(hex, radix: 16));
        i = braced ? end + 1 : end;
        continue;
      }
      if (n == 'x') {
        out.writeCharCode(int.parse(s.substring(i + 2, i + 4), radix: 16));
        i += 4;
        continue;
      }
      out.write(_escapes[n] ?? n);
      i += 2;
      continue;
    }
    out.write(c);
    i++;
  }
  return null;
}

/// The Polish `.arb` values, as the shapes a finder literal could take.
class _PolishCopy {
  _PolishCopy(Map<String, List<String>> shapesByKey) {
    final holes = RegExp('[$_text$_number]');
    shapesByKey.forEach((key, shapes) {
      for (final shape in shapes) {
        if (!shape.contains(holes)) {
          _plain.putIfAbsent(shape, () => []).add(key);
        } else if (shape.replaceAll(holes, '').trim().length >= 5) {
          // Less fixed text than that matches half the alphabet ("$n min").
          final pattern = shape.splitMapJoin(
            holes,
            onMatch: (m) => m[0] == _number ? r'\d+' : '.+?',
            onNonMatch: RegExp.escape,
          );
          _templates[key] = [
            ...?_templates[key],
            RegExp('^$pattern\$', dotAll: true),
          ];
        }
      }
    });
  }

  factory _PolishCopy.fromArb(String path) {
    final arb = jsonDecode(File(path).readAsStringSync()) as Map;
    // Placeholder types live in the template file only.
    final meta = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync());
    Set<String> numeric(String key) {
      final placeholders = (meta['@$key'] as Map?)?['placeholders'] as Map?;
      return {
        for (final e in placeholders?.entries ?? const <MapEntry>[])
          if (const {'int', 'num', 'double'}.contains(e.value['type']))
            e.key as String,
      };
    }

    return _PolishCopy({
      for (final e in arb.entries)
        if (!(e.key as String).startsWith('@') && e.value is String)
          e.key as String: _shapes(
            (e.value as String).replaceAll("''", "'"),
            numeric(e.key as String),
          ),
    });
  }

  /// A placeholder holding free text, and one holding a number.
  static const _text = '\u0000';
  static const _number = '\u0001';
  final _plain = <String, List<String>>{};
  final _templates = <String, List<RegExp>>{};

  static final _polish = RegExp('[ąćęłńóśźżĄĆĘŁŃÓŚŹŻ]');

  /// Why [literal] reads as copy, or null when it does not.
  String? explain(String literal, {required Set<String> allowed}) {
    if (allowed.contains(literal)) return null;
    final keys = _plain[literal];
    if (keys != null) return 'pl.${keys.first}';
    for (final MapEntry(:key, :value) in _templates.entries) {
      if (value.any((rx) => rx.hasMatch(literal))) return 'pl.$key(…)';
    }
    // A long fragment of one message ("przestanie działać natychmiast").
    if (literal.trim().length >= 8) {
      for (final MapEntry(:key, :value) in _plain.entries) {
        if (value.isNotEmpty && key.contains(literal)) {
          return 'part of pl.${value.first}';
        }
      }
    }
    if (_polish.hasMatch(literal)) return 'Polish text: pl.<key>';
    return null;
  }

  /// Every concrete text [message] (ICU) can render as, a `{placeholder}`
  /// standing for [_text] or [_number]. `plural` and `select` branches each
  /// become a shape.
  static List<String> _shapes(String message, Set<String> numeric) {
    var shapes = <String>[''];
    var i = 0;
    while (i < message.length) {
      if (message[i] != '{') {
        final next = message.indexOf('{', i);
        final end = next == -1 ? message.length : next;
        final text = message.substring(i, end);
        shapes = [for (final s in shapes) '$s$text'];
        i = end;
        continue;
      }
      final close = _matching(message, i);
      final inner = message.substring(i + 1, close);
      final comma = inner.indexOf(',');
      final branches = comma == -1
          ? [numeric.contains(inner.trim()) ? _number : _text]
          : _branches(
              inner.substring(inner.indexOf(',', comma + 1) + 1),
              numeric,
            );
      shapes = [
        for (final s in shapes)
          for (final b in branches) '$s$b',
      ];
      i = close + 1;
    }
    return shapes;
  }

  /// Bodies of `selector{body}` pairs, each expanded in turn.
  static List<String> _branches(String list, Set<String> numeric) {
    final bodies = <String>[];
    var i = 0;
    while (true) {
      final open = list.indexOf('{', i);
      if (open == -1) break;
      final close = _matching(list, open);
      bodies.addAll(_shapes(list.substring(open + 1, close), numeric));
      i = close + 1;
    }
    return bodies;
  }

  static int _matching(String s, int open) {
    var depth = 0;
    for (var i = open; i < s.length; i++) {
      if (s[i] == '{') depth++;
      if (s[i] == '}' && --depth == 0) return i;
    }
    return s.length - 1;
  }
}
