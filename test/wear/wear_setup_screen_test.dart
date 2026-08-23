import 'package:bambuddy_mobile/core/watch/watch_config_sync.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/wear/screens/wear_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_connectivity/watch_connectivity.dart';

import '../helpers.dart';

/// What a fresh watch offers. Issue #25: the server-URL field was the first
/// thing on this screen and the watch keyboard never opened for it, which left
/// the app unusable to anyone who did not already have it running on a phone.
/// So two things are asserted here — that the phone handoff leads, and that the
/// manual path types through the watch's own input activity rather than a
/// keyboard that is not coming.
/// A handoff that blows up while persisting, the way secure storage does when
/// the Keystore no longer holds the key it was written with.
class _FailingConfigSync extends WatchConfigSync {
  _FailingConfigSync()
      : super(
          watch: WatchConnectivity(),
          credentials: InMemoryCredentialsStore(),
        );

  @override
  Future<bool> adoptLatestPending() async =>
      throw Exception('keystore is gone');
}

void main() {
  const inputChannel =
      MethodChannel('page.codeberg.morganmlgman.bambuddy/wear_input');

  final calls = <MethodCall>[];
  String? entered;
  bool isWatch = true;

  void mockWatchInput() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(inputChannel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'isSupported' => isWatch,
        'requestText' => entered,
        _ => null,
      };
    });
  }

  setUp(() async {
    calls.clear();
    entered = null;
    isWatch = true;
    SharedPreferences.setMockInitialValues({});
    mockWatchInput();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(inputChannel, null);
  });

  Future<void> pumpSetup(WidgetTester tester,
      {List<Override> overrides = const []}) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        credentialsStoreProvider.overrideWithValue(InMemoryCredentialsStore()),
        ...overrides,
      ],
      child: plApp(const WearSetupScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('leads with the phone handoff, not with a field to type in',
      (tester) async {
    await pumpSetup(tester);

    expect(find.text('Ustaw z telefonu'), findsOneWidget);
    expect(find.text('Sprawdź ponownie'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('says so when the phone has pushed nothing', (tester) async {
    await pumpSetup(tester);

    // No Data Layer under a test binding, so the check comes back empty — the
    // same answer a watch gets when the phone app was never set up.
    await tester.tap(find.text('Sprawdź ponownie'));
    await tester.pumpAndSettle();

    expect(find.text('Telefon jeszcze nic nie przysłał.'), findsOneWidget);
  });

  testWidgets('a failed check gives the spinner back, not a dead screen',
      (tester) async {
    await pumpSetup(tester, overrides: [
      watchConfigSyncProvider.overrideWithValue(_FailingConfigSync()),
    ]);

    await tester.tap(find.text('Sprawdź ponownie'));
    await tester.pumpAndSettle();

    // Persisting an adopted config is a secure-storage write, and that throws
    // outright rather than hanging — the timeout alone would leave the user
    // watching a spinner with no way back.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('keystore'), findsOneWidget);
    expect(find.text('Sprawdź ponownie'), findsOneWidget);
  });

  testWidgets('manual entry reveals the URL field', (tester) async {
    await pumpSetup(tester);

    await tester.tap(find.text('Wpisz ręcznie'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Adres serwera'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Połącz'), findsOneWidget);
  });

  testWidgets('the URL field takes no focus and types through the watch',
      (tester) async {
    entered = 'http://printer.local:8000';
    await pumpSetup(tester);
    await tester.tap(find.text('Wpisz ręcznie'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Adres serwera'));
    expect(field.readOnly, isTrue);
    expect(field.canRequestFocus, isFalse);

    await tester.tap(find.widgetWithText(TextField, 'Adres serwera'));
    await tester.pumpAndSettle();

    expect(
      calls.map((c) => c.method),
      containsAllInOrder(<String>['isSupported', 'requestText']),
    );
    expect(calls.last.arguments, {'label': 'Adres serwera'});
    expect(find.text('http://printer.local:8000'), findsOneWidget);
  });

  testWidgets('backing out of the watch input keeps the old value',
      (tester) async {
    entered = null;
    await pumpSetup(tester);
    await tester.tap(find.text('Wpisz ręcznie'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextField, 'Adres serwera'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Adres serwera'));
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('falls back to an editable field where there is no watch input',
      (tester) async {
    isWatch = false;
    await pumpSetup(tester);
    await tester.tap(find.text('Wpisz ręcznie'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Adres serwera'));
    expect(field.readOnly, isFalse);
    expect(calls.map((c) => c.method), isNot(contains('requestText')));
  });
}
