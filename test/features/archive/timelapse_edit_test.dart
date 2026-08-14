import 'dart:convert';

import 'package:bambuddy_mobile/core/models/timelapse.dart';
import 'package:bambuddy_mobile/features/archive/timelapse_export.dart';
import 'package:bambuddy_mobile/features/archive/timelapse_format.dart';
import 'package:bambuddy_mobile/features/archive/timelapse_providers.dart';
import 'package:bambuddy_mobile/features/archive/timelapse_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

const _info = TimelapseInfo(
  duration: 54,
  width: 1920,
  height: 1080,
  fps: 30,
  codec: 'h264',
  fileSize: 12345,
  hasAudio: false,
);

/// 1×1 JPEG — enough for the strip to have something decodable in it.
const _jpeg =
    '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0a'
    'HBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAARCAABAAEDASIAAhEBAxEB/8QAHwAA'
    'AQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIh'
    'MUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpT'
    'VFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5'
    'usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD3+iii'
    'gD//2Q==';

void main() {
  group('formatClock', () {
    test('poniżej godziny bez wiodącego zera', () {
      expect(formatClock(0), '0:00');
      expect(formatClock(7), '0:07');
      expect(formatClock(54), '0:54');
      expect(formatClock(605), '10:05');
    });

    test('powyżej godziny dokłada człon godzinowy', () {
      expect(formatClock(3661), '1:01:01');
    });

    test('ułamki sekundy ucina — zegar nie wyprzedza materiału', () {
      expect(formatClock(0.6), '0:00');
      expect(formatClock(1.9), '0:01');
    });
  });

  group('formatSpeed', () {
    test('obcina zbędne zera', () {
      expect(formatSpeed(1), '1x');
      expect(formatSpeed(0.25), '0.25x');
      expect(formatSpeed(1.5), '1.5x');
    });
  });

  group('exportFilename', () {
    test('składa nazwę pliku z nazwy wydruku', () {
      expect(exportFilename('Part Studio 1'), 'Part_Studio_1_timelapse.mp4');
    });

    test('wycina znaki, które wywracają zapis albo udostępnianie', () {
      expect(exportFilename('a/b\\c:d*?'), 'abcd_timelapse.mp4');
      expect(exportFilename('  ../etc  '), 'etc_timelapse.mp4');
    });

    test('pusta nazwa nie daje pliku zaczynającego się od podkreślenia', () {
      expect(exportFilename('///'), 'timelapse_timelapse.mp4');
    });
  });

  group('TimelapseFilmstrip.fromJson', () {
    test('dekoduje klatki i znaczniki czasu', () {
      final strip = TimelapseFilmstrip.fromJson({
        'thumbnails': [_jpeg, _jpeg],
        'timestamps': [0, 3.5],
      });

      expect(strip.frames, hasLength(2));
      expect(strip.timestamps, [0.0, 3.5]);
      expect(strip.isEmpty, isFalse);
    });

    test('niedekodowalna klatka nie zabiera całego paska', () {
      final strip = TimelapseFilmstrip.fromJson({
        'thumbnails': [_jpeg, 'nie-base64!!'],
        'timestamps': [0, 1],
      });

      expect(strip.frames, hasLength(1));
    });

    test('brak pól to pusty pasek, nie wyjątek', () {
      expect(TimelapseFilmstrip.fromJson(const {}).isEmpty, isTrue);
    });
  });

  group('ekran edycji', () {
    testWidgets('pokazuje długość źródła i wyliczony wynik dla prędkości',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            timelapseInfoProvider(7).overrideWith((ref) async => _info),
            timelapseFilmstripProvider(7).overrideWith(
              (ref) async => TimelapseFilmstrip(
                frames: [base64Decode(_jpeg)],
                timestamps: const [0],
              ),
            ),
          ],
          child: plApp(const TimelapseEditorScreen(archiveId: 7)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Oryginał: 0:54 w 1920×1080'), findsOneWidget);
      expect(find.text('Wynik: 0:54'), findsOneWidget);

      await tester.tap(find.text('2x'));
      await tester.pumpAndSettle();

      expect(find.text('Wynik: 0:27'), findsOneWidget,
          reason: '2x skraca 54 s do 27 s');
    });

    testWidgets('bez podglądu wideo edytor dalej daje przyciąć i zapisać',
        (tester) async {
      // Podglądu nie ma: w teście nie istnieje natywna strona video_player,
      // czyli dokładnie ta degradacja, którą ekran ma przetrwać.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            timelapseInfoProvider(7).overrideWith((ref) async => _info),
            timelapseFilmstripProvider(7).overrideWith(
              (ref) async =>
                  const TimelapseFilmstrip(frames: [], timestamps: []),
            ),
          ],
          child: plApp(const TimelapseEditorScreen(archiveId: 7)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RangeSlider), findsOneWidget);
      expect(find.text('Zapisz'), findsOneWidget);
    });

    testWidgets('nieudane info zostawia ekran z ponowieniem, nie spinnerem',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            timelapseInfoProvider(7)
                .overrideWith((ref) async => throw Exception('boom')),
            timelapseFilmstripProvider(7).overrideWith(
              (ref) async => const TimelapseFilmstrip(
                frames: [],
                timestamps: [],
              ),
            ),
          ],
          child: plApp(const TimelapseEditorScreen(archiveId: 7)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Spróbuj ponownie'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
