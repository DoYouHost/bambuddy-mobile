import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Moving a spool from one slot to another: on a server without `move` the old
/// slot is cleared first, since neither backend takes a spool off the slot it
/// leaves on its own; with it the move is the one request.
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
    calls.add('assign ${draft.trayId}${draft.move ? ' move' : ''}');
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
  late RecordingCommands commands;

  Future<(ProviderContainer, _FakeSource)> harness(
    _FakeSource source, {
    bool atomicMove = false,
  }) async {
    final container = ProviderContainer(
      retry: neverRetry,
      overrides: [
        assignmentMoveProvider.overrideWithValue(AsyncData(atomicMove)),
        fakeServerProfileOverride(),
        inventoryBackendOverride(),
        inventorySourceProvider.overrideWith((ref) => source),
        printerCommandsRepositoryProvider.overrideWithValue(
          commands = RecordingCommands(),
        ),
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

  test('a move on a server with `move` is one request', () async {
    final (container, source) = await harness(_FakeSource(), atomicMove: true);

    await container
        .read(inventoryProvider.notifier)
        .assignSpool(to, from: from);

    expect(source.calls, ['assign 2 move']);
    expect(commands.calls, ['refreshStatus:1']);
  });

  test('an atomic move to another printer nudges both printers', () async {
    final (container, source) = await harness(_FakeSource(), atomicMove: true);

    await container
        .read(inventoryProvider.notifier)
        .assignSpool(
          const SpoolAssignmentDraft(
            spoolId: 1,
            printerId: 2,
            amsId: 0,
            trayId: 0,
          ),
          from: from,
        );

    expect(source.calls, ['assign 0 move']);
    expect(commands.calls, ['refreshStatus:2', 'refreshStatus:1']);
  });

  test('an atomic move the new slot refuses is not retried', () async {
    final (container, source) = await harness(
      _FakeSource(refusesTray: 2),
      atomicMove: true,
    );

    await expectLater(
      container.read(inventoryProvider.notifier).assignSpool(to, from: from),
      throwsA(isA<ApiException>()),
    );

    // The server kept the spool in its old slot, so no put-back is sent.
    expect(source.calls, ['assign 2 move']);
    expect(commands.calls, isEmpty);
  });

  test('a plain assign never asks for a move, even on a new server', () async {
    final (container, source) = await harness(_FakeSource(), atomicMove: true);

    await container.read(inventoryProvider.notifier).assignSpool(to);

    expect(source.calls, ['assign 2']);
  });

  test('a move the new slot refuses puts the spool back', () async {
    final (container, source) = await harness(_FakeSource(refusesTray: 2));

    await expectLater(
      container.read(inventoryProvider.notifier).assignSpool(to, from: from),
      throwsA(isA<ApiException>()),
    );

    expect(source.calls, ['unassign', 'assign 2', 'assign 0']);
    expect(commands.calls, ['refreshStatus:1']);
  });

  test('a move to another printer nudges both printers', () async {
    final (container, _) = await harness(_FakeSource());

    await container
        .read(inventoryProvider.notifier)
        .assignSpool(
          const SpoolAssignmentDraft(
            spoolId: 1,
            printerId: 2,
            amsId: 0,
            trayId: 0,
          ),
          from: from,
        );

    // Neither firmware echoes the change back on its own: the one the spool
    // left keeps showing it until told to speak.
    expect(commands.calls, ['refreshStatus:2', 'refreshStatus:1']);
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
