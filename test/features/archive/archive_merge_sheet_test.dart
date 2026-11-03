import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/data/archive_repository.dart';
import 'package:bambuddy_mobile/features/archive/archive_providers.dart';
import 'package:bambuddy_mobile/features/archive/archive_screen.dart';
import 'package:bambuddy_mobile/features/archive/archive_merge_sheet.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../contract/sent_writes.dart';
import '../../helpers.dart';

Map<String, dynamic> _member(int id, String name, {int runs = 1}) => {
  'id': id,
  'print_name': name,
  'filename': '$name.3mf',
  'created_at': '2026-10-0${id % 9 + 1}T10:00:00',
  'run_count': runs,
};

final _preview = {
  'groups': [
    {
      'survivor': _member(3, 'Handle'),
      'merged': [_member(9, 'Handle', runs: 2)],
      'skipped': null,
    },
    {
      'survivor': _member(4, 'Box'),
      'merged': [_member(8, 'Box')],
      'skipped': null,
    },
    {
      'survivor': _member(5, 'Clip'),
      'merged': [_member(7, 'Clip')],
      'skipped': 'busy',
    },
  ],
};

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late RequestLog sent;

  setUp(() {
    dio = testDio();
    adapter = mockServer(dio);
    sent = captureRequests(dio);
    adapter
      ..onGet('/api/v1/archives/merge-preview', (s) => s.reply(200, _preview))
      ..onGet(
        '/api/v1/archives/merge-count',
        (s) => s.reply(200, {'groups': 2}),
      );
  });

  Future<SharedPreferences> pump(
    WidgetTester tester,
    Widget child, {
    Map<String, Object> prefs = const {},
    double textScale = 1.0,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final store = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        retry: neverRetry,
        overrides: [
          noServerProfileOverride,
          sharedPreferencesProvider.overrideWithValue(store),
          archiveRepositoryProvider.overrideWithValue(ArchiveRepository(dio)),
        ],
        child: plApp(
          Scaffold(body: child),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return store;
  }

  group('banner', () {
    testWidgets('says how many groups there are and opens the sheet', (
      tester,
    ) async {
      await pump(tester, const ArchiveMergeBanner());

      expect(find.text(pl.archiveMergeBanner(2)), findsOneWidget);
      await tester.tap(byLogId('archive.merge_banner.open'));
      await tester.pumpAndSettle();
      expect(find.text(pl.archiveMergeTitle), findsOneWidget);
    });

    testWidgets('dismissed, it stays away until there are more groups', (
      tester,
    ) async {
      final store = await pump(tester, const ArchiveMergeBanner());

      await tester.tap(byLogId('archive.merge_banner.dismiss'));
      await tester.pumpAndSettle();

      expect(find.text(pl.archiveMergeBanner(2)), findsNothing);
      expect(store.getInt('archive_merge_dismissed_at'), 2);
    });

    testWidgets('comes back once the count passes the dismissed one', (
      tester,
    ) async {
      await pump(
        tester,
        const ArchiveMergeBanner(),
        prefs: const {'archive_merge_dismissed_at': 1},
      );

      expect(find.text(pl.archiveMergeBanner(2)), findsOneWidget);
    });

    testWidgets('no groups, no banner', (tester) async {
      adapter.onGet(
        '/api/v1/archives/merge-count',
        (s) => s.reply(200, {'groups': 0}),
      );
      await pump(tester, const ArchiveMergeBanner());

      expect(byLogId('archive.merge_banner'), findsNothing);
    });

    testWidgets('an older server shows nothing and raises nothing', (
      tester,
    ) async {
      adapter.onGet(
        '/api/v1/archives/merge-count',
        (s) => s.reply(422, {'detail': []}),
      );
      await pump(tester, const ArchiveMergeBanner());

      expect(tester.takeException(), isNull);
      expect(byLogId('archive.merge_banner'), findsNothing);
    });
  });

  group('sheet', () {
    testWidgets('every mergeable group ticked, the busy one says why', (
      tester,
    ) async {
      await pump(tester, const ArchiveMergeSheet());

      expect(byLogId('archive.merge.group'), findsNWidgets(2));
      expect(find.text(pl.archiveMergeWaiting), findsOneWidget);
      expect(find.text(pl.archiveMergeSkipBusy), findsOneWidget);
      expect(find.text(pl.archiveMergeAction(2)), findsOneWidget);
    });

    testWidgets('unticking every group leaves nothing to merge', (
      tester,
    ) async {
      await pump(tester, const ArchiveMergeSheet());

      await tester.tap(byLogId('archive.merge.group').first);
      await tester.tap(byLogId('archive.merge.group').last);
      await tester.pumpAndSettle();

      expect(buttonAt(tester, 'archive.merge.confirm').onPressed, isNull);
    });

    testWidgets('the ticked groups merge after one confirmation', (
      tester,
    ) async {
      adapter.onPost(
        '/api/v1/archives/merge',
        (s) => s.reply(200, {
          'merged': [
            {
              'survivor_id': 3,
              'merged_ids': [9],
            },
          ],
          'skipped': [],
        }),
        data: Matchers.any,
      );
      // Opened as the app opens it, so closing it leaves the screen behind.
      await pump(tester, const ArchiveMergeBanner());
      await tester.tap(byLogId('archive.merge_banner.open'));
      await tester.pumpAndSettle();

      await tester.tap(byLogId('archive.merge.group').last);
      await tester.pumpAndSettle();
      await tester.tap(byLogId('archive.merge.confirm'));
      await tester.pumpAndSettle();
      expect(writesOf(sent.requests), isEmpty, reason: 'not before the yes');
      await tester.tap(find.text(pl.archiveMergeButton).last);
      await tester.pumpAndSettle();

      expectSentAsRecorded('archive_merge', writesOf(sent.requests));
      expect(find.text(pl.archiveMergeDone(1)), findsOneWidget);
      expect(find.text(pl.archiveMergeTitle), findsNothing);
    });

    testWidgets('a group the merge left out is reported with why', (
      tester,
    ) async {
      adapter.onPost(
        '/api/v1/archives/merge',
        (s) => s.reply(200, {
          'merged': [
            {
              'survivor_id': 3,
              'merged_ids': [9],
            },
          ],
          'skipped': [
            {'survivor_id': 4, 'reason': 'conflicting_files'},
          ],
        }),
        data: Matchers.any,
      );
      await pump(tester, const ArchiveMergeSheet());

      await tester.tap(byLogId('archive.merge.confirm'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(pl.archiveMergeButton).last);
      await tester.pumpAndSettle();

      expect(find.text(pl.archiveMergeLeftOut), findsOneWidget);
      expect(find.text(pl.archiveMergeSkipConflicting), findsOneWidget);
      expect(find.text(pl.archiveMergeDoneSome(1, 1)), findsOneWidget);
    });

    testWidgets('a refused merge says so and unlocks the sheet', (
      tester,
    ) async {
      adapter.onPost(
        '/api/v1/archives/merge',
        (s) => s.reply(403, {'detail': 'Missing required permissions'}),
        data: Matchers.any,
      );
      await pump(tester, const ArchiveMergeSheet());

      await tester.tap(byLogId('archive.merge.confirm'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(pl.archiveMergeButton).last);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(buttonAt(tester, 'archive.merge.confirm').onPressed, isNotNull);
    });

    testWidgets('a double tap asks once, and a no unlocks the sheet', (
      tester,
    ) async {
      await pump(tester, const ArchiveMergeSheet());

      // Two presses inside one frame, before the dialog takes the screen: a
      // tester tap cannot land the second one, the handler can.
      final press = buttonAt(tester, 'archive.merge.confirm').onPressed!;
      press();
      press();
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text(pl.cancel));
      await tester.pumpAndSettle();
      expect(writesOf(sent.requests), isEmpty);
      expect(buttonAt(tester, 'archive.merge.confirm').onPressed, isNotNull);
    });

    testWidgets('only held-back groups: nothing to tick, a way out', (
      tester,
    ) async {
      adapter.onGet(
        '/api/v1/archives/merge-preview',
        (s) => s.reply(200, {
          'groups': [(_preview['groups']! as List).last],
        }),
      );
      await pump(tester, const ArchiveMergeSheet());

      expect(byLogId('archive.merge.group'), findsNothing);
      expect(byLogId('archive.merge.confirm'), findsNothing);
      expect(byLogId('archive.merge.close'), findsOneWidget);
    });

    testWidgets('nothing to merge says so', (tester) async {
      adapter.onGet(
        '/api/v1/archives/merge-preview',
        (s) => s.reply(200, {'groups': []}),
      );
      await pump(tester, const ArchiveMergeSheet());

      expect(find.text(pl.archiveMergeNone), findsOneWidget);
    });

    for (final scale in const [1.0, 1.5, 2.0]) {
      testWidgets('the sheet fits at text $scale', (tester) async {
        tester.view.physicalSize = const Size(360, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await pump(tester, const ArchiveMergeSheet(), textScale: scale);

        expect(tester.takeException(), isNull);
        expect(byLogId('archive.merge.confirm'), findsOneWidget);
      });
    }
  });

  group('menu', () {
    Future<void> openMenu(
      WidgetTester tester, {
      required bool supported,
      Set<String> permissions = const {
        Permissions.archivesUpdateAll,
        Permissions.archivesDeleteAll,
      },
    }) async {
      SharedPreferences.setMockInitialValues({});
      final store = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          retry: neverRetry,
          overrides: [
            noServerProfileOverride,
            sharedPreferencesProvider.overrideWithValue(store),
            archiveListOverride(const []),
            archiveRepositoryProvider.overrideWithValue(ArchiveRepository(dio)),
            archiveMergeSupportedProvider.overrideWithValue(
              AsyncData(supported),
            ),
            currentUserOverride(
              CurrentUser(
                id: 1,
                username: 'op',
                isAdmin: false,
                permissions: permissions,
              ),
            ),
          ],
          child: plApp(const ArchiveScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(byLogId('archive.menu'));
      await tester.pumpAndSettle();
    }

    testWidgets('offered with the routes and both rights', (tester) async {
      await openMenu(tester, supported: true);

      expect(byLogId('archive.menu.merge'), findsOneWidget);
    });

    testWidgets('not on a server without the routes', (tester) async {
      await openMenu(tester, supported: false);

      expect(byLogId('archive.menu.merge'), findsNothing);
    });

    testWidgets('not to a session missing delete-all', (tester) async {
      await openMenu(
        tester,
        supported: true,
        permissions: const {Permissions.archivesUpdateAll},
      );

      expect(byLogId('archive.menu.merge'), findsNothing);
    });
  });
}
