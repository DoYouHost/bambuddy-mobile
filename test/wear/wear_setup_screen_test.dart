import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:bambuddy_mobile/core/watch/watch_config_sync.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/wear/screens/wear_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// What a fresh watch offers. Issue #25: the server-URL field was the first
/// thing on this screen and the watch keyboard never opened for it, which left
/// the app unusable to anyone who did not already have it running on a phone.
/// So two things are asserted here — that the phone handoff leads, and that the
/// manual path types through the watch's own input activity rather than a
/// keyboard that is not coming.

final _offered = WatchConfig(
  profile: const ServerProfile(
    baseUrl: 'http://workshop.local:8000',
    authMode: AuthMode.apiKey,
    label: 'Workshop',
  ),
  apiKey: 'bb_secret',
);

void main() {
  const inputChannel = MethodChannel(
    'page.codeberg.morganmlgman.bambuddy/wear_input',
  );

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
    mockWatchInput();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(inputChannel, null);
  });

  Future<ProviderContainer> pumpSetup(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) => pumpWear(tester, const WearSetupScreen(), overrides: overrides);

  testWidgets('leads with the phone handoff, not with a field to type in', (
    tester,
  ) async {
    await pumpSetup(tester);

    expect(find.text('Ustaw z telefonu'), findsOneWidget);
    // Below the fold on a watch face — the check button lives under the
    // explanation, so reaching it is a scroll, not a missing button.
    await revealOnWatch(tester, find.text('Sprawdź ponownie'));
    expect(find.text('Sprawdź ponownie'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('says so when the phone has pushed nothing', (tester) async {
    await pumpSetup(tester);

    // No Data Layer under a test binding, so the check comes back empty — the
    // same answer a watch gets when the phone app was never set up.
    await tapOnWatch(tester, find.text('Sprawdź ponownie'));
    await tester.pumpAndSettle();

    expect(find.text('Telefon jeszcze nic nie przysłał.'), findsOneWidget);
  });

  testWidgets('what the phone sent is shown before it is used', (tester) async {
    await pumpSetup(
      tester,
      overrides: [
        watchConfigSyncProvider.overrideWithValue(
          FakeWatchConfigSync(pending: _offered),
        ),
      ],
    );

    await tapOnWatch(tester, find.text('Sprawdź ponownie'));
    await tester.pumpAndSettle();

    // The name and the auth mode, so the user can tell this is the server they
    // meant — a phone that switched servers used to reconfigure the watch with
    // nothing on screen to say so.
    expect(find.text('Z telefonu'), findsOneWidget);
    expect(find.text('Workshop'), findsOneWidget);
    expect(find.text('Klucz'), findsOneWidget);
    expect(find.text('Użyj tego serwera'), findsOneWidget);
    // The way out of the offer sits under the button that takes it — a scroll
    // away on a face this size.
    await revealOnWatch(tester, find.text('Nie teraz'));
    expect(find.text('Nie teraz'), findsOneWidget);
  });

  testWidgets('"not now" hands the screen back, it does not apply anything', (
    tester,
  ) async {
    await pumpSetup(
      tester,
      overrides: [
        watchConfigSyncProvider.overrideWithValue(
          FakeWatchConfigSync(pending: _offered),
        ),
      ],
    );
    await tapOnWatch(tester, find.text('Sprawdź ponownie'));
    await tester.pumpAndSettle();

    await tapOnWatch(tester, find.text('Nie teraz'));
    await tester.pumpAndSettle();

    expect(find.text('Użyj tego serwera'), findsNothing);
    expect(find.text('Ustaw z telefonu'), findsOneWidget);
    await revealOnWatch(tester, find.text('Wpisz ręcznie'));
    expect(find.text('Wpisz ręcznie'), findsOneWidget);
  });

  testWidgets('a failed adopt gives the spinner back, not a dead screen', (
    tester,
  ) async {
    await pumpSetup(
      tester,
      overrides: [
        watchConfigSyncProvider.overrideWithValue(
          FakeWatchConfigSync(pending: _offered, failsToApply: true),
        ),
      ],
    );
    await tapOnWatch(tester, find.text('Sprawdź ponownie'));
    await tester.pumpAndSettle();

    await tapOnWatch(tester, find.text('Użyj tego serwera'));
    await tester.pumpAndSettle();

    // Persisting is a secure-storage write, and that throws outright rather
    // than hanging — a timeout alone would leave the user watching a spinner.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('keystore'), findsOneWidget);
    expect(find.text('Użyj tego serwera'), findsOneWidget);
  });

  testWidgets('demo needs one tap and no keyboard at all', (tester) async {
    // The watch has no usable keyboard of its own (see WearTextInput), so the
    // reviewer's "type demo / demo / demo1234" is three trips through the input
    // activity. This button is the whole flow, and it goes through the shared
    // setup controller rather than writing a profile of its own.
    final container = await pumpSetup(tester);

    await tapOnWatch(tester, find.text('Demo'));
    await tester.pumpAndSettle();

    final profile = container.read(serverProfileProvider);
    expect(profile?.isDemo, isTrue);
    expect(profile?.label, 'Demo');
  });

  testWidgets('a demo that cannot be saved says so instead of going quiet', (
    tester,
  ) async {
    // Demo runs in-process, so nothing here is a network step — but writing the
    // profile is still a disk write, and it throws rather than reporting itself
    // through the controller's error field. On a screen whose only other route
    // needs the watch keyboard, a button that just comes back is a dead end.
    await pumpSetup(
      tester,
      overrides: [
        settingsRepositoryProvider.overrideWith(
          (ref) => _UnwritableSettings(ref.watch(sharedPreferencesProvider)),
        ),
      ],
    );

    await tapOnWatch(tester, find.text('Demo'));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Demo'), findsOneWidget);
    // Upwards, unlike [revealOnWatch]: reaching the button left the list at the
    // bottom, and the message belongs with the explanation at the top.
    await tester.scrollUntilVisible(
      find.textContaining('prefs are gone'),
      -40,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('prefs are gone'), findsOneWidget);
  });

  testWidgets('manual entry reveals the URL field', (tester) async {
    await pumpSetup(tester);

    await tapOnWatch(tester, find.text('Wpisz ręcznie'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Adres serwera'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Połącz'), findsOneWidget);
  });

  testWidgets('the URL field takes no focus and types through the watch', (
    tester,
  ) async {
    entered = 'http://printer.local:8000';
    await pumpSetup(tester);
    await tapOnWatch(tester, find.text('Wpisz ręcznie'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Adres serwera'),
    );
    expect(field.readOnly, isTrue);
    expect(field.canRequestFocus, isFalse);

    await tapOnWatch(tester, find.widgetWithText(TextField, 'Adres serwera'));
    await tester.pumpAndSettle();

    expect(
      calls.map((c) => c.method),
      containsAllInOrder(<String>['isSupported', 'requestText']),
    );
    expect(calls.last.arguments, {'label': 'Adres serwera'});
    expect(find.text('http://printer.local:8000'), findsOneWidget);
  });

  testWidgets('backing out of the watch input keeps the old value', (
    tester,
  ) async {
    entered = null;
    await pumpSetup(tester);
    await tapOnWatch(tester, find.text('Wpisz ręcznie'));
    await tester.pumpAndSettle();
    await tapOnWatch(tester, find.widgetWithText(TextField, 'Adres serwera'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Adres serwera'),
    );
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('falls back to an editable field where there is no watch input', (
    tester,
  ) async {
    isWatch = false;
    await pumpSetup(tester);
    await tapOnWatch(tester, find.text('Wpisz ręcznie'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Adres serwera'),
    );
    expect(field.readOnly, isFalse);
    expect(calls.map((c) => c.method), isNot(contains('requestText')));
  });
}

/// Preferences that refuse the one write demo mode makes, the way a disk with
/// no room left does.
class _UnwritableSettings extends SettingsRepository {
  _UnwritableSettings(super.prefs);

  @override
  Future<void> saveProfile(ServerProfile profile) async =>
      throw Exception('prefs are gone');
}
