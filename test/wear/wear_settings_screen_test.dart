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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_connectivity/watch_connectivity.dart';

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

class _RecordingConfigSync extends WatchConfigSync {
  _RecordingConfigSync({this.gate})
      : super(
          watch: WatchConnectivity(),
          credentials: InMemoryCredentialsStore(),
        );

  /// When set, `apply` does not finish until the test completes it — that is how
  /// a write still in flight is held open while the screen goes away.
  final Completer<void>? gate;

  final applied = <WatchConfig>[];

  @override
  Future<void> apply(WatchConfig config) async {
    applied.add(config);
    if (gate != null) await gate!.future;
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
  late _RecordingConfigSync sync;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    profile = _FakeProfile();
    sync = _RecordingConfigSync();
  });

  Future<ProviderContainer> pumpSettings(
    WidgetTester tester, {
    WatchConfig? offered,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      credentialsStoreProvider.overrideWithValue(InMemoryCredentialsStore()),
      serverProfileProvider.overrideWith(() => profile),
      watchConfigSyncProvider.overrideWithValue(sync),
    ]);
    addTearDown(container.dispose);
    if (offered != null) {
      container.read(pendingWatchConfigProvider.notifier).offer(offered);
    }
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: plApp(const WearSettingsScreen()),
    ));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('names the server the watch is on', (tester) async {
    await pumpSettings(tester);

    expect(find.text('Obecny serwer'), findsOneWidget);
    expect(find.text('Workshop'), findsOneWidget);
    expect(find.text('Zmień serwer'), findsOneWidget);
    // The consequence is on the screen, not hidden in the dialog: the shared
    // wear dialog clips its subtitle to one line.
    expect(find.text('Zapisany profil i poświadczenia zostaną usunięte.'),
        findsOneWidget);
  });

  testWidgets('change server asks first, and a refusal changes nothing',
      (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Zmień serwer'));
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

    await tester.tap(find.text('Zmień serwer'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pumpAndSettle();

    expect(profile.cleared, isTrue);
  });

  testWidgets('offers the server the phone sent, when it is a different one',
      (tester) async {
    await pumpSettings(tester, offered: _configFor('garage', label: 'Garage'));

    expect(find.text('Telefon proponuje inny serwer.'), findsOneWidget);

    await tester.tap(find.text('Użyj tego serwera'));
    await tester.pumpAndSettle();

    expect(sync.applied.single.profile.label, 'Garage');
  });

  testWidgets('a double tap on the switch writes once, not twice',
      (tester) async {
    final gate = Completer<void>();
    sync = _RecordingConfigSync(gate: gate);
    await pumpSettings(tester, offered: _configFor('garage', label: 'Garage'));

    await tester.tap(find.text('Użyj tego serwera'));
    await tester.pump();
    // The button is gone while the write runs, so the second tap has nothing to
    // hit — two concurrent writes of the same secrets is not a race worth having.
    expect(find.text('Użyj tego serwera'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(sync.applied, hasLength(1));
  });

  testWidgets('leaving mid-write does not touch a disposed widget',
      (tester) async {
    final gate = Completer<void>();
    sync = _RecordingConfigSync(gate: gate);
    await pumpSettings(tester, offered: _configFor('garage', label: 'Garage'));

    await tester.tap(find.text('Użyj tego serwera'));
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

  testWidgets('says nothing about an offer for the server already running',
      (tester) async {
    // The phone pushes on every launch, and most of those name the server the
    // watch is already on — surfacing that as a switch would be noise.
    await pumpSettings(tester,
        offered: _configFor('workshop.local', label: 'Workshop'));

    expect(find.text('Telefon proponuje inny serwer.'), findsNothing);
    expect(find.text('Użyj tego serwera'), findsNothing);
  });
}
