import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/ai_detection.dart';
import 'package:bambuddy_mobile/data/ai_detection_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

const _obico = '/api/v1/obico/printer-status';
const _octoEverywhere = '/api/v1/octoeverywhere/printer-status';

Map<String, dynamic> _status({
  bool enabled = true,
  List<int>? monitored,
  Map<String, dynamic> perPrinter = const {},
}) => {
  'enabled': enabled,
  'monitored_printers': monitored,
  'per_printer': perPrinter,
  'last_error': null,
};

void main() {
  final dio = testDio();
  final server = mockServer(dio);
  final repo = AiDetectionRepository(dio);

  void notFound(String path) =>
      server.onGet(path, (s) => s.reply(404, {'detail': 'Not Found'}));

  group('which provider answers', () {
    test('OctoEverywhere when it is enabled', () async {
      server.onGet(
        _octoEverywhere,
        (s) => s.reply(
          200,
          _status(
            perPrinter: {
              '1': {'class': 'safe', 'frame_count': 4, 'print_quality': 8},
            },
          ),
        ),
      );
      server.onGet(_obico, (s) => s.reply(200, _status(enabled: false)));

      final status = await repo.fetch();
      expect(status!.detectionFor(1)!.printQuality, 8);
    });

    test('Obico when OctoEverywhere is off', () async {
      server.onGet(
        _octoEverywhere,
        (s) => s.reply(200, _status(enabled: false)),
      );
      server.onGet(
        _obico,
        (s) => s.reply(
          200,
          _status(
            perPrinter: {
              '2': {'class': 'warning', 'frame_count': 9, 'score': 0.4312},
            },
          ),
        ),
      );

      final entry = (await repo.fetch())!.detectionFor(2)!;
      expect(entry.cls, AiDetectionClass.warning);
      expect(entry.score, 0.4312);
      expect(entry.ratesQuality, isFalse);
    });

    test('Obico on a server from before OctoEverywhere', () async {
      notFound(_octoEverywhere);
      server.onGet(
        _obico,
        (s) => s.reply(
          200,
          _status(
            perPrinter: {
              '1': {'class': 'safe', 'frame_count': 1, 'score': 0},
            },
          ),
        ),
      );
      expect((await repo.fetch())!.detectionFor(1)!.cls, AiDetectionClass.safe);
    });

    test('nothing on a server with neither route', () async {
      notFound(_octoEverywhere);
      notFound(_obico);
      expect(await repo.fetch(), isNull);
    });

    test('nothing for a session the server refuses', () async {
      for (final path in [_octoEverywhere, _obico]) {
        server.onGet(path, (s) => s.reply(403, {'detail': 'Forbidden'}));
      }
      expect(await repo.fetch(), isNull);
    });

    test('both off is a status that is off', () async {
      for (final path in [_octoEverywhere, _obico]) {
        server.onGet(path, (s) => s.reply(200, _status(enabled: false)));
      }
      expect((await repo.fetch())!.enabled, isFalse);
    });

    test('a server error is still an error', () async {
      server.onGet(_octoEverywhere, (s) => s.reply(500, null));
      await expectLater(repo.fetch(), throwsA(isA<AppApiException>()));
    });
  });

  group('AiDetectionStatus', () {
    AiDetectionStatus parse(Map<String, dynamic> json) =>
        AiDetectionStatus.fromJson(json);

    const safe = {'class': 'safe', 'frame_count': 1, 'score': 0.01};

    test('an entry shows only while detection is enabled', () {
      final off = parse(_status(enabled: false, perPrinter: {'1': safe}));
      expect(off.detectionFor(1), isNull);
    });

    test('an entry shows only for a printer in the monitored set', () {
      final status = parse(
        _status(monitored: [2], perPrinter: {'1': safe, '2': safe}),
      );
      expect(status.detectionFor(1), isNull);
      expect(status.detectionFor(2), isNotNull);
    });

    test('no monitored set means every printer', () {
      final status = parse(_status(perPrinter: {'1': safe}));
      expect(status.detectionFor(1), isNotNull);
    });

    test('a monitored printer without a running print has no entry', () {
      expect(parse(_status(monitored: [1])).detectionFor(1), isNull);
    });

    test('a class this app does not know is unknown, never safe', () {
      final status = parse(
        _status(
          perPrinter: {
            '1': {'class': 'paused', 'frame_count': 0},
            '2': <String, dynamic>{},
          },
        ),
      );
      expect(status.detectionFor(1)!.cls, AiDetectionClass.unknown);
      expect(status.detectionFor(2)!.cls, AiDetectionClass.unknown);
    });

    test('OctoEverywhere before its first result rates quality as null', () {
      final entry = parse(
        _status(
          perPrinter: {
            '1': {
              'class': 'unknown',
              'frame_count': 0,
              'print_quality': null,
              'error': null,
              'error_code': null,
            },
          },
        ),
      ).detectionFor(1)!;
      expect(entry.ratesQuality, isTrue);
      expect(entry.printQuality, isNull);
    });

    test('the usage limit is read off the error code', () {
      final entry = parse(
        _status(
          perPrinter: {
            '1': {
              'class': 'error',
              'frame_count': 3,
              'print_quality': null,
              'error': 'Usage limit reached.',
              'error_code': 'OE_FREE_USAGE_LIMIT_REACHED',
            },
          },
        ),
      ).detectionFor(1)!;
      expect(entry.cls, AiDetectionClass.error);
      expect(entry.usageLimitReached, isTrue);
    });

    test('odd envelopes parse to nothing instead of throwing', () {
      final status = parse({
        'enabled': 'yes',
        'monitored_printers': 'all',
        'per_printer': {'x': safe, '3': 'junk', '4': safe},
      });
      expect(status.enabled, isFalse);
      expect(status.monitoredPrinters, isNull);
      expect(status.perPrinter.keys, [4]);
      expect(parse(const {}).perPrinter, isEmpty);
    });
  });
}
