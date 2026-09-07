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
      loadFacts: () async =>
          const SessionFacts(app: '0.11.5+1105', flavor: 'mobile'),
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
    // Values taken from real 0.2.5b2 server responses.
    test('z sufiksem Z: instant UTC, oddany lokalnie', () {
      final d = dateTimeFromJson('2026-07-30T16:00:00Z')!;

      expect(d.isUtc, isFalse, reason: 'konsument formatuje pola wprost');
      expect(d.toUtc().hour, 16);
      expect(
        d.millisecondsSinceEpoch,
        DateTime.utc(2026, 7, 30, 16).millisecondsSinceEpoch,
      );
    });

    test('bez strefy znaczy UTC, nie czas lokalny', () {
      // The second bug: the server keeps UTC in naive columns and only some
      // schemas append the Z. Dart read that as local, so every archive date and
      // every statistics bucket was off by the device's offset.
      final naive = dateTimeFromJson('2026-07-29T06:15:10.233878')!;
      final explicit = dateTimeFromJson('2026-07-29T06:15:10.233878Z')!;

      expect(
        naive,
        explicit,
        reason:
            'oba zapisy to ta sama chwila — serwer jest niekonsekwentny '
            'w formacie, nie w znaczeniu',
      );
      expect(naive.toUtc().hour, 6);
    });

    test('an offset and a Z at once — the malformed PATCH answer', () {
      // serialize_utc_datetime appends Z to a value that already carries +00:00.
      // DateTime.tryParse zwraca na to null, czyli po cichu gubi termin.
      expect(
        DateTime.tryParse('2026-07-30T16:00:00+00:00Z'),
        isNull,
        reason: 'if Dart swallowed this, the tolerance would be unnecessary',
      );

      final d = dateTimeFromJson('2026-07-30T16:00:00+00:00Z')!;
      expect(d, dateTimeFromJson('2026-07-30T16:00:00Z'));
    });

    test('prawdziwy offset zostaje uszanowany', () {
      expect(
        dateTimeFromJson('2026-07-30T18:00:00+02:00'),
        dateTimeFromJson('2026-07-30T16:00:00Z'),
      );
    });

    test('absent, junk and non-strings → null, never a throw', () {
      for (final junk in [null, '', '   ', 'wczoraj', 42, <String>[], {}]) {
        expect(dateTimeFromJson(junk), isNull, reason: 'input: $junk');
      }
    });

    test('a bare date with no time of day gets no zone', () {
      // There is no time of day here, so appending a Z would be a guess; the value
      // zostaje kalendarzowa.
      final d = dateTimeFromJson('2026-07-30')!;
      expect([d.year, d.month, d.day], [2026, 7, 30]);
    });
  });

  group('calendarDateFromJson', () {
    test('a date stays that date, with no zone shift', () {
      // A project due on the 5th is the 5th everywhere. Through dateTimeFromJson
      // UTC midnight would slide to the 4th for anyone west of UTC.
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
      for (final junk in [null, '', 'someday', 7]) {
        expect(calendarDateFromJson(junk), isNull, reason: 'input: $junk');
      }
    });
  });

  group('parseJsonList', () {
    test('skips the broken element and parses the rest', () {
      final items = parseJsonList([
        {'id': 1, 'position': 1, 'status': 'pending'},
        // `position` is required — the generated cast throws on a null.
        {'id': 2, 'status': 'pending'},
        {'id': 3, 'position': 2, 'status': 'pending'},
      ], QueueItem.fromJson);

      expect(items.map((i) => i.id), [1, 3]);
    });

    test(
      'records the dropped elements: how many, of how many, and why',
      () async {
        await recorder.start();

        // The whole list dropped — exactly the case where the screen looks empty
        // and the server answered 200 with data in it.
        final items = parseJsonList([
          {'id': 1, 'status': 'pending'},
          {'id': 2, 'status': 'pending'},
        ], QueueItem.fromJson);

        expect(items, isEmpty);
        final drop = (await stopAndParse()).firstWhere(
          (r) => r['evt'] == 'parse_drop',
        );
        expect(drop['src'], 'app');
        expect(drop['lvl'], 'warn');
        expect(drop['type'], 'QueueItem');
        expect(drop['n'], 2);
        expect(drop['of'], 2);
        expect(
          drop['cause'],
          contains('Null'),
          reason: 'the cause names the cast that failed',
        );
      },
    );

    test('an element that is not an object is reported too', () async {
      await recorder.start();

      parseJsonList(['not an object'], QueueItem.fromJson);

      final drop = (await stopAndParse()).firstWhere(
        (r) => r['evt'] == 'parse_drop',
      );
      expect(drop['n'], 1);
      expect(drop['cause'], contains('not an object'));
    });

    test('nothing dropped — no record at all', () async {
      await recorder.start();

      parseJsonList([
        {'id': 1, 'position': 1, 'status': 'pending'},
      ], QueueItem.fromJson);

      expect(
        (await stopAndParse()).where((r) => r['evt'] == 'parse_drop'),
        isEmpty,
      );
    });
  });

  group('parseJsonList tolerance', () {
    test('reads a record whose static key type is not String', () {
      // What a platform channel hands back (`Map<Object?, Object?>`) and what an
      // untyped `Map.from` builds. The private list parsers this one replaced
      // accepted both; an exact `is Map<String, dynamic>` test would drop them
      // as "not an object" without a word.
      final items = parseJsonList(<dynamic>[
        <Object?, Object?>{'id': 1, 'position': 1, 'status': 'pending'},
      ], QueueItem.fromJson);

      expect(items.single.id, 1);
    });
  });

  group('parseJsonListOrNull', () {
    test('tells an absent list apart from an empty one', () {
      // The whole reason it exists: `PrinterStatus.mergedWith` inherits on null
      // and blanks the card on an empty list.
      expect(parseJsonListOrNull(null, QueueItem.fromJson), isNull);
      expect(parseJsonListOrNull('not a list', QueueItem.fromJson), isNull);
      expect(parseJsonListOrNull(<dynamic>[], QueueItem.fromJson), isEmpty);
    });

    test('drops one bad record rather than the list', () {
      final items = parseJsonListOrNull([
        {'id': 1, 'position': 1, 'status': 'pending'},
        {'id': 2, 'status': 'pending'},
      ], QueueItem.fromJson);

      expect(items!.map((i) => i.id), [1]);
    });
  });

  group('parseJsonObjectOrNull', () {
    test('parses a nested record', () {
      final item = parseJsonObjectOrNull({
        'id': 7,
        'position': 1,
        'status': 'pending',
      }, QueueItem.fromJson);

      expect(item!.id, 7);
    });

    test('answers null for anything that is not an object', () {
      for (final junk in [null, 'text', 3, <dynamic>[]]) {
        expect(
          parseJsonObjectOrNull(junk, QueueItem.fromJson),
          isNull,
          reason: 'input: $junk',
        );
      }
    });

    test(
      'a record the factory chokes on reads as absent, and is recorded',
      () async {
        // Not a throw: the field is one part of a frame, and losing the frame
        // over it would take the whole card down with it.
        await recorder.start();

        final item = parseJsonObjectOrNull({'id': 1}, QueueItem.fromJson);

        expect(item, isNull);
        final drop = (await stopAndParse()).firstWhere(
          (r) => r['evt'] == 'parse_drop',
        );
        expect(drop['type'], 'QueueItem');
        expect(drop['n'], 1);
      },
    );
  });

  group('parseJsonMapByIdOrNull', () {
    test('reads the stringified numeric keys the server sends', () {
      final map = parseJsonMapByIdOrNull({'0': 1, '1': 0}, toIntOrNull);

      expect(map, {0: 1, 1: 0});
    });

    test('keeps absence apart from emptiness', () {
      expect(parseJsonMapByIdOrNull(null, toIntOrNull), isNull);
      expect(parseJsonMapByIdOrNull('not a map', toIntOrNull), isNull);
      expect(parseJsonMapByIdOrNull(<String, dynamic>{}, toIntOrNull), isEmpty);
    });

    test('drops an entry it cannot read either half of', () {
      // A key that is not a number would otherwise have to be guessed at, and a
      // guessed AMS id addresses the wrong unit.
      final map = parseJsonMapByIdOrNull({
        '0': 1,
        'left': 1,
        '2': 'not a number',
      }, toIntOrNull);

      expect(map, {0: 1});
    });
  });

  group('toBoolOrFalse', () {
    test('accepts the spellings the server and the printer both use', () {
      expect(toBoolOrFalse(true), isTrue);
      expect(toBoolOrFalse(1), isTrue);
      expect(toBoolOrFalse('true'), isTrue);
      expect(toBoolOrFalse('TRUE'), isTrue);
      expect(toBoolOrFalse('1'), isTrue);
    });

    test('anything it cannot read is false, never a throw', () {
      // Every flag read through it names a capability or an accessory, where
      // "not reported" and "not there" are the same answer.
      for (final junk in [null, 0, 'false', 'yes', '', <dynamic>[]]) {
        expect(toBoolOrFalse(junk), isFalse, reason: 'input: $junk');
      }
    });
  });

  group('toStringMap', () {
    test('keeps the keys as strings and drops what is not a label', () {
      // `printer_names` on `/archives/stats`: ids as string keys, and a name
      // the server has no record of arriving as null rather than as a name.
      final names = toStringMap(const {
        '3': 'Ultron',
        4: 'Bender',
        '5': null,
        '6': '   ',
        '7': 42,
      });

      expect(names['3'], 'Ultron');
      expect(names['4'], 'Bender');
      // A blank or non-string value is no label: the caller's own fallback
      // names that row better than an empty string would.
      expect(names.keys, ['3', '4']);
    });

    test('a missing or non-map field is an empty map, never a throw', () {
      expect(toStringMap(null), isEmpty);
      expect(toStringMap('nope'), isEmpty);
      expect(toStringMap(const []), isEmpty);
    });
  });
}
