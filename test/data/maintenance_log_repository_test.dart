import 'dart:convert';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/maintenance.dart';
import 'package:bambuddy_mobile/data/maintenance_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

/// The log of resets (server #3557): `GET/DELETE /maintenance/printers/{id}/log`,
/// the two CSV exports and the delete of one entry.
void main() {
  late Dio dio;
  late DioAdapter adapter;
  late MaintenanceRepository repo;

  setUp(() {
    dio = testDio();
    adapter = mockServer(dio);
    repo = MaintenanceRepository(dio);
  });

  Map<String, Object?> entry(int id, {Map<String, Object?> extra = const {}}) =>
      {
        'id': id,
        'printer_id': 4,
        'printer_name': 'X2D-3DP',
        'maintenance_type_id': 2,
        'maintenance_type_name': 'Lubricate rods',
        'hours_at_maintenance': 123.4,
        'notes': null,
        'performed_by_id': 1,
        'performed_by_username': 'morgan',
        'performed_at': '2026-11-20T08:30:00',
        ...extra,
      };

  group('the entry', () {
    test('reads what the server keeps, the time as UTC without a Z', () {
      final e = MaintenanceLogEntry.fromJson(entry(7));

      expect(e.id, 7);
      expect(e.printerName, 'X2D-3DP');
      expect(e.maintenanceTypeName, 'Lubricate rods');
      expect(e.hoursAtMaintenance, 123.4);
      expect(e.performedByUsername, 'morgan');
      expect(e.performedAtDate!.toUtc(), DateTime.utc(2026, 11, 20, 8, 30));
    });

    test('a deleted printer and task leave their ids null and the names', () {
      final e = MaintenanceLogEntry.fromJson(
        entry(
          8,
          extra: {
            'printer_id': null,
            'maintenance_type_id': null,
            'performed_by_id': null,
            'performed_by_username': null,
          },
        ),
      );

      expect(e.printerId, isNull);
      expect(e.maintenanceTypeId, isNull);
      expect(e.printerName, 'X2D-3DP');
      expect(e.performedByUsername, isNull);
    });

    test('missing and odd fields do not break it', () {
      final e = MaintenanceLogEntry.fromJson({
        'id': 9,
        'hours_at_maintenance': 12,
        'performed_at': 'garbage',
      });

      expect(e.printerName, '');
      expect(e.maintenanceTypeName, '');
      expect(e.hoursAtMaintenance, 12.0);
      expect(e.performedAtDate, isNull);
    });
  });

  group('fetchLog', () {
    test('asks for a page and reads the items and the total', () async {
      adapter.onGet(
        '/api/v1/maintenance/printers/4/log',
        (s) => s.reply(200, {
          'items': [entry(2), entry(1)],
          'total': 5,
        }),
        queryParameters: {'limit': 50, 'offset': 0},
      );

      final page = await repo.fetchLog(4);

      expect(page.items.map((e) => e.id), [2, 1]);
      expect(page.total, 5);
    });

    test('the next page starts where the loaded rows end', () async {
      adapter.onGet(
        '/api/v1/maintenance/printers/4/log',
        (s) => s.reply(200, {
          'items': [entry(1)],
          'total': 51,
        }),
        queryParameters: {'limit': 50, 'offset': 50},
      );

      final page = await repo.fetchLog(4, offset: 50);

      expect(page.items, hasLength(1));
    });

    test('an empty log is an empty page', () async {
      adapter.onGet(
        '/api/v1/maintenance/printers/4/log',
        (s) => s.reply(200, {'items': [], 'total': 0}),
        queryParameters: {'limit': 50, 'offset': 0},
      );

      final page = await repo.fetchLog(4);

      expect(page.items, isEmpty);
      expect(page.total, 0);
    });

    test(
      'a row that does not parse is dropped, the total is the server\'s',
      () async {
        adapter.onGet(
          '/api/v1/maintenance/printers/4/log',
          (s) => s.reply(200, {
            'items': [
              entry(1),
              'junk',
              {'printer_name': 'no id'},
            ],
            'total': 3,
          }),
          queryParameters: {'limit': 50, 'offset': 0},
        );

        final page = await repo.fetchLog(4);

        expect(page.items.map((e) => e.id), [1]);
        expect(page.total, 3);
        expect(
          page.received,
          3,
          reason: 'the next page starts after what was sent',
        );
      },
    );

    test('an answer that is not a page is an error', () async {
      adapter.onGet(
        '/api/v1/maintenance/printers/4/log',
        (s) => s.reply(200, ['not', 'a', 'page']),
        queryParameters: {'limit': 50, 'offset': 0},
      );

      await expectLater(
        repo.fetchLog(4),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.badResponse,
          ),
        ),
      );
    });

    test('a printer that is gone is a 404', () async {
      adapter.onGet(
        '/api/v1/maintenance/printers/4/log',
        (s) => s.reply(404, {'detail': 'Printer not found'}),
        queryParameters: {'limit': 50, 'offset': 0},
      );

      await expectLater(repo.fetchLog(4), throwsA(isA<AppApiException>()));
    });
  });

  group('exportLog', () {
    test(
      'a printer\'s export comes with the name the server gave it',
      () async {
        adapter.onGet(
          '/api/v1/maintenance/printers/4/log/export',
          (s) => s.reply(
            200,
            utf8.encode('\u{feff}Performed at (UTC),Printer\n'),
            headers: {
              'content-disposition': [
                "attachment; filename=\"maintenance_log_X2D_20261120.csv\"; "
                    "filename*=UTF-8''maintenance_log_X2D_20261120.csv",
              ],
            },
          ),
        );

        final file = await repo.exportLog(printerId: 4);

        expect(file.filename, 'maintenance_log_X2D_20261120.csv');
        // The BOM is what makes Excel read the file as UTF-8; it must survive.
        expect(file.bytes.take(3), [0xEF, 0xBB, 0xBF]);
        expect(utf8.decode(file.bytes), startsWith('Performed at'));
      },
    );

    test('without a printer it is the fleet\'s, and a header-less answer gets '
        'a plain name', () async {
      adapter.onGet(
        '/api/v1/maintenance/log/export',
        (s) => s.reply(200, utf8.encode('a,b\n')),
      );

      final file = await repo.exportLog();

      expect(file.filename, 'maintenance-log.csv');
      expect(file.bytes, isNotEmpty);
    });

    test('a refused export throws', () async {
      adapter.onGet(
        '/api/v1/maintenance/log/export',
        (s) => s.reply(403, {'detail': 'no'}),
      );

      await expectLater(repo.exportLog(), throwsA(isA<AppApiException>()));
    });
  });

  group('cleanUpLog', () {
    test(
      'a printer\'s cleanup sends the age and reads how many went',
      () async {
        adapter.onDelete(
          '/api/v1/maintenance/printers/4/log',
          (s) => s.reply(200, {'deleted': 3}),
          queryParameters: {'older_than_days': 90},
        );

        expect(await repo.cleanUpLog(olderThanDays: 90, printerId: 4), 3);
      },
    );

    test('without a printer it is the fleet\'s route', () async {
      adapter.onDelete(
        '/api/v1/maintenance/log',
        (s) => s.reply(200, {'deleted': 0}),
        queryParameters: {'older_than_days': 1},
      );

      expect(await repo.cleanUpLog(olderThanDays: 1), 0);
    });

    test('an odd answer reads as none deleted', () async {
      adapter.onDelete(
        '/api/v1/maintenance/log',
        (s) => s.reply(200, 'ok'),
        queryParameters: {'older_than_days': 30},
      );

      expect(await repo.cleanUpLog(olderThanDays: 30), 0);
    });

    test('a 403 is a refusal, not an outage', () async {
      adapter.onDelete(
        '/api/v1/maintenance/log',
        (s) => s.reply(403, {'detail': 'no'}),
        queryParameters: {'older_than_days': 30},
      );

      await expectLater(
        repo.cleanUpLog(olderThanDays: 30),
        throwsA(
          isA<AuthException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.forbidden,
          ),
        ),
      );
    });
  });

  group('deleteLogEntry', () {
    test('deletes one entry by id', () async {
      adapter.onDelete(
        '/api/v1/maintenance/log/12',
        (s) => s.reply(200, {'status': 'deleted', 'id': 12}),
      );
      final sent = captureRequests(dio);

      await repo.deleteLogEntry(12);

      expect(sent.calls, ['DELETE /api/v1/maintenance/log/12']);
    });

    test('an entry that is gone is a 404', () async {
      adapter.onDelete(
        '/api/v1/maintenance/log/12',
        (s) => s.reply(404, {'detail': 'Maintenance log entry not found'}),
      );

      await expectLater(
        repo.deleteLogEntry(12),
        throwsA(isA<AppApiException>()),
      );
    });
  });
}
