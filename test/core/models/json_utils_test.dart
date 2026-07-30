import 'dart:convert';

import 'package:bambuddy_mobile/core/diagnostics/diagnostic_recorder.dart';
import 'package:bambuddy_mobile/core/diagnostics/session_facts.dart';
import 'package:bambuddy_mobile/core/models/json_utils.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DiagnosticRecorder recorder;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    recorder = DiagnosticRecorder(
      settings: SettingsRepository(await SharedPreferences.getInstance()),
      loadFacts: () async => const SessionFacts(
        app: '0.11.5+1105',
        flavor: 'mobile',
      ),
      resolveDirectory: () async => null,
    );
    addTearDown(recorder.discard);
  });

  Future<List<Map<String, dynamic>>> stopAndParse() async {
    final jsonl = await recorder.stop();
    return [
      for (final line in const LineSplitter().convert(jsonl))
        jsonDecode(line) as Map<String, dynamic>,
    ];
  }

  group('dateTimeFromJson', () {
    // Wartości wzięte z prawdziwych odpowiedzi serwera 0.2.5b2.
    test('z sufiksem Z: instant UTC, oddany lokalnie', () {
      final d = dateTimeFromJson('2026-07-30T16:00:00Z')!;

      expect(d.isUtc, isFalse, reason: 'konsument formatuje pola wprost');
      expect(d.toUtc().hour, 16);
      expect(d.millisecondsSinceEpoch,
          DateTime.utc(2026, 7, 30, 16).millisecondsSinceEpoch);
    });

    test('bez strefy znaczy UTC, nie czas lokalny', () {
      // To jest ten drugi błąd: serwer trzyma UTC w naive kolumnach i część
      // schematów nie dokleja Z. Dart czytał to jako lokalne, więc każda data
      // archiwum i każdy kubełek statystyk był przesunięty o offset urządzenia.
      final naive = dateTimeFromJson('2026-07-29T06:15:10.233878')!;
      final explicit = dateTimeFromJson('2026-07-29T06:15:10.233878Z')!;

      expect(naive, explicit,
          reason: 'oba zapisy to ta sama chwila — serwer jest niekonsekwentny '
              'w formacie, nie w znaczeniu');
      expect(naive.toUtc().hour, 6);
    });

    test('offset i Z naraz — zepsuta odpowiedź PATCH', () {
      // serialize_utc_datetime dokleja Z do wartości, która ma już +00:00.
      // DateTime.tryParse zwraca na to null, czyli po cichu gubi termin.
      expect(DateTime.tryParse('2026-07-30T16:00:00+00:00Z'), isNull,
          reason: 'gdyby Dart to łykał, tolerancja nie byłaby potrzebna');

      final d = dateTimeFromJson('2026-07-30T16:00:00+00:00Z')!;
      expect(d, dateTimeFromJson('2026-07-30T16:00:00Z'));
    });

    test('prawdziwy offset zostaje uszanowany', () {
      expect(
        dateTimeFromJson('2026-07-30T18:00:00+02:00'),
        dateTimeFromJson('2026-07-30T16:00:00Z'),
      );
    });

    test('brak, śmieci i nie-stringi → null, nigdy wyjątek', () {
      for (final junk in [null, '', '   ', 'wczoraj', 42, <String>[], {}]) {
        expect(dateTimeFromJson(junk), isNull, reason: 'wejście: $junk');
      }
    });

    test('goła data bez czasu nie dostaje strefy', () {
      // Nie ma tu pory dnia, więc doklejenie Z byłoby zgadywaniem; wartość
      // zostaje kalendarzowa.
      final d = dateTimeFromJson('2026-07-30')!;
      expect([d.year, d.month, d.day], [2026, 7, 30]);
    });
  });

  group('calendarDateFromJson', () {
    test('data zostaje tą datą, bez przesuwania strefą', () {
      // Termin projektu na 5. ma być 5. wszędzie. Przez dateTimeFromJson
      // północ UTC zjechałaby na 4. dla każdego na zachód od UTC.
      for (final raw in [
        '2026-08-05',
        '2026-08-05T00:00:00',
        '2026-08-05T00:00:00Z',
      ]) {
        final d = calendarDateFromJson(raw)!;
        expect([d.year, d.month, d.day], [2026, 8, 5], reason: raw);
        expect(d.isUtc, isFalse);
      }
    });

    test('nie-data → null', () {
      for (final junk in [null, '', 'kiedyś', 7]) {
        expect(calendarDateFromJson(junk), isNull, reason: 'wejście: $junk');
      }
    });
  });

  group('parseJsonList', () {
    test('pomija zepsuty element, resztę parsuje', () {
      final items = parseJsonList(
        [
          {'id': 1, 'position': 1, 'status': 'pending'},
          // `position` jest wymagane — generowany rzut wywala się na null.
          {'id': 2, 'status': 'pending'},
          {'id': 3, 'position': 2, 'status': 'pending'},
        ],
        QueueItem.fromJson,
      );

      expect(items.map((i) => i.id), [1, 3]);
    });

    test('zapisuje odrzucone elementy do logu: ile, z ilu i dlaczego', () async {
      await recorder.start();

      // Cała lista do wyrzucenia — dokładnie ten przypadek, w którym ekran
      // wygląda jak pusty, a serwer odpowiedział 200 z danymi.
      final items = parseJsonList(
        [
          {'id': 1, 'status': 'pending'},
          {'id': 2, 'status': 'pending'},
        ],
        QueueItem.fromJson,
      );

      expect(items, isEmpty);
      final drop = (await stopAndParse())
          .firstWhere((r) => r['evt'] == 'parse_drop');
      expect(drop['src'], 'app');
      expect(drop['lvl'], 'warn');
      expect(drop['type'], 'QueueItem');
      expect(drop['n'], 2);
      expect(drop['of'], 2);
      expect(drop['cause'], contains('Null'),
          reason: 'przyczyna nazywa rzut, który się wywalił');
    });

    test('element, który nie jest obiektem, też jest raportowany', () async {
      await recorder.start();

      parseJsonList(['nie obiekt'], QueueItem.fromJson);

      final drop = (await stopAndParse())
          .firstWhere((r) => r['evt'] == 'parse_drop');
      expect(drop['n'], 1);
      expect(drop['cause'], contains('not an object'));
    });

    test('nic nie odrzucone — żadnego rekordu', () async {
      await recorder.start();

      parseJsonList(
        [
          {'id': 1, 'position': 1, 'status': 'pending'},
        ],
        QueueItem.fromJson,
      );

      expect(
        (await stopAndParse()).where((r) => r['evt'] == 'parse_drop'),
        isEmpty,
      );
    });
  });
}
