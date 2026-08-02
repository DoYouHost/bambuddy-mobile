import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/features/setup/setup_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

const _baseUrl = 'http://server.local:8000';

/// The code step as the user meets it: type a URL, type a password, and end up
/// on a screen that asks for something else. The controller is covered in
/// `setup_probe_test.dart`; what matters here is that the form the user sees
/// matches the account — the wrong keyboard or a missing method makes a
/// working account unreachable just as thoroughly as a missing endpoint.
void main() {
  late DioAdapter adapter;
  late ProviderContainer container;
  late bool closed;

  /// Ends the screen the way leaving it does: tearing the container down runs
  /// the controller's `onDispose`, which cancels the five-minute challenge
  /// countdown. Without it the framework's pending-timer check trips before any
  /// tearDown gets to run.
  void closeSetup() {
    if (closed) return;
    closed = true;
    container.dispose();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final dio = Dio();
    adapter = DioAdapter(dio: dio);
    container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      credentialsStoreProvider.overrideWithValue(InMemoryCredentialsStore()),
      bareDioProvider.overrideWithValue(dio),
    ]);
    closed = false;
    addTearDown(closeSetup);
  });

  ServerProfile? savedProfile() => container.read(serverProfileProvider);

  Future<void> pumpSetup(WidgetTester tester) async {
    // The setup card is taller than the default 800×600 test surface once the
    // auth section unfolds, and an off-screen button cannot be tapped.
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: plApp(const SetupScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Drives the screen as far as the code step, against a server whose account
  /// offers [methods].
  Future<void> signInTo(
    WidgetTester tester, {
    List<String> methods = const ['totp'],
  }) async {
    adapter.onGet('$_baseUrl/api/v1/auth/status',
        (s) => s.reply(200, readFixture('auth_status_enabled.json')));
    adapter.onPost(
      '$_baseUrl/api/v1/auth/login',
      (s) => s.reply(200, {
        'requires_2fa': true,
        'pre_auth_token': 'pre-auth-xyz',
        'two_fa_methods': methods,
      }),
      data: {'username': 'tester', 'password': 'sekret'},
    );

    await pumpSetup(tester);
    await tester.enterText(find.byType(TextField).first, _baseUrl);
    await tester.tap(find.text('Testuj połączenie'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Login i hasło'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), 'tester');
    await tester.enterText(fields.at(2), 'sekret');
    await tester.tap(find.text('Zaloguj i połącz'));
    await tester.pumpAndSettle();
  }

  testWidgets('the password form gives way to the code field', (tester) async {
    // Side by side they invite re-submitting the password, and that mints a
    // second challenge which voids the one on screen.
    await signInTo(tester);

    expect(find.text('Uwierzytelnianie dwuskładnikowe'), findsOneWidget);
    expect(find.text('Zaloguj i połącz'), findsNothing);
    expect(find.text('Potwierdź i połącz'), findsOneWidget);
    closeSetup();
  });

  testWidgets('a single method needs no picker', (tester) async {
    await signInTo(tester);

    expect(find.byType(SegmentedButton<Object?>), findsNothing);
    expect(find.text('Wpisz 6-cyfrowy kod z aplikacji uwierzytelniającej.'),
        findsOneWidget);
    closeSetup();
  });

  testWidgets('backup codes switch the field to 8 letters and digits',
      (tester) async {
    // A digits-only keyboard on an 8-character alphanumeric code is the whole
    // difference between "2FA works" and "my codes are all rejected".
    await signInTo(tester, methods: ['totp', 'backup']);

    await tester.tap(find.text('Kod zapasowy'));
    await tester.pumpAndSettle();

    final code = tester.widget<TextField>(find.byType(TextField).last);
    expect(code.maxLength, 8);
    expect(code.keyboardType, TextInputType.visiblePassword);
    await tester.enterText(find.byType(TextField).last, 'a1b2c3d4');
    expect(find.text('a1b2c3d4'), findsOneWidget);
    closeSetup();
  });

  testWidgets('switching method clears a code typed for the previous one',
      (tester) async {
    // Six digits meant for the authenticator, submitted as a backup code, burn
    // one of the five attempts the server allows per quarter hour.
    await signInTo(tester, methods: ['totp', 'backup']);
    await tester.enterText(find.byType(TextField).last, '123456');

    await tester.tap(find.text('Kod zapasowy'));
    await tester.pumpAndSettle();

    expect(find.text('123456'), findsNothing);
    closeSetup();
  });

  testWidgets('the code goes out and the profile is saved', (tester) async {
    await signInTo(tester);
    adapter.onPost(
      '$_baseUrl/api/v1/auth/2fa/verify',
      (s) => s.reply(200, readFixture('login_response_ok.json')),
      data: {
        'pre_auth_token': 'pre-auth-xyz',
        'code': '123456',
        'method': 'totp',
      },
    );

    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('Potwierdź i połącz'));
    // Not pumpAndSettle: the screen stays busy behind the spinner until the
    // router (absent here) moves off setup, and an indeterminate progress
    // indicator never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(savedProfile()?.authMode, AuthMode.jwt);
    closeSetup();
  });

  testWidgets('backing out brings the password form back', (tester) async {
    await signInTo(tester);

    await tester.tap(find.text('Zaloguj się na inne konto'));
    await tester.pumpAndSettle();

    expect(find.text('Zaloguj i połącz'), findsOneWidget);
    expect(find.text('Potwierdź i połącz'), findsNothing);
    closeSetup();
  });
}
