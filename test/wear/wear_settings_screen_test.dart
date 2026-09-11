import 'dart:async';

import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/watch/watch_config_sync.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/wear/screens/wear_settings_screen.dart';
import 'package:bambuddy_mobile/wear/wear_providers.dart';
import 'package:bambuddy_mobile/wear/widgets/wear_confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../helpers.dart';

/// The screen that had to exist: a watch which had connected once was married to
/// that server for good, with nothing on the device able to change or forget it.
class _FakeProfile extends ServerProfileNotifier {
  _FakeProfile();

  bool cleared = false;

  @override
  ServerProfile? build() => const ServerProfile(
    baseUrl: 'http://workshop.local:8000',
    authMode: AuthMode.apiKey,
    label: 'Workshop',
  );

  @override
  Future<void> clear() async {
    cleared = true;
    state = null;
  }
}

WatchConfig _configFor(String host, {String? label}) => WatchConfig(
  profile: ServerProfile(
    baseUrl: 'http://$host:8000',
    authMode: AuthMode.apiKey,
    label: label,
  ),
  apiKey: 'bb_secret',
);

void main() {
  late _FakeProfile profile;
  late FakeWatchConfigSync sync;

  setUp(() {
    profile = _FakeProfile();
    sync = FakeWatchConfigSync();
    PackageInfo.setMockInitialValues(
      appName: 'bambuddy',
      packageName: 'page.codeberg.morganmlgman.bambuddy_mobile',
      version: '0.14.0',
      buildNumber: '2028000',
      buildSignature: '',
    );
  });

  Future<ProviderContainer> pumpSettings(
    WidgetTester tester, {
    WatchConfig? offered,
    String? serverVersion,
  }) async {
    final container = await pumpWear(
      tester,
      const WearSettingsScreen(),
      overrides: [
        serverProfileProvider.overrideWith(() => profile),
        watchConfigSyncProvider.overrideWithValue(sync),
        // Without this the footer would reach for the phone over a Data Layer
        // that is not there, and the screen's own tests would wait out its
        // timeout.
        wearServerVersionProvider.overrideWith((ref) => serverVersion),
      ],
    );
    if (offered != null) {
      container.read(pendingWatchConfigProvider.notifier).offer(offered);
      await tester.pumpAndSettle();
    }
    return container;
  }

  testWidgets('names the server the watch is on', (tester) async {
    await pumpSettings(tester);

    expect(find.text('Obecny serwer'), findsOneWidget);
    expect(find.text('Workshop'), findsOneWidget);
    expect(find.text('Zmień serwer'), findsOneWidget);
    // The consequence is on the screen, not hidden in the dialog: the shared
    // wear dialog clips its subtitle to one line. Under the button, so on a
    // small face it is a scroll away.
    await revealOnWatch(
      tester,
      find.text('Zapisany profil i poświadczenia zostaną usunięte.'),
    );
    expect(
      find.text('Zapisany profil i poświadczenia zostaną usunięte.'),
      findsOneWidget,
    );
  });

  testWidgets('change server asks first, and a refusal changes nothing', (
    tester,
  ) async {
    await pumpSettings(tester);

    await tapOnWatch(tester, find.text('Zmień serwer'));
    await tester.pumpAndSettle();
    expect(find.byType(WearConfirmDialog), findsOneWidget);
    // Named inside the question, so it is clear which server is being dropped —
    // the screen behind it carries the same name, hence the descendant match.
    expect(
      find.descendant(
        of: find.byType(WearConfirmDialog),
        matching: find.text('Workshop'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(profile.cleared, isFalse);
  });

  testWidgets('confirming drops the profile and every secret', (tester) async {
    await pumpSettings(tester);

    await tapOnWatch(tester, find.text('Zmień serwer'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pumpAndSettle();

    expect(profile.cleared, isTrue);
  });

  testWidgets('offers the server the phone sent, when it is a different one', (
    tester,
  ) async {
    await pumpSettings(tester, offered: _configFor('garage', label: 'Garage'));

    expect(find.text('Telefon proponuje inny serwer.'), findsOneWidget);

    await tapOnWatch(tester, find.text('Użyj tego serwera'));
    await tester.pumpAndSettle();

    expect(sync.applied.single.profile.label, 'Garage');
  });

  testWidgets('a double tap on the switch writes once, not twice', (
    tester,
  ) async {
    final gate = Completer<void>();
    sync = FakeWatchConfigSync(applyGate: gate);
    await pumpSettings(tester, offered: _configFor('garage', label: 'Garage'));

    await tapOnWatch(tester, find.text('Użyj tego serwera'));
    await tester.pump();
    // The button is gone while the write runs, so the second tap has nothing to
    // hit — two concurrent writes of the same secrets is not a race worth having.
    expect(find.text('Użyj tego serwera'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(sync.applied, hasLength(1));
  });

  testWidgets('leaving mid-write does not touch a disposed widget', (
    tester,
  ) async {
    final gate = Completer<void>();
    sync = FakeWatchConfigSync(applyGate: gate);
    await pumpSettings(tester, offered: _configFor('garage', label: 'Garage'));

    await tapOnWatch(tester, find.text('Użyj tego serwera'));
    await tester.pump();

    // Swipe-to-dismiss is a sideways swipe on Wear OS, so leaving mid-write is
    // an easy accident. Replacing the tree is this test's version of it.
    await tester.pumpWidget(plApp(const SizedBox.shrink()));
    gate.complete();
    await tester.pumpAndSettle();

    // `ref` on a disposed widget throws rather than no-oping, so an unguarded
    // continuation lands here as a test failure.
    expect(tester.takeException(), isNull);
  });

  testWidgets('says nothing about an offer for the server already running', (
    tester,
  ) async {
    // The phone pushes on every launch, and most of those name the server the
    // watch is already on — surfacing that as a switch would be noise.
    await pumpSettings(
      tester,
      offered: _configFor('workshop.local', label: 'Workshop'),
    );

    expect(find.text('Telefon proponuje inny serwer.'), findsNothing);
    expect(find.text('Użyj tego serwera'), findsNothing);
  });

  testWidgets('the footer carries both versions', (tester) async {
    // The two numbers every report starts with, on the watch's one screen
    // that is not a control.
    await pumpSettings(tester, serverVersion: '1.2.6b1');
    await tester.pumpAndSettle();

    await revealOnWatch(tester, find.text('Aplikacja 0.14.0+2028000'));
    expect(find.text('Aplikacja 0.14.0+2028000'), findsOneWidget);
    await revealOnWatch(tester, find.text('Serwer 1.2.6b1'));
    expect(find.text('Serwer 1.2.6b1'), findsOneWidget);
  });

  testWidgets('a phone or server that answers nothing says so', (tester) async {
    // An older phone cannot decode the action and stays silent; an older
    // server has no version route. Both are one sentence to the reader.
    await pumpSettings(tester);
    await tester.pumpAndSettle();

    await revealOnWatch(tester, find.text('Nieznana wersja serwera'));
    expect(find.text('Nieznana wersja serwera'), findsOneWidget);
  });

  testWidgets('the longest version there is stays on the glass', (
    tester,
  ) async {
    // A daily build is the longest string this footer can ever be handed.
    //
    // Deliberately NOT an assertion about ellipsis: a widget test renders in
    // the test font, whose digits are a full em wide, while the watch renders
    // in the platform font at a bit over half that — measured here, the
    // unbreakable run `0.14.0+2028000` comes to 143.5 dp against a 141.8 dp
    // viewport in the test font and around 80 dp on the device. Pinning pixels
    // would be pinning a font the app never uses. What does carry over is the
    // geometry: the line has to sit inside the circle, which is the failure
    // that actually cut a Pause button's ends once.
    await pumpSettings(tester, serverVersion: '1.2.6b1-daily.20260729');
    await tester.pumpAndSettle();

    for (final line in [
      'Aplikacja 0.14.0+2028000',
      'Serwer 1.2.6b1-daily.20260729',
    ]) {
      await revealOnWatch(tester, find.text(line));
      expectOnGlass(tester, find.text(line), reason: line);
    }
  });
}
