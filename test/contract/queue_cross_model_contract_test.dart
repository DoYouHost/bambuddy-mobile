import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/data/library_repository.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// A job with alternatives (#671) picks its printer at dispatch. The server
/// refuses a printer put on it, so the queue screen's Start releases it with a
/// bare `/start`, as the web does. Servers before #671 have no alternatives and
/// skip.
void main() {
  group('queue cross-model contract', skip: contractSkipReason, () {
    late Dio dio;
    late QueueRepository queue;
    late int seededFileId;
    late int otherFileId;
    late int printerId;

    setUpAll(() async {
      dio = await authenticatedDio();
      queue = QueueRepository(dio);
      final library = LibraryRepository(dio);
      final seeded = (await library.listFiles()).firstWhere(
        (f) => f.filename == 'contract-probe.3mf',
      );
      seededFileId = seeded.id;
      final bytes = (await dio.get<List<int>>(
        '${Endpoints.libraryFile(seeded.id)}/download',
        options: Options(responseType: ResponseType.bytes),
      )).data!;
      final uploaded = await dio.post<Map<String, dynamic>>(
        Endpoints.libraryFiles,
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: 'cross-model.3mf'),
        }),
      );
      otherFileId = uploaded.data!['id'] as int;
      printerId =
          (await dio.get<List<dynamic>>(
                Endpoints.printers,
              )).data!.cast<Map<String, dynamic>>().first['id']
              as int;
    });

    tearDownAll(() => LibraryRepository(dio).deleteFile(otherFileId));

    test('Start releases it; putting a printer on it is refused', () async {
      final created = await dio.post<Map<String, dynamic>>(
        Endpoints.queue,
        data: {
          'variants': [
            {'library_file_id': seededFileId, 'target_model': 'X1C'},
            {'library_file_id': otherFileId, 'target_model': 'P1S'},
          ],
          'manual_start': true,
        },
        options: Options(validateStatus: (_) => true),
      );
      // An older server refuses a job with neither file nor archive.
      if (created.statusCode != 200) {
        markTestSkipped('server has no cross-model jobs (#671)');
        return;
      }
      final id = created.data!['id'] as int;
      addTearDown(() => queue.delete(id));
      // The create answer carries `variants: []` even for a job that has them
      // (measured on daily); only a read shows them.
      final item = (await queue.fetch(
        status: 'pending',
      )).firstWhere((q) => q.id == id);
      expect(item.isCrossModel, isTrue);

      await expectLater(
        queue.assignPrinter(item.id, printerId),
        throwsA(
          isA<AppApiException>().having((e) => e.statusCode, 'status', 400),
        ),
      );

      await queue.start(item.id);
      final after = (await queue.fetch(
        status: 'pending',
      )).firstWhere((q) => q.id == item.id);
      expect(after.printerId, isNull, reason: 'the scheduler picks it');
      expect(after.manualStart, isFalse, reason: 'released');
    });
  });
}
