import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/data/firmware_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late FirmwareRepository repo;

  setUp(() {
    dio = testDio();
    adapter = DioAdapter(dio: dio);
    repo = FirmwareRepository(dio);
  });

  test('fetchUpdates parsuje listę i flagę update_available', () async {
    adapter.onGet(
      '/api/v1/firmware/updates',
      (s) => s.reply(200, {
        'updates': [
          {
            'printer_id': 7,
            'printer_name': 'X2D',
            'model': 'X2D',
            'current_version': '01.02.03',
            'latest_version': '01.02.05',
            'update_available': true,
          },
          {
            'printer_id': 8,
            'current_version': '01.00.00',
            'latest_version': '01.00.00',
            'update_available': false,
          },
        ],
        'updates_available': 1,
      }),
    );

    final resp = await repo.fetchUpdates();
    expect(resp.updatesAvailable, 1);
    expect(resp.updates, hasLength(2));
    final first = resp.updates.first;
    expect(first.printerId, 7);
    expect(first.updateAvailable, isTrue);
    expect(first.latestVersion, '01.02.05');
    expect(first.hasVersion, isTrue);
    expect(resp.updates[1].updateAvailable, isFalse);
  });

  test('fetchUpdates pomija niesparsowalny wpis listy', () async {
    adapter.onGet(
      '/api/v1/firmware/updates',
      (s) => s.reply(200, {
        'updates': [
          {'printer_id': 1, 'current_version': '1.0'},
          'śmieć',
          42,
        ],
      }),
    );
    final resp = await repo.fetchUpdates();
    expect(resp.updates, hasLength(1));
    expect(resp.updates.single.printerId, 1);
  });

  test('fetchUpdates: brak pól → puste/bezpieczne wartości domyślne', () async {
    adapter.onGet('/api/v1/firmware/updates', (s) => s.reply(200, {}));
    final resp = await repo.fetchUpdates();
    expect(resp.updates, isEmpty);
    expect(resp.updatesAvailable, isNull);
  });

  test('fetchForPrinter parsuje pojedynczą drukarkę', () async {
    adapter.onGet(
      '/api/v1/firmware/updates/7',
      (s) => s.reply(200, {
        'printer_id': 7,
        'current_version': '01.02.03',
        'latest_version': '01.02.05',
        'update_available': true,
        'release_notes': 'Bug fixes',
        'available_versions': [
          {'version': '01.02.05', 'file_available': true},
        ],
      }),
    );
    final info = await repo.fetchForPrinter(7);
    expect(info, isNotNull);
    expect(info!.updateAvailable, isTrue);
    expect(info.releaseNotes, 'Bug fixes');
    expect(info.availableVersions, hasLength(1));
    expect(info.availableVersions!.single.fileAvailable, isTrue);
  });

  test('fetchForPrinter: błąd serwera degraduje się do null', () async {
    adapter.onGet(
      '/api/v1/firmware/updates/9',
      (s) => s.reply(500, {'detail': 'boom'}),
    );
    expect(await repo.fetchForPrinter(9), isNull);
  });

  test('fetchForPrinter: 401 wypływa jako AuthException', () async {
    adapter.onGet(
      '/api/v1/firmware/updates/7',
      (s) => s.reply(401, {'detail': 'unauthorized'}),
    );
    await expectLater(repo.fetchForPrinter(7), throwsA(isA<AuthException>()));
  });

  test('startUpload dokłada version w query i czyta started', () async {
    adapter.onPost(
      '/api/v1/firmware/updates/7/upload',
      (s) => s.reply(200, {'started': true, 'message': 'queued'}),
      queryParameters: {'version': '01.02.05'},
    );
    final res = await repo.startUpload(7, version: '01.02.05');
    expect(res.started, isTrue);
    expect(res.message, 'queued');
  });
}
