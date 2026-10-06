import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Server #1620: a user without `queue:start_unreviewed` has every job held
/// until a reviewer starts it, and may start none. Every 1.2.6 daily reports
/// the same version, so the gate is read off a printer row instead.
void main() {
  group('reviewGateCapability', () {
    Future<bool?> seen(List<Map<String, dynamic>> rows) async {
      final dio = testDio();
      mockServer(dio).onGet('/api/v1/printers/', (s) => s.reply(200, rows));
      final repo = PrintersRepository(dio);
      await repo.fetchPrinters();
      return repo.reviewGateCapability.observedAnswer;
    }

    test('a printer row from #694 on proves the gate', () async {
      expect(
        await seen([
          {'id': 1, 'name': 'X1C', 'wear_cost_per_hour': null},
        ]),
        isTrue,
      );
    });

    test('an older row reads as no gate', () async {
      expect(
        await seen([
          {'id': 1, 'name': 'X1C'},
        ]),
        isFalse,
      );
    });

    test('no printer settles nothing', () async {
      expect(await seen(const []), isNull);
    });
  });

  group('awaitingReviewProvider', () {
    Future<bool> held(CurrentUser? me, {bool gate = true}) async {
      final container = ProviderContainer(
        overrides: [
          currentUserOverride(me),
          queueReviewGateProvider.overrideWithValue(AsyncData(gate)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(currentUserProvider.future);
      return container.read(awaitingReviewProvider);
    }

    CurrentUser user(Set<String> permissions, {bool admin = false}) =>
        CurrentUser(
          id: 7,
          username: 'student',
          isAdmin: admin,
          permissions: permissions,
        );

    test('a user holding neither right is held', () async {
      final me = user({Permissions.queueCreate, Permissions.queueUpdateOwn});
      expect(await held(me), isTrue);
    });

    test('either right, or admin, lets the user start', () async {
      for (final me in [
        user({Permissions.queueStartUnreviewed}),
        user({Permissions.queueUpdateAll}),
        user(const {}, admin: true),
      ]) {
        expect(await held(me), isFalse, reason: '${me.permissions}');
      }
    });

    test('a server without the gate, or nobody known, holds no one', () async {
      final me = user(const {});
      expect(await held(me, gate: false), isFalse);
      expect(await held(null), isFalse);
    });
  });
}
