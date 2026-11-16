import 'dart:async';
import 'dart:convert';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/data/server_settings_repository.dart';
import 'package:bambuddy_mobile/features/notifications/notification_settings_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../contract/sent_writes.dart';
import '../../helpers.dart';

/// The server's low-stock threshold on the notification settings screen: shown
/// when the server has one, edited by whoever may write server settings, and
/// replaced by this phone's own slider on a server that has none.
class _Settings extends ServerSettingsRepository {
  _Settings(this.settings, {this.failWith}) : super(Dio());

  Map<String, dynamic> settings;
  final AppApiException? failWith;
  final writes = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> fetch() async => settings;

  @override
  Future<Map<String, dynamic>> update(Map<String, dynamic> changes) async {
    writes.add(changes);
    if (failWith case final failure?) throw failure;
    return settings = {...settings, ...changes};
  }
}

/// A server that answers every request with the same body, and refuses a write
/// with [status].
class _EchoAdapter implements HttpClientAdapter {
  _EchoAdapter({this.status = 200});

  final int status;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({'low_stock_threshold': 15.5}),
      // The read that fills the screen is never the one that is refused.
      options.method == 'GET' ? 200 : status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  Future<_Settings> pumpScreen(
    WidgetTester tester, {
    Map<String, dynamic> settings = const {'low_stock_threshold': 20.0},
    AuthMode authMode = AuthMode.none,
    CurrentUser? user,
    AppApiException? failWith,
    ServerSettingsRepository? repository,
    Map<String, dynamic> flags = const {},
  }) async {
    usePhoneWindow(tester, dp: 3000);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final fake = _Settings(settings, failWith: failWith);
    await pumpPhone(
      tester,
      const NotificationSettingsScreen(),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        fakeServerProfileOverride(authMode: authMode),
        currentUserOverride(user),
        serverSettingsRepositoryProvider.overrideWithValue(repository ?? fake),
        serverUiFlagsProvider.overrideWith((ref) async => flags),
      ],
    );
    await tester.pumpAndSettle();
    return fake;
  }

  final pencil = find.byTooltip(pl.notifLowStockEdit);

  Future<void> typeAndSave(WidgetTester tester, String text) async {
    await tester.tap(pencil);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), text);
    await tester.tap(
      find.text(
        MaterialLocalizations.of(
          tester.element(find.byType(AlertDialog)),
        ).saveButtonLabel,
      ),
    );
    await tester.pumpAndSettle();
  }

  group('which control shows', () {
    testWidgets('the server number, with a pencil, where settings are open', (
      tester,
    ) async {
      await pumpScreen(tester);
      expect(find.text(pl.notifLowStockTitle('20')), findsOneWidget);
      expect(pencil, findsOneWidget);
      expect(find.byType(Slider), findsNWidgets(2), reason: 'humidity, bed');
    });

    testWidgets('a decimal threshold is shown as it is', (tester) async {
      await pumpScreen(tester, settings: {'low_stock_threshold': 15.5});
      expect(find.text(pl.notifLowStockTitle('15.5')), findsOneWidget);
    });

    testWidgets('an API key reads it and cannot change it', (tester) async {
      await pumpScreen(tester, authMode: AuthMode.apiKey);
      expect(find.text(pl.notifLowStockTitle('20')), findsOneWidget);
      expect(pencil, findsNothing);
    });

    testWidgets('an account without settings:update reads it only', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        authMode: AuthMode.jwt,
        user: const CurrentUser(
          id: 2,
          username: 'bob',
          isAdmin: false,
          permissions: <String>{},
        ),
      );
      expect(find.text(pl.notifLowStockTitle('20')), findsOneWidget);
      expect(pencil, findsNothing);
    });

    testWidgets('a server without the setting keeps the phone\'s slider', (
      tester,
    ) async {
      await pumpScreen(tester, settings: const {'use_slicer_api': true});
      expect(find.text(pl.notifLowStockTitle('20')), findsNothing);
      expect(pencil, findsNothing);
      expect(find.byType(Slider), findsNWidgets(3));
    });
  });

  group('editing it', () {
    testWidgets('writes the number and shows what the server answered', (
      tester,
    ) async {
      final server = await pumpScreen(tester);
      await typeAndSave(tester, '15,5');
      expect(server.writes, [
        {'low_stock_threshold': 15.5},
      ]);
      expect(find.text(pl.notifLowStockTitle('15.5')), findsOneWidget);
    });

    for (final bad in ['', 'abc', '0', '100', '123', '-5']) {
      testWidgets('"$bad" is refused before anything is sent', (tester) async {
        final server = await pumpScreen(tester);
        await typeAndSave(tester, bad);
        expect(server.writes, isEmpty);
        expect(find.text(pl.notifLowStockTitle('20')), findsOneWidget);
      });
    }

    testWidgets('a refusal leaves the old number and says so', (tester) async {
      final server = await pumpScreen(
        tester,
        failWith: const ApiException(AppErrorCode.forbidden, statusCode: 403),
      );
      await typeAndSave(tester, '30');
      expect(server.writes, [
        {'low_stock_threshold': 30.0},
      ]);
      expect(find.text(pl.notifLowStockTitle('20')), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('leaving the dialog sends nothing', (tester) async {
      final server = await pumpScreen(tester);
      await tester.tap(pencil);
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(
          MaterialLocalizations.of(
            tester.element(find.byType(AlertDialog)),
          ).cancelButtonLabel,
        ),
      );
      await tester.pumpAndSettle();
      expect(server.writes, isEmpty);
    });

    testWidgets('what the real repository sends is what the server takes', (
      tester,
    ) async {
      final adapter = _EchoAdapter();
      final repository = ServerSettingsRepository(
        Dio(BaseOptions(baseUrl: 'http://server.test'))
          ..httpClientAdapter = adapter,
      );
      await pumpScreen(tester, repository: repository);
      await typeAndSave(tester, '15.5');
      expectSentAsRecorded('low_stock_threshold', writesOf(adapter.requests));
    });
  });

  group('when it goes wrong', () {
    testWidgets('a refused write closes the pencil, not just the snackbar', (
      tester,
    ) async {
      final adapter = _EchoAdapter(status: 403);
      // `/auth/me` says yes and the route says no: the route outranks it.
      await pumpScreen(
        tester,
        authMode: AuthMode.jwt,
        user: const CurrentUser(
          id: 2,
          username: 'bob',
          isAdmin: false,
          permissions: {Permissions.settingsUpdate},
        ),
        repository: ServerSettingsRepository(
          Dio(BaseOptions(baseUrl: 'http://server.test'))
            ..httpClientAdapter = adapter,
        ),
      );
      await typeAndSave(tester, '30');
      expect(writesOf(adapter.requests), hasLength(1));
      expect(find.byType(SnackBar), findsOneWidget);
      expect(pencil, findsNothing);
      // What the server held when the screen opened (the adapter's 15.5), not
      // what was typed.
      expect(find.text(pl.notifLowStockTitle('15.5')), findsOneWidget);
    });

    testWidgets('the pencil waits for a write that is out', (tester) async {
      final gate = Completer<void>();
      final server = _Held(gate.future);
      await pumpScreen(tester, repository: server);
      await typeAndSave(tester, '30');
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.edit_outlined),
            )
            .onPressed,
        isNull,
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.edit_outlined),
            )
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('a screen gone while the dialog was open is not written to', (
      tester,
    ) async {
      final server = await pumpScreen(tester);
      await tester.tap(pencil);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '30');
      // The row is no longer on screen, as when the screen is popped.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NotificationSettingsScreen)),
      );
      container.read(serverSettingsProvider.notifier).adopt(const {});
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(
          MaterialLocalizations.of(
            tester.element(find.byType(AlertDialog)),
          ).saveButtonLabel,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(server.writes, [
        {'low_stock_threshold': 30.0},
      ]);
    });
  });

  group('a session that may not read the settings', () {
    testWidgets('sees the server number from the flags, read only', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        settings: const {},
        flags: {'low_stock_threshold': 7.5},
        authMode: AuthMode.apiKey,
      );
      expect(find.text(pl.notifLowStockTitle('7.5')), findsOneWidget);
      expect(pencil, findsNothing);
      expect(find.byType(Slider), findsNWidgets(2));
    });

    testWidgets('and the phone\'s slider only when no one has the number', (
      tester,
    ) async {
      await pumpScreen(tester, settings: const {});
      expect(find.byType(Slider), findsNWidgets(3));
    });
  });
}

/// A settings repository whose write waits for [gate].
class _Held extends ServerSettingsRepository {
  _Held(this.gate) : super(Dio());

  final Future<void> gate;

  @override
  Future<Map<String, dynamic>> fetch() async => const {
    'low_stock_threshold': 20.0,
  };

  @override
  Future<Map<String, dynamic>> update(Map<String, dynamic> changes) async {
    await gate;
    return {...changes};
  }
}
