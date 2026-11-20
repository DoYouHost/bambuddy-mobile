import 'package:bambuddy_mobile/core/api/server_version.dart';
import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// `move` on an assignment (server #1574): the spool leaves its old slot in the
/// same commit as it enters the new one. A server without the field takes it,
/// says nothing and leaves the spool in both slots — which is why the app asks
/// for it only from `ServerFeature.assignmentMove` on and clears the old slot
/// itself before that.
void main() {
  group('assignment move contract', skip: contractSkipReason, () {
    late Dio dio;
    late NativeInventorySource source;
    late int printerId;
    late int spoolId;
    late bool hasMove;

    SpoolAssignmentDraft draft(int trayId, {bool move = false}) =>
        SpoolAssignmentDraft(
          spoolId: spoolId,
          printerId: printerId,
          amsId: 0,
          trayId: trayId,
          move: move,
        );

    Future<Set<int>> heldTrays() async => {
      for (final a in await source.fetchAssignments(printerId: printerId))
        if (a.spoolId == spoolId) a.trayId,
    };

    setUpAll(() async {
      dio = await authenticatedDio();
      source = NativeInventorySource(dio);
      final printers = (await dio.get<List<dynamic>>(
        '/api/v1/printers/',
      )).data!;
      printerId = (printers.first as Map<String, dynamic>)['id'] as int;
      hasMove = (await contractServerVersion()).supports(
        ServerFeature.assignmentMove,
      );
    });

    setUp(() async {
      final spool = await source.createSpool(
        SpoolDraft(
          material: 'PLA',
          brand: 'Move ${DateTime.now().millisecondsSinceEpoch}',
          labelWeight: 1000,
        ),
      );
      spoolId = spool.id;
      await source.assignSpool(draft(2));
    });

    tearDown(() async {
      final quiet = Options(validateStatus: (_) => true);
      for (final tray in [2, 3]) {
        await dio.delete<dynamic>(
          Endpoints.inventoryAssignment(printerId, 0, tray),
          options: quiet,
        );
      }
      await dio.delete<dynamic>(
        Endpoints.inventorySpool(spoolId),
        options: quiet,
      );
    });

    test('a move leaves the spool in exactly the new slot', () async {
      if (!hasMove) {
        markTestSkipped('server has no `move`; the two-request path is used');
        return;
      }
      await source.assignSpool(draft(3, move: true));

      expect(await heldTrays(), {3});
    });

    test(
      'an unassign then an assign leaves it in exactly the new slot',
      () async {
        await source.unassignSpool(printerId, 0, 2);
        await source.assignSpool(draft(3));

        expect(await heldTrays(), {3});
      },
    );
  });
}
