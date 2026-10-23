import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/data/archive_repository.dart';
import 'package:bambuddy_mobile/data/library_repository.dart';
import 'package:bambuddy_mobile/data/server_settings_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';
import 'sent_writes.dart';

/// The controller's Prints tab, button by button: what its widget tests
/// recorded (`test/fixtures/sent/`) sent to a live server, and what the server
/// made of it.
void main() {
  group('controller prints contract', skip: brokerSkipReason, () {
    late Dio dio;
    late int fileId;
    late int printerId;
    late String printerModel;

    setUpAll(() async {
      dio = await authenticatedDio();
      fileId = (await LibraryRepository(
        dio,
      ).listFiles()).firstWhere((f) => f.filename == 'contract-probe.3mf').id;
      final printer = (await dio.get<List<dynamic>>(
        Endpoints.printers,
      )).data!.cast<Map<String, dynamic>>().first;
      printerId = printer['id'] as int;
      printerModel = printer['model'] as String;
    });

    Future<Map<String, dynamic>> item(int id) async =>
        (await dio.get<Map<String, dynamic>>(Endpoints.queueItem(id))).data!;

    /// A job waiting for a manual start, removed with the test.
    Future<int> queued(Map<String, Object?> where) async {
      final id =
          (await dio.post<Map<String, dynamic>>(
                Endpoints.queue,
                data: {
                  'library_file_id': fileId,
                  'manual_start': true,
                  ...where,
                },
              )).data!['id']
              as int;
      addTearDown(
        () => dio.delete<dynamic>(
          Endpoints.queueItem(id),
          options: Options(validateStatus: (_) => true),
        ),
      );
      return id;
    }

    void expectAccepted(List<Response<dynamic>> answers) {
      for (final a in answers) {
        expect(
          a.statusCode,
          200,
          reason:
              '${a.requestOptions.method} ${a.requestOptions.path}: ${a.data}',
        );
      }
    }

    test('Start on a job pinned here maps it and releases it', () async {
      final id = await queued({'printer_id': printerId});
      final sent = recordedWrites('controller_start_pinned');

      expectAccepted(await replayWrites(dio, sent, item: id));

      final after = await item(id);
      expect(after['printer_id'], printerId);
      expect(after['ams_mapping'], (sent.first.body! as Map)['ams_mapping']);
      expect(after['manual_start'], isFalse, reason: 'released');
    });

    test('Start on a job for this model puts it on this printer', () async {
      final id = await queued({'target_model': printerModel});
      final sent = recordedWrites('controller_start_for_model');

      expectAccepted(
        await replayWrites(dio, sent, item: id, ids: {'printer_id': printerId}),
      );

      final after = await item(id);
      expect(after['printer_id'], printerId);
      expect(after['target_model'], isNull);
      expect(after['ams_mapping'], (sent[1].body! as Map)['ams_mapping']);
      expect(after['manual_start'], isFalse, reason: 'released');
    });

    test('Print again queues the archive as the screen sent it, on a '
        'dual-nozzle printer and a billing server', () async {
      final archives = ArchiveRepository(dio);
      final bytes = (await dio.get<List<int>>(
        '${Endpoints.libraryFile(fileId)}/download',
        options: Options(responseType: ResponseType.bytes),
      )).data!;
      final archiveId =
          (await dio.post<Map<String, dynamic>>(
                '${Endpoints.archives}upload',
                data: FormData.fromMap({
                  'file': MultipartFile.fromBytes(bytes, filename: 'again.3mf'),
                }),
              )).data!['id']
              as int;
      addTearDown(() => archives.delete(archiveId, purgeStats: true));
      final h2d =
          (await dio.post<Map<String, dynamic>>(
                Endpoints.printers,
                data: {
                  'name': 'Contract H2D',
                  'serial_number': '0948AD000000003',
                  'ip_address': contractBrokerIp,
                  'access_code': '12345678',
                  'model': 'H2D',
                },
              )).data!['id']
              as int;
      addTearDown(() => dio.delete<dynamic>(Endpoints.printer(h2d)));

      var sent = recordedWrites('controller_reprint_archive');
      final ids = <String, Object?>{'archive_id': archiveId, 'printer_id': h2d};
      final settings = ServerSettingsRepository(dio);
      if ((await settings.fetch()).containsKey('billing_enabled')) {
        await settings.update({'billing_enabled': true});
        addTearDown(() => settings.update({'billing_enabled': false}));
        final center =
            (await dio.post<Map<String, dynamic>>(
                  '/api/v1/finance/cost-centers',
                  data: {
                    'name':
                        'Controller ${DateTime.now().microsecondsSinceEpoch}',
                  },
                )).data!['id']
                as int;
        addTearDown(
          () => dio.delete<dynamic>(
            '/api/v1/finance/cost-centers/$center',
            options: Options(validateStatus: (_) => true),
          ),
        );
        ids['cost_center_id'] = center;
      } else {
        // Before billing (1.2.5.3) the app sends no centre: there is none.
        sent = [
          for (final w in sent)
            (
              method: w.method,
              path: w.path,
              body: {...w.body! as Map<String, dynamic>}
                ..remove('cost_center_id'),
            ),
        ];
      }

      final answers = await replayWrites(dio, sent, ids: ids);
      expectAccepted(answers);

      final after = await item(answers.single.data['id'] as int);
      addTearDown(() => dio.delete<dynamic>(Endpoints.queueItem(after['id'])));
      final body = {...sent.single.body! as Map<String, dynamic>, ...ids}
        // Instructions for the create, not fields of the job.
        ..remove('quantity')
        ..remove('insert_at_top');
      for (final MapEntry(:key, :value) in body.entries) {
        if (!after.containsKey(key)) continue;
        expect(after[key], _stored(value), reason: key);
      }
      expect(after['archive_id'], archiveId);
      expect(after['library_file_id'], isNull);
      expect(after['plate_id'], 2);
    });
  });
}

/// A tri-state option sent as a bool reads back as the server's word for it.
Object? _stored(Object? sent) => switch (sent) {
  true => anyOf(true, 'on'),
  false => anyOf(false, 'off'),
  _ => sent,
};
