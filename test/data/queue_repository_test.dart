import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late QueueRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
    repo = QueueRepository(dio);
  });

  test('fetch: parsuje listę, id i statusKind są poprawne', () async {
    adapter.onGet(
      '/api/v1/queue/',
      (server) => server.reply(200, [readFixture('queue_item.json')]),
    );

    final items = await repo.fetch();

    expect(items, hasLength(1));
    expect(items.first.id, 78);
    expect(items.first.statusKind, QueueItemStatusKind.printing);
  });

  test('fetch: prawdziwa odpowiedź serwera parsuje się w całości', () async {
    // Fixture przechwycony z żywego bambuddy (patrz test/fixtures/README.md).
    // To jest tripwire na kontrakt: gdy serwer zmieni typ pola, na które
    // generowany `fromJson` rzuca twardo, `parseJsonList` wyrzuci rekordy po
    // cichu i ekran kolejki zrobi się pusty bez żadnego błędu.
    final payload = readFixture('queue_list.json') as List<dynamic>;
    adapter.onGet('/api/v1/queue/', (server) => server.reply(200, payload));

    final items = await repo.fetch();

    expect(items, hasLength(payload.length),
        reason: 'ani jeden rekord nie może wypaść przy parsowaniu');
    expect(items.map((i) => i.id), payload.map((r) => (r as Map)['id']));
  });

  test('fetch: pozycje spoza AMS i dziwne nazwy przechodzą bez straty',
      () async {
    final payload = readFixture('queue_list.json') as List<dynamic>;
    adapter.onGet('/api/v1/queue/', (server) => server.reply(200, payload));

    final items = await repo.fetch();
    final fromLibrary = items.firstWhere((i) => i.libraryFileId != null);
    final external = items.firstWhere((i) => i.amsMapping?.contains(254) ?? false);
    final scheduled = items.firstWhere((i) => i.scheduledTime != null);

    expect(fromLibrary.libraryFileName, endsWith('.gcode.3mf'));
    expect(external.amsMapping, contains(254));
    expect(scheduled.scheduledTime, isA<DateTime>());
    // Serwer zwraca też nazwy z zepsutym kodowaniem — nie mogą nic wywalić.
    expect(items.map((i) => i.displayName), isNot(contains(isNull)));
  });

  test('fetch: historia nie trafia do aktywnej kolejki', () async {
    // Cała ta odpowiedź to pozycje zakończone (completed/cancelled/failed) —
    // dokładnie taki serwer wygląda jak „kolejka pusta" na ekranie i jest to
    // poprawne: aktywne są tylko pending/scheduled/printing/paused.
    final payload = readFixture('queue_list.json') as List<dynamic>;
    adapter.onGet('/api/v1/queue/', (server) => server.reply(200, payload));

    final items = await repo.fetch();

    expect(items.where((i) => i.isActive), isEmpty);
    expect(
      items.map((i) => i.statusKind).toSet(),
      {
        QueueItemStatusKind.completed,
        QueueItemStatusKind.cancelled,
        QueueItemStatusKind.failed,
      },
      reason: 'żaden status z tej odpowiedzi nie może trafić do unknown',
    );
  });

  group('fetchActive', () {
    /// Dwa filtrowane żądania zamiast jednego po całość — dopasowanie po
    /// `queryParameters` jest tu istotą testu, nie ozdobą.
    void mockStatus(String status, List<dynamic> reply) => adapter.onGet(
          '/api/v1/queue/',
          (server) => server.reply(200, reply),
          queryParameters: {'status': status},
        );

    Map<String, dynamic> item(int id, String status) => {
          'id': id,
          'position': 1,
          'status': status,
        };

    test('pyta osobno o pending i printing, scala odpowiedzi', () async {
      mockStatus('pending', [item(2, 'pending'), item(3, 'pending')]);
      mockStatus('printing', [item(1, 'printing')]);

      final items = await repo.fetchActive();

      expect(items.map((i) => i.id).toSet(), {1, 2, 3});
      expect(items.where((i) => i.statusKind == QueueItemStatusKind.printing),
          hasLength(1));
    });

    test('pozycja, która ruszyła między odpowiedziami, jest raz i jako drukująca',
        () async {
      // Wyścig wbudowany w dwa żądania: scheduler wystartował 7 po tym, jak
      // lista pending została zbudowana.
      mockStatus('pending', [item(7, 'pending')]);
      mockStatus('printing', [item(7, 'printing')]);

      final items = await repo.fetchActive();

      expect(items, hasLength(1));
      expect(items.single.statusKind, QueueItemStatusKind.printing);
    });

    test('pusta kolejka to pusta lista, nie błąd', () async {
      mockStatus('pending', const []);
      mockStatus('printing', const []);

      expect(await repo.fetchActive(), isEmpty);
    });

    test('błąd któregokolwiek żądania nie ginie', () async {
      // Ekran ma pokazać błąd, nie „kolejka pusta" — to jest różnica między
      // „serwer nie odpowiedział" i „nie ma nic do druku".
      mockStatus('pending', const []);
      adapter.onGet(
        '/api/v1/queue/',
        (server) => server.reply(500, {'detail': 'boom'}),
        queryParameters: {'status': 'printing'},
      );

      await expectLater(repo.fetchActive(), throwsA(isA<AppApiException>()));
    });
  });

  test('reorder: wysyła POST i kończy się bez wyjątku', () async {
    adapter.onPost(
      '/api/v1/queue/reorder',
      (server) => server.reply(200, null),
      data: {
        'items': [
          {'id': 78, 'position': 1},
          {'id': 79, 'position': 2},
        ],
      },
    );

    await repo.reorder([(id: 78, position: 1), (id: 79, position: 2)]);
    // Brak wyjątku = sukces.
  });

  test('delete: wysyła DELETE /queue/78 i kończy się bez wyjątku', () async {
    adapter.onDelete(
      '/api/v1/queue/78',
      (server) => server.reply(200, null),
    );

    await repo.delete(78);
  });

  test('start: wysyła POST /queue/78/start i kończy się bez wyjątku', () async {
    adapter.onPost(
      '/api/v1/queue/78/start',
      (server) => server.reply(200, null),
    );

    await repo.start(78);
  });

  test('cancel: wysyła POST /queue/78/cancel i kończy się bez wyjątku',
      () async {
    adapter.onPost(
      '/api/v1/queue/78/cancel',
      (server) => server.reply(200, null),
    );

    await repo.cancel(78);
  });

  test('addFromArchive: wysyła POST /queue/ i kończy się bez wyjątku',
      () async {
    adapter.onPost(
      '/api/v1/queue/',
      (server) => server.reply(200, null),
      data: {'archive_id': 77, 'printer_id': 1, 'quantity': 1},
    );

    await repo.addFromArchive(77, printerId: 1);
  });

  test('addFromArchive z insertAtTop: dokłada insert_at_top=true (reprint)',
      () async {
    adapter.onPost(
      '/api/v1/queue/',
      (server) => server.reply(200, null),
      data: {
        'archive_id': 77,
        'printer_id': 1,
        'quantity': 1,
        'insert_at_top': true,
      },
    );

    await repo.addFromArchive(77, printerId: 1, insertAtTop: true);
  });

  test('addFromArchive z opcjami: cała konfiguracja idzie z POST-em', () async {
    // Sedno poprawki wyścigu: pozycja powstaje już skonfigurowana, więc
    // scheduler nie ma jak zabrać jej w trakcie ustawiania.
    adapter.onPost(
      '/api/v1/queue/',
      (server) => server.reply(200, null),
      data: {
        'archive_id': 77,
        'printer_id': 1,
        'quantity': 1,
        'ams_mapping': [2, -1],
        'manual_start': true,
        'require_previous_success': false,
        'auto_off_after': false,
        'bed_levelling': true,
        'flow_cali': false,
        'vibration_cali': true,
        'layer_inspect': false,
        'timelapse': false,
        'preheat_override': 'inherit',
      },
    );

    await repo.addFromArchive(
      77,
      printerId: 1,
      options: const QueueCreateOptions(
        amsMapping: [2, -1],
        manualStart: true,
        requirePreviousSuccess: false,
        autoOffAfter: false,
        bedLevelling: true,
        flowCali: false,
        vibrationCali: true,
        layerInspect: false,
        timelapse: false,
        preheatOverride: 'inherit',
      ),
    );
  });

  test('addFromLibraryFile z harmonogramem: scheduled_time i cel modelowy',
      () async {
    adapter.onPost(
      '/api/v1/queue/',
      (server) => server.reply(200, null),
      data: {
        'library_file_id': 12,
        'quantity': 1,
        'target_model': 'X2D',
        'target_location': 'Garage',
        'scheduled_time': '2026-07-28T20:00:00.000Z',
      },
    );

    await repo.addFromLibraryFile(
      12,
      options: const QueueCreateOptions(
        targetModel: 'X2D',
        targetLocation: 'Garage',
        scheduledTime: '2026-07-28T20:00:00.000Z',
      ),
    );
  });

  test('puste opcje nie dokładają nic do body', () async {
    // Null w [QueueCreateOptions] znaczy „nieustawione" — klucz ma NIE polecieć,
    // bo na tworzeniu nie ma czego czyścić, a serwer ma własne domyślne.
    adapter.onPost(
      '/api/v1/queue/',
      (server) => server.reply(200, null),
      data: {'archive_id': 77, 'printer_id': 1, 'quantity': 1},
    );

    await repo.addFromArchive(77,
        printerId: 1, options: const QueueCreateOptions());
  });
}
