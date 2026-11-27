import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/data/announcements_repository.dart';
import 'package:bambuddy_mobile/features/announcements/announcements_screen.dart';
import 'package:bambuddy_mobile/features/announcements/announcements_widgets.dart';
import 'package:bambuddy_mobile/features/announcements/app_update.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

// The real app_update and in_app_update run over mocked channels.
const _methods = MethodChannel('de.ffuf.in_app_update/methods');
const _events = EventChannel('de.ffuf.in_app_update/stateEvents');

void main() {
  late Dio dio;
  late DioAdapter server;
  late RequestLog log;
  late List<Override> overrides;
  late SharedPreferences prefs;
  late List<String> play;
  late int versionCode;
  late int installStatus;

  void installedBy(String store) => PackageInfo.setMockInitialValues(
    appName: 'app',
    packageName: 'app',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
    installerStore: store,
  );

  void inbox(bool visible, {String level = 'critical'}) => server.onGet(
    '/api/v1/announcements',
    (s) => s.reply(200, {
      'visible': visible,
      'announcements': [
        if (visible)
          {
            'id': 'a',
            'level': level,
            'texts': {
              'en': {'title': 'EN a', 'body': 'body a'},
            },
            'published_at': '2026-10-01T10:00:00',
            'read': false,
          },
      ],
    }),
  );

  setUp(() async {
    installedBy('com.android.vending');
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    play = [];
    versionCode = 42;
    installStatus = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_methods, (call) async {
      play.add(call.method);
      return call.method == 'checkForUpdate'
          ? {
              'updateAvailability': 2,
              'immediateAllowed': false,
              'immediateAllowedPreconditions': <int>[],
              'flexibleAllowed': true,
              'flexibleAllowedPreconditions': <int>[],
              'availableVersionCode': versionCode,
              'installStatus': installStatus,
              'packageName': 'app',
              'clientVersionStalenessDays': null,
              'updatePriority': 0,
            }
          : null;
    });
    messenger.setMockStreamHandler(
      _events,
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(_methods, null);
      messenger.setMockStreamHandler(_events, null);
    });
    dio = testDio();
    server = mockServer(dio);
    log = captureRequests(dio);
    overrides = [
      fakeServerProfileOverride(authMode: AuthMode.jwt),
      sharedPreferencesProvider.overrideWithValue(prefs),
      announcementsRepositoryProvider.overrideWithValue(
        AnnouncementsRepository(dio),
      ),
    ];
  });

  Widget drawerHost() => Scaffold(
    appBar: AppBar(leading: const AnnouncementsDrawerButton()),
    drawer: const Drawer(child: Row(children: [AnnouncementsHeaderButton()])),
    body: const Column(children: [AppUpdateReadyBanner()]),
  );

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double scale = 1,
  }) async {
    // 360 dp wide: the default 800 dp window never wraps a line.
    usePhoneWindow(tester);
    await pumpPhone(
      tester,
      child,
      overrides: overrides,
      builder: textScaled(scale),
    );
    await tester.pumpAndSettle();
  }

  Finder card() => find.text(pl.announcementsSourceMobile);

  testWidgets('a hidden server inbox still shows the entry for an update', (
    tester,
  ) async {
    inbox(false);
    await pump(tester, drawerHost());
    expect(
      (tester.widget(find.byType(Badge).first) as Badge).isLabelVisible,
      isTrue,
    );
    await tester.tap(find.byType(DrawerButton));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.campaign_outlined), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('the count adds the update to the unread server entries', (
    tester,
  ) async {
    inbox(true);
    await pump(tester, drawerHost());
    await tester.tap(find.byType(DrawerButton));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('a sideloaded build never asks Play and counts nothing', (
    tester,
  ) async {
    installedBy('dev.imranr.obtainium');
    inbox(false);
    await pump(tester, drawerHost());
    await tester.tap(find.byType(DrawerButton));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.campaign_outlined), findsOneWidget);
    final badges = tester.widgetList<Badge>(find.byType(Badge));
    expect(badges.every((b) => !b.isLabelVisible), isTrue);
    expect(play, isEmpty);
  });

  testWidgets('each entry names its source, the app\'s pinned first', (
    tester,
  ) async {
    inbox(true);
    await pump(tester, const AnnouncementsScreen());
    expect(
      tester.getTopLeft(card()).dy,
      lessThan(tester.getTopLeft(find.text(announcementsServerSource)).dy),
    );
    expect(find.text(pl.announcementsSource), findsOneWidget);
    expect(find.text(pl.announcementsNew), findsNWidgets(2));
  });

  testWidgets('without a server inbox there is no footer about it', (
    tester,
  ) async {
    inbox(false);
    await pump(tester, const AnnouncementsScreen());
    expect(card(), findsOneWidget);
    expect(find.text(pl.announcementsSource), findsNothing);
    expect(find.text(pl.announcementsEmpty), findsNothing);
  });

  testWidgets('a failing server inbox does not take the entry with it', (
    tester,
  ) async {
    server.onGet(
      '/api/v1/announcements',
      (s) => s.reply(500, {'detail': 'boom'}),
    );
    await pump(tester, const AnnouncementsScreen());
    expect(card(), findsOneWidget);
  });

  testWidgets('opening the entry reads it, per version and without a POST', (
    tester,
  ) async {
    inbox(false);
    await pump(tester, const AnnouncementsScreen());
    await tester.tap(find.text(pl.appUpdateTitle));
    await tester.pumpAndSettle();
    expect(find.text(pl.announcementsNew), findsNothing);
    expect(card(), findsOneWidget, reason: 'read, but still on offer');
    expect(prefs.getInt(appUpdateSeenKey), 42);
    expect(log.calls, ['GET /api/v1/announcements']);

    // A new scope is a new start: the same version stays read, a newer one
    // is news again.
    await tester.pumpWidget(const SizedBox.shrink());
    await pump(tester, const AnnouncementsScreen());
    expect(find.text(pl.announcementsNew), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    versionCode = 43;
    await pump(tester, const AnnouncementsScreen());
    expect(find.text(pl.announcementsNew), findsOneWidget);
  });

  testWidgets('mark all reads the update too', (tester) async {
    inbox(true);
    server.onPost('/api/v1/announcements/a/read', (s) => s.reply(204, null));
    await pump(tester, const AnnouncementsScreen());
    await tester.tap(find.byTooltip(pl.announcementsMarkAllRead));
    await tester.pumpAndSettle();
    expect(find.text(pl.announcementsNew), findsNothing);
    expect(prefs.getInt(appUpdateSeenKey), 42);
    expect(log.calls.last, 'POST /api/v1/announcements/a/read');
  });

  testWidgets('Update downloads, then Restart installs', (tester) async {
    inbox(false);
    await pump(tester, const AnnouncementsScreen());
    await tester.tap(find.text(pl.appUpdateButton));
    await tester.pumpAndSettle();
    expect(play, contains('startFlexibleUpdate'));
    expect(prefs.getInt(appUpdateSeenKey), 42);

    await tester.tap(find.text(pl.appUpdateRestart));
    await tester.pumpAndSettle();
    expect(play.last, 'completeFlexibleUpdate');
  });

  testWidgets('the dashboard banner appears only for a downloaded update', (
    tester,
  ) async {
    inbox(false);
    await pump(tester, drawerHost());
    expect(find.text(pl.appUpdateReady), findsNothing);

    // Back from the background, where the download finished.
    installStatus = 11;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text(pl.appUpdateReady), findsOneWidget);
    await tester.tap(find.text(pl.appUpdateRestart));
    await tester.pumpAndSettle();
    expect(play.last, 'completeFlexibleUpdate');
  });

  for (final scale in [1.0, 1.5, 2.0]) {
    for (final status in [0, 2, 11]) {
      testWidgets('fits at $scale text, install status $status', (
        tester,
      ) async {
        installStatus = status;
        // The widest chips: "Important" with "New".
        inbox(true, level: 'important');
        await pump(tester, const AnnouncementsScreen(), scale: scale);
        expect(tester.takeException(), isNull);
        if (scale == 2) {
          // The case under test is really there: the chips have moved down.
          expect(
            tester.getTopLeft(find.text(pl.announcementLevelImportant)).dy,
            greaterThan(
              tester.getBottomLeft(find.text(announcementsServerSource)).dy,
            ),
          );
        }
        // The chips end where the line ends, beside the name or below it.
        final line = find
            .ancestor(
              of: find.text(announcementsServerSource),
              matching: find.byType(OverflowBar),
            )
            .first;
        expect(
          tester.getTopRight(find.text(pl.announcementLevelImportant)).dx,
          lessThanOrEqualTo(tester.getTopRight(line).dx),
        );
        expect(
          tester.getTopRight(line).dx -
              tester.getTopRight(find.text(pl.announcementsNew).last).dx,
          lessThan(DashSpace.lg),
        );
      });
    }
  }

  testWidgets('the banner fits at 2.0 text', (tester) async {
    installStatus = 11;
    inbox(false);
    await pump(tester, drawerHost(), scale: 2);
    expect(find.text(pl.appUpdateReady), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
