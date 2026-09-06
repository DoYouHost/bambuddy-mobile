import 'dart:convert';
import 'dart:typed_data';

import 'package:bambuddy_mobile/core/models/timelapse.dart';
import 'package:bambuddy_mobile/features/archive/timelapse_export.dart';
import 'package:bambuddy_mobile/features/archive/timelapse_format.dart';
import 'package:bambuddy_mobile/features/archive/timelapse_providers.dart';
import 'package:bambuddy_mobile/features/archive/timelapse_trim.dart';
import 'package:bambuddy_mobile/features/archive/timelapse_trim_strip.dart';
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

  group('pętla podglądu', () {
    test('w środku zakresu nie zawija', () {
      expect(timelapseReachedEnd(5, 30), isFalse);
    });

    test('koniec zakresu łapie z zapasem na odstęp klatek', () {
      expect(timelapseReachedEnd(29.95, 30), isTrue);
      expect(timelapseReachedEnd(31, 30), isTrue);
    });

    test('niedostrzelony seek pod początek zakresu NIE zawija w kółko', () {
      // Regresja: reguła pilnująca też początku wyzwalała się na własnym
      // niedostrzeleniu — seek, niedostrzelenie, seek. Dekoder tylko czyścił
      // bufory, obraz nie ruszał.
      expect(
        timelapseReachedEnd(9.98, 30),
        isFalse,
        reason: 'pozycja tuż pod startem 10 s to nie koniec zakresu',
      );
    });

    test('start odtwarzania cofa spoza zakresu i z jego końca', () {
      expect(timelapseNeedsRewind(9.98, 10, 30), isTrue);
      expect(timelapseNeedsRewind(29.99, 10, 30), isTrue);
      expect(timelapseNeedsRewind(15, 10, 30), isFalse);
    });
  });

  group('kontener pliku', () {
    test('rozszerzenie bierze z typu treści, nie z założenia', () {
      expect(timelapseExtension('video/mp4'), 'mp4');
      expect(timelapseExtension('video/x-msvideo'), 'avi');
      expect(timelapseExtension('video/x-matroska'), 'mkv');
    });

    test('parametry i wielkość liter nie mylą rozpoznania', () {
      expect(timelapseExtension('Video/X-MSVideo; charset=binary'), 'avi');
    });

    test('brak lub nieznany typ to mp4, bo to serwuje serwer domyślnie', () {
      expect(timelapseExtension(null), 'mp4');
      expect(timelapseExtension('application/octet-stream'), 'mp4');
    });

    test('typ do udostępnienia wraca z rozszerzenia pliku', () {
      expect(timelapseMimeType('/tmp/a_timelapse.avi'), 'video/x-msvideo');
      expect(timelapseMimeType('/tmp/a_timelapse.mp4'), 'video/mp4');
    });
  });

  group('exportFilename', () {
    test('składa nazwę pliku z nazwy wydruku', () {
      expect(exportFilename('Part Studio 1'), 'Part_Studio_1_timelapse.mp4');
    });

    test('bierze kontener, którym serwer nazwał plik', () {
      expect(exportFilename('Part', 'avi'), 'Part_timelapse.avi');
    });

    test('wycina znaki, które wywracają zapis albo udostępnianie', () {
      expect(exportFilename('a/b\\c:d*?'), 'abcd_timelapse.mp4');
      expect(exportFilename('  ../etc  '), 'etc_timelapse.mp4');
    });

    test('pusta nazwa nie daje pliku zaczynającego się od podkreślenia', () {
      expect(exportFilename('///'), 'timelapse_timelapse.mp4');
    });

    test('keeps letters of any script, so a folder of videos stays usable', () {
      // `\w` is ASCII in Dart: before the Unicode class this reduced "Łódź" to
      // "d" and a Japanese name to nothing at all, so every such print saved as
      // the same fallback name.
      expect(exportFilename('Łódź'), 'Łódź_timelapse.mp4');
      expect(exportFilename('日本語 x2'), '日本語_x2_timelapse.mp4');
      // Emoji are neither letter nor digit and a share target may refuse them.
      expect(exportFilename('Benchy 🎉'), 'Benchy_timelapse.mp4');
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

  group('framesFitting', () {
    final all = List.generate(14, (i) => i);

    test(
      'na wąskim pasku żadna klatka nie schodzi poniżej czytelnej szerokości',
      () {
        const stripWidth = 517.0;
        final shown = framesFitting(all, stripWidth);

        expect(stripWidth / shown.length, greaterThanOrEqualTo(56.0));
        expect(
          shown,
          hasLength(lessThan(all.length)),
          reason: 'przy tej szerokości komplet się nie mieści',
        );
      },
    );

    test('próbkuje z całego materiału, nie z jego początku', () {
      final shown = framesFitting(all, 517);

      expect(shown, orderedEquals(shown.toList()..sort()));
      expect(shown.toSet(), hasLength(shown.length), reason: 'bez powtórek');
      expect(
        shown.last,
        greaterThan(all.length ~/ 2),
        reason: 'ostatnia próbka z końcowej połowy, nie z pierwszej',
      );
    });

    test('każda klatka trafia pod moment, który pokazuje', () {
      // 14 klatek na 6 kafelków. Kafelek i zajmuje [i/6, (i+1)/6] materiału,
      // klatka j jest z chwili j/14 — więc do kafelka pasuje ta najbliższa
      // jego środkowi. Przy próbkowaniu „od początku kafelka" ostatni kafelek
      // (83–100%) dostawał klatkę z 78,6% i końcówki nie dało się przyciąć.
      final shown = framesFitting(all, 360);

      expect(shown, hasLength(6));
      for (var i = 0; i < shown.length; i++) {
        final tileStart = i / shown.length;
        final tileEnd = (i + 1) / shown.length;
        final frameAt = shown[i] / all.length;
        expect(
          frameAt,
          greaterThanOrEqualTo(tileStart - 0.001),
          reason: 'klatka $i sprzed swojego kafelka',
        );
        expect(
          frameAt,
          lessThanOrEqualTo(tileEnd + 0.001),
          reason: 'klatka $i zza swojego kafelka',
        );
      }
    });

    test(
      'ostatni kafelek pokazuje ostatnią klatkę, jaką serwer wyrenderował',
      () {
        expect(framesFitting(all, 360).last, all.last);
        expect(framesFitting(all, 517).last, all.last);
      },
    );

    test('gdy wszystkie się mieszczą, nie gubi żadnej', () {
      expect(framesFitting(all, 2000), all);
    });

    test('pusta lista i zerowa szerokość nie wywracają się', () {
      expect(framesFitting(<int>[], 500), isEmpty);
      expect(framesFitting(all, 0), hasLength(1));
    });
  });

  group('pasek przycinania', () {
    // 300 px na 60 s materiału. Oś czasu jest wcięta o szerokość uchwytu z
    // każdej strony, więc środek paska wypada na 30 s.
    const width = 300.0;
    const duration = 60.0;

    Future<({List<RangeValues> trims, List<double> ends, List<double> seeks})>
    pumpStrip(
      WidgetTester tester, {
      RangeValues trim = const RangeValues(0, duration),
      double? position,
      List<Uint8List> frames = const [],
    }) async {
      final trims = <RangeValues>[];
      final ends = <double>[];
      final seeks = <double>[];
      var current = trim;
      await tester.pumpWidget(
        plApp(
          Center(
            child: SizedBox(
              width: width,
              // Zakres wraca do paska tak, jak robi to edytor — bez tego
              // sprzężenia widżet w teście widziałby wiecznie stary zakres i
              // asercje mierzyłyby harness, nie produkt.
              child: StatefulBuilder(
                builder: (context, setState) => TimelapseTrimStrip(
                  frames: frames,
                  duration: duration,
                  trim: current,
                  minClip: 1,
                  position: position,
                  onTrimChanged: (v) {
                    trims.add(v);
                    setState(() => current = v);
                  },
                  onTrimCommitted: ends.add,
                  onSeek: seeks.add,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (trims: trims, ends: ends, seeks: seeks);
    }

    Rect rectOf(WidgetTester tester, Key key) =>
        tester.getRect(find.byKey(key));

    Rect playheadRect(WidgetTester tester) =>
        rectOf(tester, TimelapseTrimStrip.playheadKey);

    testWidgets('przeciągnięcie lewego uchwytu przesuwa początek zakresu', (
      tester,
    ) async {
      final r = await pumpStrip(tester);
      final strip = tester.getRect(find.byType(TimelapseTrimStrip));

      // Chwyt na lewym uchwycie (start = 0 s siedzi na 12 px), przeciągnięcie
      // do 58 px, czyli 46 px po torze = 10 s.
      await tester.dragFrom(
        Offset(strip.left + 2, strip.center.dy),
        const Offset(56, 0),
      );
      await tester.pumpAndSettle();

      expect(r.trims, isNotEmpty);
      expect(r.trims.last.start, closeTo(10, 0.5));
      expect(r.trims.last.end, duration, reason: 'koniec nietknięty');
      expect(
        r.ends,
        hasLength(1),
        reason: 'seek dla podglądu tylko raz, po puszczeniu',
      );
      expect(
        r.ends.single,
        closeTo(r.trims.last.start, 0.01),
        reason: 'podgląd parkuje na przeciągniętym początku, nie na końcu',
      );
    });

    testWidgets('puszczenie prawego uchwytu parkuje podgląd na jego końcu', (
      tester,
    ) async {
      final r = await pumpStrip(tester);
      final strip = tester.getRect(find.byType(TimelapseTrimStrip));

      await tester.dragFrom(
        Offset(strip.right - 2, strip.center.dy),
        const Offset(-56, 0),
      );
      await tester.pumpAndSettle();

      expect(r.ends.single, closeTo(r.trims.last.end, 0.01));
    });

    testWidgets('chwyt za uchwyt nie przewija podglądu', (tester) async {
      // onTapDown odpalał się, zanim przeciąganie wygrało arenę gestów, więc
      // samo złapanie uchwytu szarpało znacznikiem w miejsce dotknięcia.
      final r = await pumpStrip(tester, trim: const RangeValues(20, 40));
      final strip = tester.getRect(find.byType(TimelapseTrimStrip));
      final startHandle = rectOf(tester, TimelapseTrimStrip.startHandleKey);

      // Palec najpierw chwilę stoi na uchwycie — tak się go łapie i dopiero
      // wtedy rozpoznawanie tapnięcia zdąża minąć swój próg czasu. Natychmiast
      // rozpoczęte przeciągnięcie nie odtworzyłoby tego błędu.
      final gesture = await tester.startGesture(
        Offset(startHandle.center.dx, strip.center.dy),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(r.trims, isNotEmpty, reason: 'uchwyt jednak ruszył');
      expect(r.seeks, isEmpty, reason: 'żaden seek przy chwytaniu uchwytu');
    });

    testWidgets('nagranie krótsze niż minimalny fragment nie wywraca gestu', (
      tester,
    ) async {
      // clamp(0, end - minClip) rzuca, gdy granice się mijają — a przy 0,5 s
      // materiału mijają się zawsze.
      await tester.pumpWidget(
        plApp(
          Center(
            child: SizedBox(
              width: width,
              child: TimelapseTrimStrip(
                frames: const [],
                duration: 0.5,
                trim: const RangeValues(0, 0.5),
                minClip: 1,
                onTrimChanged: (_) {},
                onTrimCommitted: (_) {},
                onSeek: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final strip = tester.getRect(find.byType(TimelapseTrimStrip));

      await tester.dragFrom(
        Offset(strip.left + 2, strip.center.dy),
        const Offset(56, 0),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('przeciągnięcie w środku paska przewija, nie tnie', (
      tester,
    ) async {
      final r = await pumpStrip(tester);
      final strip = tester.getRect(find.byType(TimelapseTrimStrip));

      // Przeciągnięcie musi przekroczyć próg dotyku (18 px), inaczej system
      // uzna je za tapnięcie — stąd 30 px, a nie kilkanaście.
      await tester.dragFrom(strip.center, const Offset(30, 0));
      await tester.pumpAndSettle();

      expect(r.trims, isEmpty, reason: 'zakres bez zmian');
      expect(
        r.seeks.last,
        closeTo(36.5, 0.5),
        reason: '180 px to 168 px po torze, czyli 36,5 s',
      );
    });

    testWidgets('znacznik czasu nie wchodzi pod uchwyty', (tester) async {
      // Na obu krańcach materiału znacznik nie może zachodzić na wyrenderowany
      // uchwyt — sprawdzane na prostokątach, nie na stałej z widżetu.
      for (final at in [0.0, duration]) {
        await pumpStrip(tester, position: at);
        final line = playheadRect(tester);

        expect(
          line.overlaps(rectOf(tester, TimelapseTrimStrip.startHandleKey)),
          isFalse,
          reason: 'znacznik na $at s wchodzi pod lewy uchwyt',
        );
        expect(
          line.overlaps(rectOf(tester, TimelapseTrimStrip.endHandleKey)),
          isFalse,
          reason: 'znacznik na $at s wchodzi pod prawy uchwyt',
        );
      }
    });

    testWidgets(
      'znacznik jedzie od pierwszej sekundy, bez postoju na starcie',
      (tester) async {
        // Regresja: znacznik był docinany do krawędzi wyliczanych z zakresu
        // przycięcia, więc przez pierwsze ~2,5 s stał w miejscu, choć materiał
        // już leciał. Test nie przelicza wzoru — sprawdza, że kolejne sekundy
        // dają kolejne, rosnące położenia.
        final seen = <double>[];
        for (final second in [0.0, 1.0, 2.0, 3.0, 30.0, duration]) {
          await pumpStrip(tester, position: second);
          seen.add(playheadRect(tester).center.dx);
        }

        for (var i = 1; i < seen.length; i++) {
          expect(
            seen[i],
            greaterThan(seen[i - 1]),
            reason: 'sekunda $i nie przesunęła znacznika',
          );
        }
      },
    );

    testWidgets('przycięcie nie przesuwa ani nie skaluje klatek', (
      tester,
    ) async {
      await pumpStrip(tester);
      final full = rectOf(tester, TimelapseTrimStrip.framesKey);

      await pumpStrip(tester, trim: const RangeValues(20, 40));
      final trimmed = rectOf(tester, TimelapseTrimStrip.framesKey);

      expect(
        trimmed,
        full,
        reason: 'klatki to oś czasu — zakres je przyciemnia, nie przelicza',
      );
    });

    testWidgets('uchwyt nie zasłania materiału, który zostaje', (tester) async {
      // Uchwyt może leżeć na przyciemnionej części — tę i tak wycinamy.
      // Nie może wejść na kadr między przyciemnieniami, czyli na to, co
      // zostanie po zapisie.
      for (final trim in [
        const RangeValues(0, duration),
        const RangeValues(20, 40),
      ]) {
        await pumpStrip(tester, trim: trim);
        final keptLeft = rectOf(tester, TimelapseTrimStrip.dimStartKey).right;
        final keptRight = rectOf(tester, TimelapseTrimStrip.dimEndKey).left;

        expect(
          rectOf(tester, TimelapseTrimStrip.startHandleKey).right,
          lessThanOrEqualTo(keptLeft + 0.01),
          reason: 'lewy uchwyt wchodzi na zachowany kadr przy $trim',
        );
        expect(
          rectOf(tester, TimelapseTrimStrip.endHandleKey).left,
          greaterThanOrEqualTo(keptRight - 0.01),
          reason: 'prawy uchwyt wchodzi na zachowany kadr przy $trim',
        );
      }
    });

    testWidgets('przewijanie nie wychodzi poza przycięty zakres', (
      tester,
    ) async {
      final r = await pumpStrip(tester, trim: const RangeValues(20, 40));
      final strip = tester.getRect(find.byType(TimelapseTrimStrip));

      // Tap tuż przy prawej krawędzi paska, czyli poza zakresem (40 s).
      await tester.tapAt(Offset(strip.right - 4, strip.center.dy));
      await tester.pumpAndSettle();

      expect(r.seeks.single, 40, reason: 'docięte do końca zakresu');
    });
  });

  group('ekran edycji', () {
    testWidgets('pokazuje długość źródła i wyliczony wynik dla prędkości', (
      tester,
    ) async {
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

      expect(
        find.text('Wynik: 0:27'),
        findsOneWidget,
        reason: '2x skraca 54 s do 27 s',
      );
    });

    testWidgets('bez podglądu wideo edytor dalej daje przyciąć i zapisać', (
      tester,
    ) async {
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

      expect(find.byType(TimelapseTrimStrip), findsOneWidget);
      expect(find.text('Zapisz'), findsOneWidget);
    });

    testWidgets('nieudane info zostawia ekran z ponowieniem, nie spinnerem', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            timelapseInfoProvider(
              7,
            ).overrideWith((ref) async => throw Exception('boom')),
            timelapseFilmstripProvider(7).overrideWith(
              (ref) async =>
                  const TimelapseFilmstrip(frames: [], timestamps: []),
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
