import 'dart:io';

import 'package:bambuddy_mobile/features/common/file_export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('downloadToCacheFile', () {
    late Directory cache;

    setUp(() async {
      cache = await Directory.systemTemp.createTemp('file-export');
      PathProviderPlatform.instance = TempDirProvider(cache.path);
    });

    tearDown(() async {
      if (cache.existsSync()) await cache.delete(recursive: true);
    });

    test('renames the scratch to the name the content type earns', () async {
      final file = await downloadToCacheFile(
        scratchName: 'timelapse-7.download',
        download: (savePath) async {
          await File(savePath).writeAsString('frames');
          return 'video/x-matroska';
        },
        name: (contentType) =>
            contentType == 'video/x-matroska' ? 'print.mkv' : 'print.mp4',
      );

      expect(file.path, '${cache.path}/print.mkv');
      expect(cache.listSync().map((e) => e.path), [file.path]);
    });

    test('an interrupted download takes its part-file with it', () async {
      // Nothing resumes one of these, so the bytes on disk are unreadable by
      // any path in the app — and the timelapse names its scratch per archive,
      // so left alone they accumulate one partial video each.
      await expectLater(
        downloadToCacheFile(
          scratchName: 'timelapse-7.download',
          download: (savePath) async {
            await File(savePath).writeAsString('half a video');
            throw const SocketException('connection reset');
          },
          name: (_) => 'print.mp4',
        ),
        throwsA(isA<SocketException>()),
      );

      expect(cache.listSync(), isEmpty);
    });

    test(
      'a download that fails before writing anything still reports why',
      () async {
        await expectLater(
          downloadToCacheFile(
            scratchName: 'timelapse-7.download',
            download: (_) async => throw const SocketException('refused'),
            name: (_) => 'print.mp4',
          ),
          throwsA(isA<SocketException>()),
        );

        expect(cache.listSync(), isEmpty);
      },
    );

    test('replaces an earlier file of the same name', () async {
      await File('${cache.path}/print.mp4').writeAsString('an older take');

      final file = await downloadToCacheFile(
        scratchName: 'timelapse-7.download',
        download: (savePath) async {
          await File(savePath).writeAsString('the new one');
          return null;
        },
        name: (_) => 'print.mp4',
      );

      expect(await file.readAsString(), 'the new one');
      expect(cache.listSync(), hasLength(1));
    });
  });

  group('discardCacheCopy', () {
    test('a copy that is already gone is the outcome, not an error', () async {
      final dir = await Directory.systemTemp.createTemp('file-export-gone');
      final missing = File('${dir.path}/never-existed.mp4');

      await expectLater(discardCacheCopy(missing), completes);

      await dir.delete(recursive: true);
    });
  });

  group('mimeTypeForFileName', () {
    test('names the kinds a printer stores', () {
      expect(mimeTypeForFileName('Benchy.3mf'), 'model/3mf');
      expect(mimeTypeForFileName('plate_1.gcode'), 'text/x.gcode');
      expect(mimeTypeForFileName('Ultron-files.zip'), 'application/zip');
    });

    test('reads the last extension, not the first', () {
      expect(mimeTypeForFileName('Benchy.gcode.3mf'), 'model/3mf');
    });

    test('is case-insensitive, because the printer is not consistent', () {
      expect(mimeTypeForFileName('COVER.PNG'), 'image/png');
    });

    test('leaves the guess to the platform for anything else', () {
      // Null rather than octet-stream: some share targets refuse that outright,
      // and the platform's own guess from the extension is a better answer.
      expect(mimeTypeForFileName('cache.bin'), isNull);
      expect(mimeTypeForFileName('noextension'), isNull);
      expect(mimeTypeForFileName(''), isNull);
    });
  });
}
