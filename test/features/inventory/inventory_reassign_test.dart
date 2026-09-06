import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Moving a spool from one slot to another.
///
/// A move is two writes with no transaction behind them, so their order is the
/// whole design: the target is refused before the source is given up. On the
/// Spoolman backend a slot can genuinely refuse — it binds to the tag the slot
/// reads, and a slot with no readable tag has nothing to bind to — and unpinning
/// first would leave the spool in neither slot with nothing to undo it.
class _FakeSource implements SpoolInventorySource {
  _FakeSource({this.refusesTarget = false});

  /// Stands for a Spoolman slot the backend cannot write.
  final bool refusesTarget;

  final List<String> calls = [];

  @override
  Future<List<Spool>> fetchSpools({bool includeArchived = false}) async => [
    const Spool(id: 1, material: 'PLA'),
  ];

  @override
  Future<List<SpoolAssignment>> fetchAssignments({int? printerId}) async =>
      const [];

  @override
  Future<void> ensureAssignable(SpoolAssignmentDraft draft) async {
    calls.add('ensure');
    if (refusesTarget) {
      throw const ApiException(AppErrorCode.slotTagUnreadable);
    }
  }

  @override
  Future<void> assignSpool(SpoolAssignmentDraft draft) async =>
      calls.add('assign');

  @override
  Future<void> unassignSpool(int printerId, int amsId, int trayId) async =>
      calls.add('unassign');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _NativeBackend extends InventoryBackendNotifier {
  @override
  InventoryBackend build() => InventoryBackend.native;
}

void main() {
  Future<(ProviderContainer, _FakeSource)> harness(_FakeSource source) async {
    final container = ProviderContainer(
      overrides: [
        fakeServerProfileOverride(),
        inventoryBackendProvider.overrideWith(_NativeBackend.new),
        inventorySourceProvider.overrideWithValue(source),
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

  test('a move clears the target before giving up the source', () async {
    final (container, source) = await harness(_FakeSource());

    await container
        .read(inventoryProvider.notifier)
        .assignSpool(to, from: from);

    expect(source.calls, ['ensure', 'unassign', 'assign']);
  });

  test('a refused target leaves the spool where it was', () async {
    final (container, source) = await harness(_FakeSource(refusesTarget: true));

    // The refusal reaches the screen, which is what puts the reason in front of
    // the user instead of a silent no-op.
    await expectLater(
      container.read(inventoryProvider.notifier).assignSpool(to, from: from),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          AppErrorCode.slotTagUnreadable,
        ),
      ),
    );

    expect(
      source.calls,
      ['ensure'],
      reason: 'the source slot must not be unpinned for a move that failed',
    );
  });

  // Assigning into a free slot is one write, so there is nothing to lose and
  // nothing to check first.
  test('a plain assign asks nothing beforehand', () async {
    final (container, source) = await harness(_FakeSource());

    await container.read(inventoryProvider.notifier).assignSpool(to);

    expect(source.calls, ['assign']);
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

      expect(source.calls, ['assign']);
    },
  );
}
