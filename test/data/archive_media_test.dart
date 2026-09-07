import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/models/archive_media.dart';
import 'package:bambuddy_mobile/data/archive_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  group('ArchivePrinterMedia.fromJson', () {
    test('reads both halves of the answer', () {
      final media = ArchivePrinterMedia.fromJson(const {
        'archive_id': 7,
        'printer_id': 3,
        'local_timelapse': {'name': 'video.mp4', 'size': 1024},
        'remote_files': [
          {
            'name': 'video_1.mp4',
            'path': '/timelapse/video_1.mp4',
            'size': 2048,
            'kind': 'timelapse',
            'mtime': '2026-09-03T08:55:51',
          },
          {
            'name': 'ipcam_1.mp4',
            'path': '/ipcam/ipcam_1.mp4',
            'size': 512,
            'kind': 'ipcam',
          },
        ],
        'warnings': <String>[],
      });

      expect(media.printerId, 3);
      expect(media.localTimelapse?.name, 'video.mp4');
      expect(media.localTimelapse?.size, 1024);
      expect(media.localTimelapse?.kind, ArchiveMediaKind.timelapse);
      expect(media.remoteFiles.map((f) => f.path), [
        '/timelapse/video_1.mp4',
        '/ipcam/ipcam_1.mp4',
      ]);
      expect(media.remoteFiles.last.kind, ArchiveMediaKind.ipcam);
      expect(media.isEmpty, isFalse);
      // Through the shared coercer: a timestamp the server sends without its
      // `Z` is read as UTC and handed back local, so every consumer formats it
      // right without remembering to convert (`json_utils.dart`).
      expect(
        media.remoteFiles.first.recordedAt,
        DateTime.utc(2026, 9, 3, 8, 55, 51).toLocal(),
      );
      // Absent rather than guessed when the FTP listing carried none.
      expect(media.remoteFiles.last.recordedAt, isNull);
    });

    test('an answer with nothing in it reads as empty, not as a failure', () {
      final media = ArchivePrinterMedia.fromJson(const {
        'archive_id': 7,
        'printer_id': 3,
        'local_timelapse': null,
        'remote_files': <Object>[],
        'warnings': <String>[],
      });

      expect(media.isEmpty, isTrue);
      expect(media.warnings, isEmpty);
    });

    test('maps every warning the server names', () {
      final media = ArchivePrinterMedia.fromJson(const {
        'warnings': [
          'printer_files_forbidden',
          'printer_missing',
          'timelapse_unavailable',
          'ipcam_unavailable',
        ],
      });

      expect(media.warnings, {
        ArchiveMediaWarning.printerFilesForbidden,
        ArchiveMediaWarning.printerMissing,
        ArchiveMediaWarning.timelapseUnavailable,
        ArchiveMediaWarning.ipcamUnavailable,
      });
    });

    test('a warning this build has no sentence for is dropped', () {
      final media = ArchivePrinterMedia.fromJson(const {
        'warnings': ['ipcam_unavailable', 'something_newer'],
      });

      expect(media.warnings, {ArchiveMediaWarning.ipcamUnavailable});
    });

    test('a file with no path cannot be selected, so it is left out', () {
      // The path is the file's identity in the selection and what the download
      // job is started with. An entry without one would tick and then download
      // nothing.
      final media = ArchivePrinterMedia.fromJson(const {
        'remote_files': [
          {'name': 'orphan.mp4', 'size': 10},
          {'name': 'ok.mp4', 'path': '/ipcam/ok.mp4', 'size': 10},
        ],
      });

      expect(media.remoteFiles.map((f) => f.name), ['ok.mp4']);
    });

    test('an unsized entry keeps a zero rather than inventing a size', () {
      // The sheet sends sizes only when every one is real: the server spends
      // them on a free-space check, and a made-up figure passes a check that
      // then fails halfway through the transfer.
      final media = ArchivePrinterMedia.fromJson(const {
        'remote_files': [
          {'name': 'a.mp4', 'path': '/ipcam/a.mp4', 'size': null},
        ],
      });

      expect(media.remoteFiles.single.size, 0);
    });
  });

  group('ArchiveRepository printer media', () {
    late Dio dio;
    late DioAdapter adapter;
    late ArchiveRepository repo;

    setUp(() {
      dio = testDio();
      adapter = DioAdapter(dio: dio);
      repo = ArchiveRepository(dio);
    });

    test('a 404 offers nothing without taking the button away', () async {
      // The route 404s for an archive that is gone or not this caller's to see
      // (`archives.py::_ensure_archive_visible`) as well as on a server that
      // never had it, so it settles nothing — one purged archive used to take
      // the recordings button off every other card until the app restarted.
      //
      // Against a version that claims the route, or the second assertion would
      // pass on a repository that never asked anything.
      adapter.onGet(
        '/api/v1/updates/version',
        (s) => s.reply(200, {'version': '1.2.6b1', 'repo': 'x/y'}),
      );
      adapter.onGet(
        '/api/v1/archives/7/printer-media',
        (s) => s.reply(404, {'detail': 'Archive not found'}),
      );
      final versioned = ArchiveRepository(dio, ServerVersionService(dio));

      expect(await versioned.printerMedia(7), isNull);
      expect(await versioned.supportsPrinterMedia(), isTrue);
    });

    test('any other failure is a broken search, not an empty one', () async {
      adapter.onGet(
        '/api/v1/archives/7/printer-media',
        (s) => s.reply(500, {'detail': 'boom'}),
      );

      await expectLater(repo.printerMedia(7), throwsA(isA<AppApiException>()));
    });

    test('a 403 hides the route without recording it as absent', () async {
      adapter.onGet(
        '/api/v1/archives/7/printer-media',
        (s) => s.reply(403, {'detail': 'Forbidden'}),
      );

      await expectLater(repo.printerMedia(7), throwsA(isA<AppApiException>()));
      expect(await repo.supportsPrinterMedia(), isFalse);
    });

    test(
      'an answer settles the capability without a version service',
      () async {
        adapter.onGet(
          '/api/v1/archives/7/printer-media',
          (s) => s.reply(200, const {
            'archive_id': 7,
            'printer_id': 2,
            'remote_files': [
              {'name': 'a.mp4', 'path': '/ipcam/a.mp4', 'size': 10},
            ],
          }),
        );

        final media = await repo.printerMedia(7);

        expect(media?.remoteFiles, hasLength(1));
        expect(await repo.supportsPrinterMedia(), isTrue);
      },
    );
  });
}
