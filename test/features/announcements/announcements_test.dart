import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/data/announcements_repository.dart';
import 'package:bambuddy_mobile/features/announcements/announcements_screen.dart';
import 'package:bambuddy_mobile/features/announcements/announcements_widgets.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter server;
  late RequestLog log;
  late List<Override> overrides;

  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(Scaffold).first));

  Map<String, dynamic> row(
    String id,
    String level, {
    bool read = false,
    bool archived = false,
  }) => {
    'id': id,
    'level': level,
    'texts': {
      'en': {'title': 'EN $id', 'body': 'body $id'},
      'pl': {'title': 'PL $id', 'body': 'treść $id'},
    },
    'link_url': 'https://github.com/maziggy/bambuddy',
    'published_at': '2026-10-01T10:00:00',
    'archived': archived,
    'read': read,
  };

  void inbox(bool visible, [List<Map<String, dynamic>> rows = const []]) =>
      server.onGet(
        '/api/v1/announcements',
        (s) => s.reply(200, {'visible': visible, 'announcements': rows}),
      );

  setUp(() {
    dio = testDio();
    server = mockServer(dio);
    log = captureRequests(dio);
    overrides = [
      fakeServerProfileOverride(authMode: AuthMode.jwt),
      announcementsRepositoryProvider.overrideWithValue(
        AnnouncementsRepository(dio),
      ),
    ];
  });

  Widget drawerHost() => Scaffold(
    appBar: AppBar(leading: const AnnouncementsDrawerButton()),
    drawer: const Drawer(child: Row(children: [AnnouncementsHeaderButton()])),
    body: const AnnouncementBanner(),
  );

  Future<void> openDrawer(WidgetTester tester) async {
    await tester.tap(find.byType(DrawerButton));
    await tester.pumpAndSettle();
  }

  testWidgets('an API key session has no entry, no dot and no banner', (
    tester,
  ) async {
    inbox(false);
    await pumpPhone(tester, drawerHost(), overrides: overrides);
    await tester.pumpAndSettle();
    expect(find.byType(Badge).evaluate().single.widget, isA<Badge>());
    expect(
      (tester.widget(find.byType(Badge)) as Badge).isLabelVisible,
      isFalse,
    );
    expect(find.byType(TextButton), findsNothing);
    await openDrawer(tester);
    expect(find.byIcon(Icons.campaign_outlined), findsNothing);
  });

  testWidgets('an older server (404) has none either', (tester) async {
    server.onGet(
      '/api/v1/announcements',
      (s) => s.reply(404, {'detail': 'Not Found'}),
    );
    await pumpPhone(tester, drawerHost(), overrides: overrides);
    await tester.pumpAndSettle();
    await openDrawer(tester);
    expect(find.byIcon(Icons.campaign_outlined), findsNothing);
  });

  testWidgets('an empty inbox still has its entry, without a count', (
    tester,
  ) async {
    inbox(true);
    await pumpPhone(tester, drawerHost(), overrides: overrides);
    await tester.pumpAndSettle();
    await openDrawer(tester);
    expect(find.byIcon(Icons.campaign_outlined), findsOneWidget);
    final badges = tester.widgetList<Badge>(find.byType(Badge));
    expect(badges.every((b) => !b.isLabelVisible), isTrue);
  });

  testWidgets('unread lights the dot and counts in the header', (tester) async {
    inbox(true, [
      row('a', 'info'),
      row('b', 'info', read: true),
      row('c', 'info', archived: true),
    ]);
    await pumpPhone(tester, drawerHost(), overrides: overrides);
    await tester.pumpAndSettle();
    expect(
      (tester.widget(find.byType(Badge).first) as Badge).isLabelVisible,
      isTrue,
    );
    await openDrawer(tester);
    expect(find.text('1'), findsOneWidget);
    // Info never raises the banner.
    expect(find.text(l10n(tester).announcementsGotIt), findsNothing);
  });

  testWidgets('the banner shows the worst unread one; Got it reads it', (
    tester,
  ) async {
    inbox(true, [row('imp', 'important'), row('crit', 'critical')]);
    server.onPost('/api/v1/announcements/crit/read', (s) => s.reply(204, null));
    await pumpPhone(tester, drawerHost(), overrides: overrides);
    await tester.pumpAndSettle();
    final t = l10n(tester);
    expect(find.text('PL crit'), findsOneWidget);
    expect(find.text(t.announcementsReadMoreCount(1)), findsOneWidget);

    await tester.tap(find.text(t.announcementsGotIt));
    await tester.pumpAndSettle();
    expect(log.calls, contains('POST /api/v1/announcements/crit/read'));
    expect(find.text('PL imp'), findsOneWidget);
    expect(find.text(t.announcementsReadMore), findsOneWidget);
  });

  testWidgets('the screen reads a message when it is opened, not before', (
    tester,
  ) async {
    inbox(true, [
      row('new', 'info'),
      row('old', 'info', archived: true, read: true),
    ]);
    server.onPost('/api/v1/announcements/new/read', (s) => s.reply(204, null));
    await pumpPhone(tester, const AnnouncementsScreen(), overrides: overrides);
    await tester.pumpAndSettle();
    final t = l10n(tester);
    expect(find.text(t.announcementsNew), findsOneWidget);
    expect(find.text('treść new'), findsNothing);
    expect(find.text('PL old'), findsNothing);
    expect(log.calls, ['GET /api/v1/announcements']);

    await tester.tap(find.text('PL new'));
    await tester.pumpAndSettle();
    expect(find.text('treść new'), findsOneWidget);
    expect(find.text(t.announcementsNew), findsNothing);
    expect(log.calls.last, 'POST /api/v1/announcements/new/read');

    await tester.tap(find.text(t.announcementsEarlier(1)));
    await tester.pumpAndSettle();
    expect(find.text('PL old'), findsOneWidget);
  });

  testWidgets('arriving from the banner opens and reads that message', (
    tester,
  ) async {
    inbox(true, [row('a', 'important')]);
    server.onPost('/api/v1/announcements/a/read', (s) => s.reply(204, null));
    await pumpPhone(
      tester,
      const AnnouncementsScreen(openId: 'a'),
      overrides: overrides,
    );
    await tester.pumpAndSettle();
    expect(find.text('treść a'), findsOneWidget);
    expect(log.calls.last, 'POST /api/v1/announcements/a/read');
  });

  testWidgets('a refused read puts the message back', (tester) async {
    inbox(true, [row('a', 'important')]);
    server.onPost(
      '/api/v1/announcements/a/read',
      (s) => s.reply(404, {'detail': 'Announcement not found'}),
    );
    await pumpPhone(tester, drawerHost(), overrides: overrides);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n(tester).announcementsGotIt));
    await tester.pumpAndSettle();
    // The re-read answers the same inbox, so the banner is back.
    expect(find.text('PL a'), findsOneWidget);
    expect(log.calls.last, 'GET /api/v1/announcements');
  });
}
