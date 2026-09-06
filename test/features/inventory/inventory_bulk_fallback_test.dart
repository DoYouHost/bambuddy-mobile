import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/inventory_bulk.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// What the multi-select actions do against a server that has the bulk routes
/// and against one that does not. The routes arrived in 0.2.5b1 and report an
/// unknown id in the body, so a 404 identifies the older server — and the app
/// is published against servers the maintainer does not control, so the
/// per-spool path has to keep working there.
class _FakeSource implements SpoolInventorySource {
  _FakeSource({this.bulkFailure, this.failingSpoolIds = const {}});

  /// Thrown by every bulk call, to stand for a server that answers 404 (no
  /// such route) or 403 (a key without `filaments:update`).
  final AppApiException? bulkFailure;

  /// Ids whose per-spool call fails, for the fallback's own tally.
  final Set<int> failingSpoolIds;

  final List<List<int>> bulkCalls = [];
  final List<int> perSpoolCalls = [];
  int loads = 0;

  @override
  Future<List<Spool>> fetchSpools({bool includeArchived = false}) async {
    loads++;
    // Growable: the notifier sorts the shelf in place.
    return [const Spool(id: 1, material: 'PLA')];
  }

  @override
  Future<List<SpoolAssignment>> fetchAssignments({int? printerId}) async =>
      const [];

  @override
  Future<void> ensureAssignable(SpoolAssignmentDraft draft) async {}

  @override
  Future<BulkOutcome> bulkArchive(List<int> spoolIds) async {
    bulkCalls.add(spoolIds);
    if (bulkFailure case final failure?) throw failure;
    return BulkOutcome(ok: spoolIds.length);
  }

  @override
  Future<void> archiveSpool(int spoolId) async {
    perSpoolCalls.add(spoolId);
    if (failingSpoolIds.contains(spoolId)) {
      throw const ApiException(AppErrorCode.badResponse, statusCode: 500);
    }
  }

  // Everything else is out of this test's way. Reaching one of them is a bug
  // in the notifier, and an UnimplementedError says so louder than a stub.
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
    // Keeps the autoDispose notifier alive for the whole test, and settles the
    // first load so the reload after a mutation is the second one.
    container.listen(inventoryProvider, (_, _) {});
    await container.read(inventoryProvider.future);
    return (container, source);
  }

  test(
    'a server with the routes takes one call for the whole selection',
    () async {
      final (container, source) = await harness(_FakeSource());

      final outcome = await container
          .read(inventoryProvider.notifier)
          .archiveSpools([1, 2, 3]);

      expect(source.bulkCalls, [
        [1, 2, 3],
      ]);
      expect(source.perSpoolCalls, isEmpty);
      expect(outcome.ok, 3);
    },
  );

  test('a server without the routes gets one call per spool', () async {
    final (container, source) = await harness(
      _FakeSource(
        bulkFailure: const ApiException(
          AppErrorCode.badResponse,
          statusCode: 404,
        ),
      ),
    );

    final outcome = await container
        .read(inventoryProvider.notifier)
        .archiveSpools([1, 2, 3]);

    expect(source.bulkCalls, hasLength(1));
    expect(source.perSpoolCalls, [1, 2, 3]);
    expect((outcome.ok, outcome.failed), (3, 0));
  });

  test('one spool failing in the fallback does not abort the rest', () async {
    final (container, source) = await harness(
      _FakeSource(
        bulkFailure: const ApiException(
          AppErrorCode.badResponse,
          statusCode: 404,
        ),
        failingSpoolIds: {2},
      ),
    );

    final outcome = await container
        .read(inventoryProvider.notifier)
        .archiveSpools([1, 2, 3]);

    expect(source.perSpoolCalls, [1, 2, 3]);
    expect((outcome.ok, outcome.failed), (2, 1));
  });

  test('a refusal that is not a missing route reaches the caller', () async {
    // 403 from a key without `filaments:update`: one request now stands for the
    // whole selection, so retrying it per spool would only ask 20 times to be
    // told no. The UI words it instead.
    final (container, source) = await harness(
      _FakeSource(bulkFailure: const AuthException(AppErrorCode.forbidden)),
    );

    await expectLater(
      container.read(inventoryProvider.notifier).archiveSpools([1, 2]),
      throwsA(isA<AuthException>()),
    );
    expect(source.perSpoolCalls, isEmpty);
  });

  test('the shelf reloads once afterwards, refusal or not', () async {
    final (container, source) = await harness(
      _FakeSource(bulkFailure: const AuthException(AppErrorCode.forbidden)),
    );
    expect(source.loads, 1);

    await container
        .read(inventoryProvider.notifier)
        .archiveSpools([1, 2])
        .onError((_, _) => BulkOutcome.empty);

    expect(source.loads, 2);
  });
}
