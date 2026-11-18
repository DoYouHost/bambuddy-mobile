import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/queue_settings.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/data/server_settings_repository.dart';
import 'package:bambuddy_mobile/features/settings/queue_settings_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:material_ui/material_ui.dart';

import '../../contract/sent_writes.dart';
import '../../helpers.dart';

/// The any-model order (server #2915, 1.3.2) on the queue settings screen: a
/// select that exists only where the server answered the key, writes that key
/// alone, and puts the old value back when the server refuses.
void main() {
  late DioAdapter server;
  late RequestLog log;

  /// The block a 1.3.2 server answers; [order] null leaves the key out, as a
  /// server before it does.
  Map<String, dynamic> settings({String? order = 'fewest_hours'}) => {
    'require_plate_clear': false,
    'queue_shortest_first': true,
    'queue_max_concurrent_uploads': 4,
    'model_dispatch_order': ?order,
  };

  Future<void> pump(
    WidgetTester tester,
    Map<String, dynamic> served, {
    AuthMode authMode = AuthMode.none,
    double textScale = 1,
    void Function(DioAdapter server)? routes,
  }) async {
    usePhoneWindow(tester, dp: 2400);
    final dio = testDio();
    server = mockServer(dio)
      ..onGet(Endpoints.appSettings, (s) => s.reply(200, served));
    routes?.call(server);
    log = captureRequests(dio);
    await pumpPhone(
      tester,
      const QueueSettingsScreen(),
      builder: textScaled(textScale),
      overrides: [
        fakeServerProfileOverride(authMode: authMode),
        currentUserOverride(null),
        serverSettingsRepositoryProvider.overrideWithValue(
          ServerSettingsRepository(dio),
        ),
      ],
    );
    await tester.pumpAndSettle();
  }

  Finder combo() => byLogId('queue_settings.dispatch_order');

  DropdownMenu<ModelDispatchOrder> menu(WidgetTester tester) =>
      tester.widget(find.byType(DropdownMenu<ModelDispatchOrder>));

  Future<void> choose(WidgetTester tester, String label) async {
    await tester.tap(combo());
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('a server before 1.3.2 has no such row, the rest stays', (
    tester,
  ) async {
    await pump(tester, settings(order: null));

    expect(combo(), findsNothing);
    expect(find.text(pl.queueSettingsDispatchLabel), findsNothing);
    expect(find.text(pl.queueSettingsShortestFirstTitle), findsOneWidget);
  });

  testWidgets('shows the stored order and says what it decides', (
    tester,
  ) async {
    await pump(tester, settings(order: 'least_recently_used'));

    expect(combo(), findsOneWidget);
    expect(find.text(pl.queueSettingsDispatchLabel), findsOneWidget);
    expect(find.text(pl.queueSettingsDispatchDesc), findsOneWidget);
    expect(
      find.text(pl.queueSettingsDispatchLeastRecentlyUsed),
      findsOneWidget,
    );
  });

  testWidgets('an order this app does not know reads as the default', (
    tester,
  ) async {
    await pump(tester, settings(order: 'most_wear'));

    expect(find.text(pl.queueSettingsDispatchFewestHours), findsOneWidget);
  });

  testWidgets('choosing one sends that key alone, in the server spelling', (
    tester,
  ) async {
    await pump(
      tester,
      settings(),
      routes: (s) => s.onPut(
        Endpoints.appSettingsUpdate,
        (r) => r.reply(200, settings(order: 'priority')),
        data: {'model_dispatch_order': 'priority'},
      ),
    );

    await choose(tester, pl.queueSettingsDispatchPriority);

    expect(log.statuses.last, 200, reason: 'the exact-body mock matched');
    expect(find.text(pl.queueSettingsDispatchPriority), findsOneWidget);
    expectSentAsRecorded(
      'dispatch_order_save',
      writesOf(log.requests.where((r) => r.method == 'PUT')),
    );
  });

  testWidgets('choosing the order already set sends nothing', (tester) async {
    await pump(tester, settings());

    await choose(tester, pl.queueSettingsDispatchFewestHours);

    expect(log.requests.where((r) => r.method == 'PUT'), isEmpty);
  });

  testWidgets('a refused write puts the old order back on screen', (
    tester,
  ) async {
    await pump(
      tester,
      settings(order: 'most_hours'),
      routes: (s) => s.onPut(
        Endpoints.appSettingsUpdate,
        (r) => r.reply(500, {'detail': 'boom'}),
        data: {'model_dispatch_order': 'priority'},
      ),
    );

    await choose(tester, pl.queueSettingsDispatchPriority);

    expect(find.text(pl.queueSettingsDispatchMostHours), findsOneWidget);
    expect(find.text(pl.queueSettingsDispatchPriority), findsNothing);
  });

  testWidgets('an API key sees the order but cannot change it', (tester) async {
    await pump(tester, settings(), authMode: AuthMode.apiKey);

    expect(combo(), findsOneWidget);
    expect(menu(tester).enabled, isFalse);
  });

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('lays out at ${scale}x text with its label and line', (
      tester,
    ) async {
      await pump(
        tester,
        settings(order: 'least_recently_used'),
        textScale: scale,
      );

      expect(tester.takeException(), isNull);
      expect(find.text(pl.queueSettingsDispatchLabel), findsOneWidget);
      expect(find.text(pl.queueSettingsDispatchDesc), findsOneWidget);
    });
  }
}
