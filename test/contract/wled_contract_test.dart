import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/wled_config.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';
import 'sent_writes.dart';

/// WLED on a printer (server #1528): the mapping the settings screen saves, the
/// three routes that reach WLED through the server, and — on a server without
/// them — that the printer row itself says so.
///
/// The WLED is `tool/ci/fake_wled.py` in a container of its own, addressed by
/// its bridge IP ([contractWledUrl]); without one those tests skip.
void main() {
  group('WLED contract', skip: contractSkipReason, () {
    late Dio dio;
    late PrintersRepository printers;
    late int printerId;
    late bool hasWled;

    /// What the printer row held before this file, put back afterwards.
    Object? before;

    setUpAll(() async {
      dio = await authenticatedDio();
      printers = PrintersRepository(dio);
      final rows = (await dio.get<List<dynamic>>(Endpoints.printers)).data!;
      final row = rows.first as Map<String, dynamic>;
      printerId = row['id'] as int;
      hasWled = row.containsKey('wled_config');
      before = row['wled_config'];
    });

    tearDownAll(() async {
      if (!hasWled) return;
      await dio.patch<dynamic>(
        Endpoints.printer(printerId),
        data: {'wled_config': before},
      );
    });

    Future<Response<dynamic>> post(String path, Map<String, Object?> body) =>
        dio.post<dynamic>(
          path,
          data: body,
          options: Options(validateStatus: (_) => true),
        );

    test('an older server is recognised from its own printer row', () async {
      if (hasWled) {
        markTestSkipped('server has WLED');
        return;
      }
      await printers.fetchPrinters();
      expect(printers.wledCapability.observedAnswer, isFalse);

      // The silent drop the gate exists for: 200, and nothing kept.
      await expectLater(
        printers.saveWledConfig(
          printerId,
          const WledConfig(enabled: true, baseUrl: 'http://192.168.1.50'),
        ),
        throwsA(isA<ApiException>()),
      );
      final presets = await post(Endpoints.printerWledPresets(printerId), {
        'base_url': 'http://192.168.1.50',
      });
      // 405 on 1.2.5, where a `GET` route takes the path.
      expect(presets.statusCode, anyOf(404, 405));
    });

    test('the mapping the screen saves is stored and read back', () async {
      if (!hasWled) {
        markTestSkipped('server predates WLED');
        return;
      }
      final [answer] = await replayWrites(
        dio,
        recordedWrites('wled_save'),
        item: printerId,
        itemIn: RegExp(r'(?<=/printers/)\d+'),
      );
      expect(answer.statusCode, 200, reason: '${answer.data}');

      final row = (await printers.fetchPrinters()).firstWhere(
        (p) => p.id == printerId,
      );
      final saved = row.wledConfig!;
      expect(saved.enabled, isTrue);
      expect(saved.baseUrl, 'http://192.168.1.50');
      expect(saved.presets, {
        WledState.idle: 1,
        WledState.printing: 5,
        WledState.paused: 2,
      });
      expect(saved.finishedTimeoutSeconds, 120);
      expect(printers.wledCapability.observedAnswer, isTrue);
    });

    test('a URL is normalised, and one with a login or none while enabled is '
        'refused with a reason', () async {
      if (!hasWled) {
        markTestSkipped('server predates WLED');
        return;
      }
      final saved = await printers.saveWledConfig(
        printerId,
        const WledConfig(enabled: true, baseUrl: ' http://192.168.1.50/ '),
      );
      expect(saved.wledConfig?.baseUrl, 'http://192.168.1.50');

      for (final (config, words) in const [
        (
          WledConfig(enabled: true, baseUrl: 'http://u:p@192.168.1.50'),
          'credentials',
        ),
        (WledConfig(enabled: true), 'base_url is required'),
        (WledConfig(enabled: true, baseUrl: 'ftp://192.168.1.50'), 'http'),
      ]) {
        await expectLater(
          printers.saveWledConfig(printerId, config),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'status', 422)
                .having((e) => e.detail, 'detail', contains(words)),
          ),
          reason: config.baseUrl,
        );
      }
    });

    test('a WLED that does not answer is a 502 on all three routes', () async {
      if (!hasWled) {
        markTestSkipped('server predates WLED');
        return;
      }
      // Port 1 on the server's own loopback: refused at once.
      const dead = 'http://127.0.0.1:1';
      for (final call in [
        () => printers.fetchWledPresets(printerId, dead),
        () => printers.testWledConnection(printerId, dead),
        () => printers.testWledPreset(printerId, dead, 1),
      ]) {
        await expectLater(
          call(),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', 502),
          ),
        );
      }
    });

    group('against a stand-in WLED', () {
      String? skip() => !hasWled
          ? 'server predates WLED'
          : (contractWledUrl ?? '').isEmpty
          ? 'BAMBUDDY_CONTRACT_WLED_URL is unset'
          : null;

      test('presets come back filtered, sorted and named', () async {
        if (skip() case final why?) return markTestSkipped(why);
        expect(await printers.fetchWledPresets(printerId, contractWledUrl!), [
          (id: 3, name: 'Printing green'),
          (id: 7, name: '7'),
        ]);
      });

      test('the connection test reads its name and version', () async {
        if (skip() case final why?) return markTestSkipped(why);
        expect(await printers.testWledConnection(printerId, contractWledUrl!), (
          name: 'Shelf strip',
          version: '0.15.1',
        ));
      });

      test('a preset test switches WLED to that preset', () async {
        if (skip() case final why?) return markTestSkipped(why);
        Future<List<dynamic>> switched() async =>
            (await Dio().get<List<dynamic>>(
              '$contractWledUrl/_switched',
            )).data!;
        final earlier = (await switched()).length;
        await printers.testWledPreset(printerId, contractWledUrl!, 3);
        expect((await switched()).skip(earlier), [
          {'ps': 3},
        ]);
      });
    });
  });
}
