import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/models/no_3mf_warning.dart';
import 'package:bambuddy_mobile/features/archive/archive_providers.dart';
import 'package:bambuddy_mobile/features/archive/archive_screen.dart';
import 'package:bambuddy_mobile/features/slicer/slice_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// Queueing an archive again is refused by `POST /queue/` without
/// `queue:create`, and by `_assert_can_queue_archive` (`print_queue.py`)
/// without the reprint right for this print — measured on a `daily` server: a
/// user holding `queue:create` and `archives:read_all` only got a 403.
void main() {
  const me = 7;

  CurrentUser user(Set<String> permissions, {bool admin = false}) =>
      CurrentUser(
        id: me,
        username: 'op',
        isAdmin: admin,
        permissions: permissions,
      );

  group('archiveReprintBlockProvider', () {
    Future<ArchiveReprintBlock?> settled(CurrentUser? who, int? owner) async {
      final container = ProviderContainer(
        overrides: [currentUserOverride(who)],
      );
      addTearDown(container.dispose);
      await container.read(currentUserProvider.future);
      return container.read(archiveReprintBlockProvider(owner));
    }

    test('an unknown identity blocks nothing', () async {
      expect(await settled(null, null), isNull);
    });

    test('without queue:create nothing can be queued', () async {
      final who = user({Permissions.archivesReprintAll});
      expect(await settled(who, me), ArchiveReprintBlock.noQueue);
    });

    test('queue:create alone is not enough', () async {
      final who = user({Permissions.queueCreate});
      expect(await settled(who, me), ArchiveReprintBlock.noReprint);
    });

    test('reprint-all reprints anyone\'s and an ownerless print', () async {
      final who = user({
        Permissions.queueCreate,
        Permissions.archivesReprintAll,
      });
      expect(await settled(who, 99), isNull);
      expect(await settled(who, null), isNull);
    });

    test('reprint-own reprints only the user\'s own print', () async {
      final who = user({
        Permissions.queueCreate,
        Permissions.archivesReprintOwn,
      });
      expect(await settled(who, me), isNull);
      expect(await settled(who, 99), ArchiveReprintBlock.noReprint);
      expect(
        await settled(who, null),
        ArchiveReprintBlock.noReprint,
        reason: 'an ownerless print needs reprint-all',
      );
    });

    test('an admin is never blocked', () async {
      expect(await settled(user(const {}, admin: true), null), isNull);
    });

    test('a server that sent no permissions blocks nothing', () async {
      const who = CurrentUser(
        id: me,
        username: 'op',
        isAdmin: false,
        permissionsKnown: false,
      );
      expect(await settled(who, 99), isNull);
    });
  });

  test('an archive reads its owner from created_by_id', () {
    final archive = Archive.fromJson({
      'id': 1,
      'filename': 'a.3mf',
      'status': 'completed',
      'created_by_id': 7,
    });
    expect(archive.createdById, 7);
    expect(
      Archive.fromJson({
        'id': 2,
        'filename': 'b.3mf',
        'status': 'completed',
      }).createdById,
      isNull,
    );
  });

  group('the archive sheet', () {
    const archive = Archive(
      id: 1,
      filename: 'benchy.gcode.3mf',
      status: 'completed',
      printName: 'Benchy',
      createdById: 99,
    );

    Future<void> openSheet(WidgetTester tester, CurrentUser who) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await pumpPhone(
        tester,
        const ArchiveScreen(),
        overrides: [
          archiveListOverride([archive]),
          no3mfWarningProvider.overrideWith((ref) async => No3mfWarning.none),
          sharedPreferencesProvider.overrideWithValue(prefs),
          noServerProfileOverride,
          slicerEnabledProvider.overrideWithValue(const AsyncData(false)),
          currentUserOverride(who),
        ],
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Benchy'));
      await tester.pumpAndSettle();
    }

    testWidgets('someone else\'s print is off for a reprint-own user, '
        'and says why', (tester) async {
      await openSheet(
        tester,
        user({Permissions.queueCreate, Permissions.archivesReprintOwn}),
      );

      expect(buttonAt(tester, 'archive.reprint').onPressed, isNull);
      expect(buttonAt(tester, 'archive.add_to_queue').onPressed, isNull);
      expect(find.text(pl.archiveReprintNotAllowed), findsOneWidget);
    });

    testWidgets('a reprint-all user keeps both buttons and no reason', (
      tester,
    ) async {
      await openSheet(
        tester,
        user({Permissions.queueCreate, Permissions.archivesReprintAll}),
      );

      expect(buttonAt(tester, 'archive.reprint').onPressed, isNotNull);
      expect(buttonAt(tester, 'archive.add_to_queue').onPressed, isNotNull);
      expect(find.text(pl.archiveReprintNotAllowed), findsNothing);
      expect(find.text(pl.archiveReprintNoQueue), findsNothing);
    });
  });
}
