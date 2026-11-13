import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/l10n_add.dart';

void main() {
  const languages = {'en', 'pl'};
  const en = '{\n  "@@locale": "en",\n  "hello": "Hello"\n}\n';
  const pl = '{\n  "@@locale": "pl",\n  "hello": "Cześć"\n}\n';

  group('parseEntries', () {
    test('takes every language and an optional "@"', () {
      final entries = parseEntries(
        jsonEncode({
          'greet': {
            'en': 'Hi {name}',
            'pl': 'Hej {name}',
            '@': {
              'placeholders': {
                'name': {'type': 'String'},
              },
            },
          },
        }),
        languages,
      );
      expect(entries['greet']!['pl'], 'Hej {name}');
    });

    test('refuses a missing or empty language', () {
      for (final byLang in [
        {'en': 'Hi'},
        {'en': 'Hi', 'pl': ''},
        {'en': 'Hi', 'pl': 3},
      ]) {
        expect(
          () => parseEntries(jsonEncode({'greet': byLang}), languages),
          throwsFormatException,
          reason: '$byLang',
        );
      }
    });

    test('refuses a language the app has no file for', () {
      expect(
        () => parseEntries(
          jsonEncode({
            'greet': {'en': 'Hi', 'pl': 'Hej', 'it': 'Ciao'},
          }),
          languages,
        ),
        throwsFormatException,
      );
    });

    test('refuses a key that is not camelCase, and nonsense input', () {
      for (final json in [
        jsonEncode({
          'Greet': {'en': 'Hi', 'pl': 'Hej'},
        }),
        jsonEncode({
          'greet-me': {'en': 'Hi', 'pl': 'Hej'},
        }),
        jsonEncode({'greet': 'Hi'}),
        jsonEncode({
          'greet': {'en': 'Hi', 'pl': 'Hej', '@': 'meta'},
        }),
        '{}',
        '[]',
        'not json',
      ]) {
        expect(
          () => parseEntries(json, languages),
          throwsFormatException,
          reason: json,
        );
      }
    });
  });

  group('appendStrings', () {
    final entries = parseEntries(
      jsonEncode({
        'greet': {
          'en': 'Hi {name}',
          'pl': 'Hej {name}',
          '@': {
            'placeholders': {
              'name': {'type': 'String'},
            },
          },
        },
        'bye': {'en': 'Bye', 'pl': 'Pa'},
      }),
      languages,
    );

    test('appends after the last key and keeps the rest byte for byte', () {
      final out = appendStrings(pl, 'pl', entries);
      expect(
        out,
        '{\n  "@@locale": "pl",\n  "hello": "Cześć",\n'
        '  "greet": "Hej {name}",\n  "bye": "Pa"\n}\n',
      );
      expect(jsonDecode(out), isA<Map<String, dynamic>>());
    });

    test('metadata goes to the template only', () {
      final out = appendStrings(en, 'en', entries);
      expect(jsonDecode(out)['@greet'], {
        'placeholders': {
          'name': {'type': 'String'},
        },
      });
      expect(appendStrings(pl, 'pl', entries), isNot(contains('@greet')));
    });

    test('a key the file already has is refused', () {
      final clash = parseEntries(
        jsonEncode({
          'hello': {'en': 'Hello', 'pl': 'Cześć'},
        }),
        languages,
      );
      expect(() => appendStrings(pl, 'pl', clash), throwsFormatException);
    });
  });
}
