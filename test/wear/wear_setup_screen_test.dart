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

/// What a fresh watch offers: the phone handoff and the demo, and nothing to
/// type (Play's WO-P6).

final _offered = WatchConfig(
  profile: const ServerProfile(
    baseUrl: 'http://workshop.local:8000',
    authMode: AuthMode.apiKey,
    label: 'Workshop',
  ),
  apiKey: 'bb_secret',
);

void main() {
  const phoneAppChannel = MethodChannel(
    'page.codeberg.morganmlgman.bambuddy/wear_phone_app',
  );
  final phoneCalls = <String>[];
  bool? phoneHasApp;
  var storeOpens = true;

  setUp(() {
    phoneCalls.clear();
    phoneHasApp = null;
    storeOpens = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(phoneAppChannel, (call) async {
          phoneCalls.add(call.method);
          return switch (call.method) {
            'installed' => phoneHasApp,
            'openStore' => storeOpens,
            _ => null,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(phoneAppChannel, null);
  });

  Future<ProviderContainer> pumpSetup(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) => pumpWear(tester, const WearSetupScreen(), overrides: overrides);

  testWidgets('leads with the phone handoff, not with a field to type in', (
    tester,
  ) async {
    await pumpSetup(tester);

    expect(find.text(pl.wearSetupPhoneTitle), findsOneWidget);
    // Below the fold on a watch face — the check button lives under the
    // explanation, so reaching it is a scroll, not a missing button.
    await revealOnWatch(tester, find.text(pl.wearSetupPhoneCheck));
    expect(find.text(pl.wearSetupPhoneCheck), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('no button on the setup screen leads to typing on the watch '
      '(WO-P6)', (tester) async {
    // Play's WO-P6 forbids a username and password typed on the watch, and an
    // API key is the same string to type. Everything comes from the phone; the
    // demo is the one way in without it, and it needs no typing either.
    await pumpSetup(tester);
    final labels = [
      for (final button
          in find
              .byWidgetPredicate(
                (w) => w is ButtonStyleButton,
                skipOffstage: false,
              )
              .evaluate())
        for (final e in collectAllElementsFrom(button, skipOffstage: false))
          if (e.widget case Text(:final data?)) data,
    ]..remove(pl.wearSetupDemo);
    expect(labels, isNotEmpty);

    for (final label in labels) {
      await pumpSetup(tester);
      await tapOnWatch(tester, find.text(label));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing, reason: 'after "$label"');
    }
  });

  group('a phone without the app', () {
    for (final (answer, offered) in [
      (false, true),
      (true, false),
      (null, false),
    ]) {
      testWidgets('installed=$answer ${offered ? 'offers' : 'does not offer'} '
          'to install it', (tester) async {
        phoneHasApp = answer;
        await pumpSetup(tester);
        await tester.pumpAndSettle();

        // Unknown is no phone connected, or no Play services: an install
        // button there could only fail.
        expect(
          find.text(pl.wearPhoneAppInstall, skipOffstage: false),
          offered ? findsOneWidget : findsNothing,
        );
      });
    }

    testWidgets('install opens the store on the phone and says where to look', (
      tester,
    ) async {
      phoneHasApp = false;
      await pumpSetup(tester);
      await tester.pumpAndSettle();

      await tapOnWatch(tester, find.text(pl.wearPhoneAppInstall));
      await tester.pumpAndSettle();

      expect(phoneCalls, contains('openStore'));
      expect(find.text(pl.wearPhoneAppOpened), findsOneWidget);
    });

    testWidgets('says so when the phone cannot be reached', (tester) async {
      phoneHasApp = false;
      storeOpens = false;
      await pumpSetup(tester);
      await tester.pumpAndSettle();

      await tapOnWatch(tester, find.text(pl.wearPhoneAppInstall));
      await tester.pumpAndSettle();

      expect(find.text(pl.wearPhoneAppOpenFailed), findsOneWidget);
    });

    testWidgets('asks again on every check, so the answer can change', (
      tester,
    ) async {
      phoneHasApp = true;
      await pumpSetup(tester);
      await tester.pumpAndSettle();
      expect(
        find.text(pl.wearPhoneAppInstall, skipOffstage: false),
        findsNothing,
      );

      phoneHasApp = false;
      await tapOnWatch(tester, find.text(pl.wearSetupPhoneCheck));
      await tester.pumpAndSettle();

      expect(
        find.text(pl.wearPhoneAppInstall, skipOffstage: false),
        findsOneWidget,
      );
    });
  });

  testWidgets('says so when the phone has pushed nothing', (tester) async {
    await pumpSetup(tester);

    // No Data Layer under a test binding, so the check comes back empty — the
    // same answer a watch gets when the phone app was never set up.
    await tapOnWatch(tester, find.text(pl.wearSetupPhoneCheck));
    await tester.pumpAndSettle();

    expect(find.text(pl.wearSetupPhoneEmpty), findsOneWidget);
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

    await tapOnWatch(tester, find.text(pl.wearSetupPhoneCheck));
    await tester.pumpAndSettle();

    // The name and the auth mode, so the user can tell this is the server they
    // meant — a phone that switched servers used to reconfigure the watch with
    // nothing on screen to say so.
    expect(find.text(pl.wearFromPhone), findsOneWidget);
    expect(find.text('Workshop'), findsOneWidget);
    expect(find.text(pl.wearAuthKey), findsOneWidget);
    expect(find.text(pl.wearFromPhoneUse), findsOneWidget);
    // The way out of the offer sits under the button that takes it — a scroll
    // away on a face this size.
    await revealOnWatch(tester, find.text(pl.wearFromPhoneLater));
    expect(find.text(pl.wearFromPhoneLater), findsOneWidget);
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
    await tapOnWatch(tester, find.text(pl.wearSetupPhoneCheck));
    await tester.pumpAndSettle();

    await tapOnWatch(tester, find.text(pl.wearFromPhoneLater));
    await tester.pumpAndSettle();

    expect(find.text(pl.wearFromPhoneUse), findsNothing);
    expect(find.text(pl.wearSetupPhoneTitle), findsOneWidget);
    await revealOnWatch(tester, find.text(pl.wearSetupPhoneCheck));
    expect(find.text(pl.wearSetupPhoneCheck), findsOneWidget);
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
    await tapOnWatch(tester, find.text(pl.wearSetupPhoneCheck));
    await tester.pumpAndSettle();

    await tapOnWatch(tester, find.text(pl.wearFromPhoneUse));
    await tester.pumpAndSettle();

    // Persisting is a secure-storage write, and that throws outright rather
    // than hanging — a timeout alone would leave the user watching a spinner.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('keystore'), findsOneWidget);
    expect(find.text(pl.wearFromPhoneUse), findsOneWidget);
  });

  testWidgets('demo needs one tap and no keyboard at all', (tester) async {
    // Nothing is typed on the watch, so the reviewer's "demo / demo / demo1234"
    // is this button. It goes through the shared setup controller rather than
    // writing a profile of its own.
    final container = await pumpSetup(tester);

    await tapOnWatch(tester, find.text(pl.wearSetupDemo));
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

    await tapOnWatch(tester, find.text(pl.wearSetupDemo));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(pl.wearSetupDemo), findsOneWidget);
    // Upwards, unlike [revealOnWatch]: reaching the button left the list at the
    // bottom, and the message belongs with the explanation at the top.
    await tester.scrollUntilVisible(
      find.textContaining('prefs are gone'),
      -40,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('prefs are gone'), findsOneWidget);
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
