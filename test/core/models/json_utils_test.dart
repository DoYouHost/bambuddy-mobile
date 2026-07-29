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
