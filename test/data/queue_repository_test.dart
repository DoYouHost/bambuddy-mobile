import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/models/calibration_option.dart';
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

  test('fetch: odpowiedź serwera 1.2.5 nie gubi ani jednego rekordu', () async {
    // To jest ten pusty ekran ze zgłoszenia: trzy pola kalibracji przyszły jako
    // stringi, generowany rzut na bool rzucał na KAŻDYM rekordzie i lista
    // wychodziła pusta przy statusie 200.
    final payload = readFixture('queue_list_tristate.json') as List<dynamic>;
    adapter.onGet('/api/v1/queue/', (server) => server.reply(200, payload));

    final items = await repo.fetch();

    expect(items, hasLength(payload.length));
    expect(items.map((i) => i.bedLevelling),
        [CalibrationOption.off, CalibrationOption.auto]);
    expect(items.map((i) => i.nozzleOffsetCali),
        [CalibrationOption.auto, CalibrationOption.off]);
    expect(items.where((i) => i.isActive), hasLength(2),
        reason: 'pending + printing — ekran kolejki ma co pokazać');
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
        bedLevelling: CalibrationOption.on,
        flowCali: CalibrationOption.off,
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

  group('kalibracje na zapisie', () {
    /// Repozytorium pytające podstawiony serwer o wersję.
    QueueRepository repoFor(String version) {
      adapter.onGet(
        '/api/v1/updates/version',
        (server) => server.reply(200, {'version': version, 'repo': 'x/y'}),
      );
      return QueueRepository(dio, ServerVersionService(dio));
    }

    test('on/off zawsze booleanem — również na serwerze 1.2.5', () async {
      adapter.onPost(
        '/api/v1/queue/',
        (server) => server.reply(200, null),
        data: {
          'archive_id': 77,
          'quantity': 1,
          'bed_levelling': true,
          'flow_cali': false,
        },
      );

      await repoFor('1.2.5.1').addFromArchive(
        77,
        options: const QueueCreateOptions(
          bedLevelling: CalibrationOption.on,
          flowCali: CalibrationOption.off,
        ),
      );
    });

    test('auto leci jako string na serwer, który to umie', () async {
      adapter.onPost(
        '/api/v1/queue/',
        (server) => server.reply(200, null),
        data: {
          'archive_id': 77,
          'quantity': 1,
          'bed_levelling': 'auto',
        },
      );

      await repoFor('1.2.5.1').addFromArchive(
        77,
        options: const QueueCreateOptions(bedLevelling: CalibrationOption.auto),
      );
    });

    test('tworzenie: auto na starym serwerze idzie tak, jak pokazał formularz',
        () async {
      // `auto` trafia tu tylko jako wybór zapamiętany z nowszego serwera. Stary
      // nie ma go gdzie zapisać, a formularz pokazuje wtedy przełącznik
      // dwustanowy w pozycji ON — więc ON ma pojechać. Pominięcie klucza
      // oddawało decyzję serwerowi, a jego domyślna dla `flow_cali` to `false`,
      // czyli ekran mówił co innego, niż się zapisywało.
      adapter.onPost(
        '/api/v1/queue/',
        (server) => server.reply(200, null),
        data: {
          'archive_id': 77,
          'quantity': 1,
          'bed_levelling': true,
          'flow_cali': true,
        },
      );

      await repoFor('0.2.4.9').addFromArchive(
        77,
        options: const QueueCreateOptions(
          bedLevelling: CalibrationOption.auto,
          flowCali: CalibrationOption.auto,
        ),
      );
    });

    test('edycja: auto na starym serwerze nadal wypada z body', () async {
      // Odwrotnie niż przy tworzeniu: tu JEST zapisana wartość do ochrony.
      // Wysłanie booleana przepisałoby userowi auto na on/off w polu, którego
      // mógł nie tknąć.
      adapter.onPatch(
        '/api/v1/queue/9',
        (server) => server.reply(200, null),
        data: {'flow_cali': false},
      );

      await repoFor('0.2.4.9').updateItem(
        9,
        bedLevelling: CalibrationOption.auto,
        flowCali: CalibrationOption.off,
      );
    });

    test('nieznana wersja zachowuje się jak starsza', () async {
      adapter.onGet(
        '/api/v1/updates/version',
        (server) => server.reply(500, null),
      );
      adapter.onPatch(
        '/api/v1/queue/9',
        (server) => server.reply(200, null),
        data: {'bed_levelling': true},
      );

      await QueueRepository(dio, ServerVersionService(dio)).updateItem(
        9,
        bedLevelling: CalibrationOption.on,
        nozzleOffsetCali: CalibrationOption.auto,
      );
    });

    test('nasz serwer 0.2.5b2: booleany potwierdzone zapytaniem na żywo',
        () async {
      // Sprawdzone 2026-07-30 curlem na własny serwer: `.[0].bed_levelling`
      // zwraca `true`. Czyli 0.2.5b2 jest PRZED zmianą na trójstan — numer
      // wersji dawał tę samą odpowiedź, ale przypadkiem, nie z dowodu.
      final repo = repoFor('0.2.5b2');
      adapter.onGet(
        '/api/v1/queue/',
        (server) => server.reply(200, [
          {'id': 1, 'position': 1, 'status': 'pending', 'bed_levelling': true},
        ]),
      );
      await repo.fetch();

      expect(await repo.supportsTriStateCalibration(), isFalse);
    });

    test('to, co serwer przysłał, bije numer wersji', () async {
      // Ten sam numer wersji, ale gdyby serwer wysyłał stringi — obserwacja ma
      // wygrać. Bramkowanie po numerze jest tu formalnie nierozstrzygalne:
      // 0.2.5b2 to beta tego samego cyklu, który wyszedł jako 1.2.5, a leży pod
      // nim w każdym porządku.
      final repo = repoFor('0.2.5b2');
      expect(await repo.supportsTriStateCalibration(), isFalse,
          reason: 'zanim cokolwiek zobaczy — ostrożnie');

      adapter.onGet(
        '/api/v1/queue/',
        (server) => server.reply(200, [
          {'id': 1, 'position': 1, 'status': 'pending', 'bed_levelling': 'auto'},
        ]),
      );
      await repo.fetch();

      expect(await repo.supportsTriStateCalibration(), isTrue,
          reason: 'stringi w odpowiedzi to dowód, nie poszlaka');
    });

    test('booleany w odpowiedzi trzymają nas przy starym kształcie', () async {
      // Odwrotny kierunek: serwer nazywa się 1.2.5, ale gdyby wysyłał booleany,
      // obserwacja też ma wygrać — nie wyślemy mu stringa.
      final repo = repoFor('1.2.5.1');
      adapter.onGet(
        '/api/v1/queue/',
        (server) => server.reply(200, [
          {'id': 1, 'position': 1, 'status': 'pending', 'bed_levelling': true},
        ]),
      );
      await repo.fetch();

      expect(await repo.supportsTriStateCalibration(), isFalse);
    });

    test('odpowiedź bez pól kalibracji nic nie ustala', () async {
      final repo = repoFor('1.2.5.1');
      adapter.onGet(
        '/api/v1/queue/',
        (server) => server.reply(200, [
          {'id': 1, 'position': 1, 'status': 'pending'},
        ]),
      );
      await repo.fetch();

      expect(await repo.supportsTriStateCalibration(), isTrue,
          reason: 'brak obserwacji → decyduje wersja');
    });

    test('po obserwacji auto jedzie na serwer 0.2.5b2', () async {
      final repo = repoFor('0.2.5b2');
      adapter
        ..onGet(
          '/api/v1/queue/',
          (server) => server.reply(200, [
            {
              'id': 1,
              'position': 1,
              'status': 'pending',
              'nozzle_offset_cali': 'auto',
            },
          ]),
        )
        ..onPatch(
          '/api/v1/queue/9',
          (server) => server.reply(200, null),
          data: {'bed_levelling': 'auto'},
        );

      await repo.fetch();
      await repo.updateItem(9, bedLevelling: CalibrationOption.auto);
    });

    test('bez serwisu wersji też działa — czytające wywołania go nie mają',
        () async {
      adapter.onPatch(
        '/api/v1/queue/9',
        (server) => server.reply(200, null),
        data: {'flow_cali': false},
      );

      await QueueRepository(dio).updateItem(
        9,
        flowCali: CalibrationOption.off,
        bedLevelling: CalibrationOption.auto,
      );
    });
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
