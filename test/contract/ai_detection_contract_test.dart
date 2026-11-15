import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/api_key.dart';
import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/data/ai_detection_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// The two `printer-status` routes the printer cards read (Obico since server
/// #1546, OctoEverywhere since 1.3.0). What is checked is the envelope, who may
/// read it and the switch between the providers. Whether the seeded print gets
/// an entry in time depends on the detection loop, so an entry of
/// `per_printer` is left to the repository's own tests against the shapes
/// `get_per_printer` builds.
void main() {
  group('AI failure detection contract', skip: contractSkipReason, () {
    late Dio dio;
    late AiDetectionRepository repo;
    late bool hasOctoEverywhere;
    late Map<String, dynamic> before;

    Future<Response<dynamic>> raw(Dio dio, String path) =>
        dio.get<dynamic>(path, options: Options(validateStatus: (_) => true));

    Future<void> patch(Map<String, dynamic> data) =>
        dio.put<dynamic>(Endpoints.appSettingsUpdate, data: data);

    setUpAll(() async {
      dio = await authenticatedDio();
      repo = AiDetectionRepository(dio);
      hasOctoEverywhere =
          (await raw(dio, Endpoints.octoEverywherePrinterStatus)).statusCode !=
          404;
      final settings = await dio.get<Map<String, dynamic>>(
        Endpoints.appSettings,
      );
      before = {
        for (final key in const ['obico_enabled', 'obico_enabled_printers'])
          key: settings.data![key],
      };
    });

    tearDownAll(() => patch(before));

    test('Obico sends the envelope the app reads', () async {
      final res = await raw(dio, Endpoints.obicoPrinterStatus);
      expect(res.statusCode, 200);
      final body = res.data as Map<String, dynamic>;
      expect(body['enabled'], isA<bool>());
      expect(body.containsKey('monitored_printers'), isTrue);
      expect(body['per_printer'], isA<Map<String, dynamic>>());
    });

    test(
      'OctoEverywhere sends the same envelope, or no route at all',
      () async {
        final res = await raw(dio, Endpoints.octoEverywherePrinterStatus);
        if (!hasOctoEverywhere) {
          expect(res.statusCode, 404);
          return;
        }
        expect(res.statusCode, 200);
        final body = res.data as Map<String, dynamic>;
        expect(body['enabled'], isA<bool>());
        expect(body.containsKey('monitored_printers'), isTrue);
        expect(body['per_printer'], isA<Map<String, dynamic>>());
      },
    );

    test(
      'switched off, the status reads as off on either generation',
      () async {
        await patch({'obico_enabled': false});
        final status = await repo.fetch();
        expect(status, isNotNull);
        expect(status!.enabled, isFalse);
        expect(status.detectionFor(1), isNull);
      },
    );

    test('Obico switched on for one printer is read with its printers', () async {
      // The server refuses an id that is no printer (`ensure_printers_exist`).
      final printers = await dio.get<List<dynamic>>(Endpoints.printers);
      final id = (printers.data!.first as Map<String, dynamic>)['id'] as int;
      await patch({'obico_enabled': true, 'obico_enabled_printers': '[$id]'});

      final status = (await repo.fetch())!;
      expect(status.enabled, isTrue);
      expect(status.monitoredPrinters, {id});
      // An entry exists only once the detection loop has seen a running print,
      // which is a matter of timing here; one for another printer never does.
      expect(status.perPrinter.keys.toSet().difference({id}), isEmpty);
    });

    test('Obico switched on for every printer has no monitored set', () async {
      await patch({'obico_enabled': true, 'obico_enabled_printers': ''});
      final status = (await repo.fetch())!;
      expect(status.enabled, isTrue);
      expect(status.monitoredPrinters, isNull);
    });

    test('printers:read is enough, without settings:read', () async {
      final viewer = await contractUser(dio, ['printers:read']);
      expect(await AiDetectionRepository(viewer.dio).fetch(), isNotNull);
    });

    test(
      'a user without printers:read is refused, and reads nothing',
      () async {
        final viewer = await contractUser(dio, [Permissions.queueCreate]);
        final res = await raw(viewer.dio, Endpoints.obicoPrinterStatus);
        expect(res.statusCode, 403);
        expect(await AiDetectionRepository(viewer.dio).fetch(), isNull);
      },
    );

    test('an API key with read-status reads it', () async {
      final asKey = AiDetectionRepository(
        await contractApiKeyDio(dio, {
          ApiKeyScope.readStatus,
        }, name: 'contract ai detection'),
      );
      expect(await asKey.fetch(), isNotNull);
    });
  });
}
