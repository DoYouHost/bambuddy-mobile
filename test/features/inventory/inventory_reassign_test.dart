import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Moving a spool from one slot to another: the old slot is cleared first,
/// since neither backend takes a spool off the slot it leaves on its own.
class _FakeSource implements SpoolInventorySource {
  _FakeSource({this.refusesTray});

  /// A tray whose assignment the server refuses.
  final int? refusesTray;

  final List<String> calls = [];

  @override
  Future<List<Spool>> fetchSpools({bool includeArchived = false}) async => [
    const Spool(id: 1, material: 'PLA'),
  ];

  @override
  Future<List<SpoolAssignment>> fetchAssignments({int? printerId}) async =>
      const [];

  @override
  Future<void> assignSpool(SpoolAssignmentDraft draft) async {
    calls.add('assign ${draft.trayId}');
    if (draft.trayId == refusesTray) {
      throw const ApiException(AppErrorCode.badResponse);
    }
  }

  @override
  Future<void> unassignSpool(int printerId, int amsId, int trayId) async =>
      calls.add('unassign');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  Future<(ProviderContainer, _FakeSource)> harness(_FakeSource source) async {
    final container = ProviderContainer(
      overrides: [
        fakeServerProfileOverride(),
        inventoryBackendOverride(),
        inventorySourceProvider.overrideWith((ref) => source),
      ],
    );
    addTearDown(container.dispose);
    container.listen(inventoryProvider, (_, _) {});
    await container.read(inventoryProvider.future);
    return (container, source);
  }

  const from = SpoolAssignment(spoolId: 1, printerId: 1, amsId: 0, trayId: 0);
  const to = SpoolAssignmentDraft(
    spoolId: 1,
    printerId: 1,
    amsId: 0,
    trayId: 2,
  );

  test('a move clears the old slot, then fills the new one', () async {
    final (container, source) = await harness(_FakeSource());

    await container
        .read(inventoryProvider.notifier)
        .assignSpool(to, from: from);

    expect(source.calls, ['unassign', 'assign 2']);
  });

  test('a move the new slot refuses puts the spool back', () async {
    final (container, source) = await harness(_FakeSource(refusesTray: 2));

    await expectLater(
      container.read(inventoryProvider.notifier).assignSpool(to, from: from),
      throwsA(isA<ApiException>()),
    );

    expect(source.calls, ['unassign', 'assign 2', 'assign 0']);
  });

  test('a plain assign is one write', () async {
    final (container, source) = await harness(_FakeSource());

    await container.read(inventoryProvider.notifier).assignSpool(to);

    expect(source.calls, ['assign 2']);
  });

  test(
    're-pinning a spool to the slot it already sits in is a plain assign',
    () async {
      final (container, source) = await harness(_FakeSource());

      await container
          .read(inventoryProvider.notifier)
          .assignSpool(
            const SpoolAssignmentDraft(
              spoolId: 1,
              printerId: 1,
              amsId: 0,
              trayId: 0,
            ),
            from: from,
          );

      expect(source.calls, ['assign 0']);
    },
  );
}
