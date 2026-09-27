import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/watch/watch_config_sync.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/wear/wear_app.dart';
import 'package:bambuddy_mobile/wear/wear_providers.dart';
import 'package:bambuddy_mobile/wear/wear_transport.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// What an incoming config is allowed to do on its own.
///
/// The phone pushes its profile on every launch, and this app used to apply
/// every one of those straight into the watch's storage — so a phone that had
/// moved to another server silently moved the watch with it, with nothing on
/// screen saying which server it was now on.

const _workshop = ServerProfile(
  baseUrl: 'http://workshop.local:8000',
  authMode: AuthMode.apiKey,
  label: 'Workshop',
);

const _garage = ServerProfile(
  baseUrl: 'http://garage.local:8000',
  authMode: AuthMode.apiKey,
  label: 'Garage',
);

WatchConfig _configFor(ServerProfile profile, {String key = 'bb_secret'}) =>
    WatchConfig(profile: profile, apiKey: key);

/// Counts how often the profile is read back, which is what an invalidate
/// costs — every provider built on it goes with it.
class _CountingProfile extends ServerProfileNotifier {
  _CountingProfile(this._profile);

  final ServerProfile? _profile;
  int builds = 0;

  @override
  ServerProfile? build() {
    builds++;
    return _profile;
  }
}

void main() {
  late FakeWatchConfigSync sync;

  setUp(() => sync = FakeWatchConfigSync());

  tearDown(() => sync.pushes.close());

  /// `WearApp` brings its own MaterialApp, so no `plApp` wrapper.
  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    ServerProfile? profile,
    ServerProfileNotifier? notifier,
  }) => pumpWear(
    tester,
    const WearApp(),
    wrapInApp: false,
    overrides: [
      if (notifier != null)
        serverProfileProvider.overrideWith(() => notifier)
      else
        serverProfileOverride(profile),
      watchConfigSyncProvider.overrideWithValue(sync),
      // The fake's empty fleet keeps `WearHome` off the network: it renders
      // its "no printers" message instead of polling.
      wearTransportProvider.overrideWith(
        (ref) => HybridWearTransport(relay: FakeWearTransport()),
      ),
    ],
  );

  testWidgets('a push for the server already running is adopted silently', (
    tester,
  ) async {
    final container = await pumpApp(tester, profile: _workshop);

    // Same server, fresh secret — this is how a rotated JWT reaches the watch,
    // and stopping to ask about it would be noise on every phone launch.
    sync.pushes.add(_configFor(_workshop, key: 'bb_rotated'));
    await tester.pumpAndSettle();

    expect(sync.applied.single.apiKey, 'bb_rotated');
    expect(container.read(pendingWatchConfigProvider), isNull);
  });

  testWidgets('a push naming another server is offered, never applied', (
    tester,
  ) async {
    final container = await pumpApp(tester, profile: _workshop);

    sync.pushes.add(_configFor(_garage));
    await tester.pumpAndSettle();

    expect(sync.applied, isEmpty);
    expect(container.read(pendingWatchConfigProvider)?.profile.label, 'Garage');
  });

  testWidgets('the config it is already running is not re-read', (
    tester,
  ) async {
    final profile = _CountingProfile(_workshop);
    await pumpApp(tester, notifier: profile);
    expect(profile.builds, 1);

    // Re-reading the profile rebuilds `wearTransportProvider` with it, which
    // disposes the relay's reply listener under whatever request is on the
    // bridge — and the phone pushes this same config at every launch, so that
    // was a relay timeout charged to every cold start. The rotated secret it
    // carries needs no re-read: `authHeaders` reads the store per request.
    sync.pushes.add(_configFor(_workshop, key: 'bb_rotated'));
    await tester.pumpAndSettle();

    expect(sync.applied.single.apiKey, 'bb_rotated');
    expect(profile.builds, 1, reason: 'nothing about the server changed');
  });

  testWidgets('adopting a different server does re-read it', (tester) async {
    final profile = _CountingProfile(_workshop);
    final container = await pumpApp(tester, notifier: profile);

    // The switch the setup screen offers, taken.
    await container
        .read(pendingWatchConfigProvider.notifier)
        .adopt(_configFor(_garage));
    await tester.pumpAndSettle();

    expect(profile.builds, 2);
  });

  testWidgets('with nothing configured the push still waits for a tap', (
    tester,
  ) async {
    final container = await pumpApp(tester);

    sync.pushes.add(_configFor(_workshop));
    await tester.pumpAndSettle();

    expect(sync.applied, isEmpty);
    expect(container.read(pendingWatchConfigProvider), isNotNull);
    // And the setup screen is what shows it. English here, not Polish: this
    // pumps `WearApp`, which builds its own MaterialApp on the system locale,
    // rather than the `plApp` harness the other wear tests wrap widgets in.
    await revealOnWatch(tester, find.text('Use this server'));
    expect(find.text('Use this server'), findsOneWidget);
  });
}
