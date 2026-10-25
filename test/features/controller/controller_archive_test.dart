import 'dart:async';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/features/controller/controller_archive.dart';
import 'package:bambuddy_mobile/features/controller/controller_print.dart';
import 'package:bambuddy_mobile/features/controller/controller_prints.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';
import '../archive/archive_fakes.dart';
import 'controller_harness.dart';

Archive _print(
  int id, {
  String status = 'completed',
  String filename = 'part.gcode.3mf',
  int? createdById,
}) => Archive(
  id: id,
  filename: filename,
  status: status,
  printName: 'Print $id',
  printerId: controllerTestPrinterId,
  slicedForModel: 'P1S',
  createdById: createdById,
);

/// [count] prints, newest first, as the server lists them.
List<Archive> _prints(int count, {int from = 1}) => [
  for (var id = from; id < from + count; id++) _print(id),
];

void main() {
  group('controllerArchiveProvider', () {
    late FakeArchives repo;

    ProviderContainer container(List<Archive> rows) {
      repo = FakeArchives(rows: rows);
      final c = ProviderContainer(
        overrides: [
          noServerProfileOverride,
          archiveRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(c.dispose);
      // Kept alive for the test, as the view keeps it.
      c.listen(controllerArchiveProvider(1), (_, _) {});
      return c;
    }

    Future<ControllerArchivePage> first(ProviderContainer c) =>
        c.read(controllerArchiveProvider(1).future);

    ControllerArchivePage now(ProviderContainer c) =>
        c.read(controllerArchiveProvider(1)).requireValue;

    test('the first page is this printer\'s 50 newest', () async {
      final c = container(_prints(120));

      final page = await first(c);

      expect(repo.listed, [(printerId: 1, limit: 50, offset: 0)]);
      expect(page.items, hasLength(50));
      expect(page.hasMore, isTrue);
    });

    test('the next page starts where the server left off, and a row a new '
        'print pushed down is kept once', () async {
      final c = container(_prints(120, from: 1));
      await first(c);
      // A print finished meanwhile: every row moves down by one.
      repo.rows = [_print(999), ...repo.rows];

      await c.read(controllerArchiveProvider(1).notifier).loadMore();

      expect(repo.listed.last.offset, 50);
      final ids = [for (final a in now(c).items) a.id];
      expect(ids.toSet(), hasLength(ids.length), reason: 'no row twice');
      expect(ids, hasLength(99));
      expect(now(c).fetched, 100);
      expect(now(c).hasMore, isTrue);

      await c.read(controllerArchiveProvider(1).notifier).loadMore();
      // By the rows the server handed over, not by the rows kept.
      expect(repo.listed.last.offset, 100);
    });

    test('a short page is the end, and nothing more is asked', () async {
      final c = container(_prints(30));
      final page = await first(c);

      expect(page.hasMore, isFalse);
      await c.read(controllerArchiveProvider(1).notifier).loadMore();
      expect(repo.listed, hasLength(1));
    });

    test(
      'a page exactly full asks once more, and an empty one ends it',
      () async {
        final c = container(_prints(50));
        await first(c);

        await c.read(controllerArchiveProvider(1).notifier).loadMore();

        expect(repo.listed.last.offset, 50);
        expect(now(c).items, hasLength(50));
        expect(now(c).hasMore, isFalse);
      },
    );

    test('one page at a time', () async {
      final c = container(_prints(120));
      await first(c);
      final notifier = c.read(controllerArchiveProvider(1).notifier);

      await Future.wait([notifier.loadMore(), notifier.loadMore()]);

      expect(repo.listed, hasLength(2));
    });

    test('a failed page keeps what was read and can be asked again', () async {
      final c = container(_prints(120));
      await first(c);
      final notifier = c.read(controllerArchiveProvider(1).notifier);

      repo.listError = const ApiException(AppErrorCode.connectionError);
      await notifier.loadMore();

      expect(now(c).items, hasLength(50));
      expect(now(c).moreFailed, isNotNull);
      expect(now(c).hasMore, isTrue);

      await notifier.loadMore();

      expect(now(c).items, hasLength(100));
      expect(now(c).moreFailed, isNull);
    });

    test('a page that lands after a refresh is dropped', () async {
      final c = container(_prints(120));
      await first(c);
      final notifier = c.read(controllerArchiveProvider(1).notifier);
      final held = repo.listHeld = Completer<void>();

      final more = notifier.loadMore();
      await notifier.refresh();
      held.complete();
      await more;

      expect(now(c).items, hasLength(50), reason: 'the refreshed first page');
      expect(now(c).fetched, 50);
    });

    test('a listing rebuilt from scratch still refreshes and pages', () async {
      final c = container(_prints(120));
      await first(c);

      // What a change of server does: a dispose, then a build on the same
      // notifier.
      c.invalidate(controllerArchiveProvider(1));
      await first(c);
      repo.rows = _prints(120, from: 500);
      await c.read(controllerArchiveProvider(1).notifier).refresh();

      expect(now(c).items.first.id, 500);
    });

    test('a refresh starts from the newest again', () async {
      final c = container(_prints(120));
      await first(c);
      final notifier = c.read(controllerArchiveProvider(1).notifier);
      await notifier.loadMore();

      await notifier.refresh();

      expect(repo.listed.last.offset, 0);
      expect(now(c).items, hasLength(50));
    });
  });

  group('the Archive view', () {
    late FakeArchives repo;

    Future<void> open(
      WidgetTester tester,
      List<Archive> rows, {
      CurrentUser? user,
    }) async {
      repo = FakeArchives(rows: rows);
      await pumpControllerScreen(
        tester,
        overrides: [
          archiveRepositoryProvider.overrideWithValue(repo),
          if (user != null) currentUserOverride(user),
        ],
      );
      await openPrintsView(tester, ControllerPrintsView.archive);
    }

    Future<void> openPrint(WidgetTester tester, int id) async {
      await tester.tap(find.text('Print $id'));
      await settle(tester);
    }

    testWidgets('lists what this printer printed', (tester) async {
      await open(tester, _prints(3));

      expect(repo.listed.first.printerId, controllerTestPrinterId);
      expect(find.text('Print 1'), findsOneWidget);
      expect(find.text(pl.printLogStatusCompleted), findsWidgets);
    });

    testWidgets('nothing printed says so', (tester) async {
      await open(tester, const []);

      expect(find.text(pl.controllerArchiveEmpty), findsOneWidget);
    });

    testWidgets('reaching the end reads older prints', (tester) async {
      await open(tester, _prints(70));
      expect(repo.listed, hasLength(1));

      await tester.dragUntilVisible(
        find.text('Print 60'),
        find.byType(CustomScrollView),
        const Offset(0, -300),
      );
      await settle(tester);

      expect(repo.listed, hasLength(2));
      expect(repo.listed.last.offset, 50);
      expect(find.text('Print 60'), findsOneWidget);
    });

    testWidgets('a page that failed at the end offers a retry', (tester) async {
      await open(tester, _prints(70));
      repo.listError = const ApiException(AppErrorCode.connectionError);

      await tester.dragUntilVisible(
        byLogId('controller.archive.more_retry'),
        find.byType(CustomScrollView),
        const Offset(0, -300),
      );
      await settle(tester);
      expect(find.text(pl.connectFailed), findsOneWidget);

      await tester.tap(byLogId('controller.archive.more_retry'));
      await settle(tester);
      await tester.dragUntilVisible(
        find.text('Print 70'),
        find.byType(CustomScrollView),
        const Offset(0, -300),
      );

      expect(find.text('Print 70'), findsOneWidget);
      expect(byLogId('controller.archive.more_retry'), findsNothing);
    });

    testWidgets('Print again opens the print screen on the archive', (
      tester,
    ) async {
      await open(tester, _prints(3));
      await openPrint(tester, 2);

      await tester.tap(byLogId('controller.archive.dialog.print'));
      await settle(tester);

      final screen = tester.widget<ControllerPrintScreen>(
        find.byType(ControllerPrintScreen),
      );
      expect(screen.draft.archiveId, 2);
      expect(screen.draft.libraryFileId, isNull);
    });

    testWidgets('someone else\'s print is not a reprint-own user\'s to print '
        'again, and says why', (tester) async {
      await open(
        tester,
        [_print(1, createdById: 99)],
        user: const CurrentUser(
          id: 7,
          username: 'op',
          isAdmin: false,
          permissions: {
            Permissions.queueCreate,
            Permissions.archivesReprintOwn,
          },
        ),
      );
      await openPrint(tester, 1);

      expect(
        buttonAt(tester, 'controller.archive.dialog.print').onPressed,
        isNull,
      );
      expect(find.text(pl.archiveReprintNotAllowed), findsOneWidget);
    });

    testWidgets('a print that is not sliced cannot be printed again', (
      tester,
    ) async {
      await open(tester, [_print(1, filename: 'model.3mf')]);
      await openPrint(tester, 1);

      expect(
        buttonAt(tester, 'controller.archive.dialog.print').onPressed,
        isNull,
      );
      expect(find.text(pl.controllerFileReasonNotSliced), findsOneWidget);
    });
  });
}
