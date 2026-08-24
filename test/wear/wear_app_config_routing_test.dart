import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/watch/watch_config_sync.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
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

class _ProfileOn extends ServerProfileNotifier {
  _ProfileOn(this._profile);

  final ServerProfile? _profile;

  @override
  ServerProfile? build() => _profile;
}

/// An empty fleet keeps `WearHome` off the network: it renders its "no printers"
/// message instead of polling.
class _EmptyTransport implements WearTransport {
  @override
  Future<WearFleet> getFleet() async => const WearFleet(printers: <PrinterWithStatus>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not this test\'s');
}

const _workshop = ServerProfile(
  baseUrl: 'http://workshop.local:8000',
  authMode: AuthMode.apiKey,
  label: 'Workshop',
);

WatchConfig _configFor(ServerProfile profile, {String key = 'bb_secret'}) =>
    WatchConfig(profile: profile, apiKey: key);

void main() {
  late FakeWatchConfigSync sync;

  setUp(() => sync = FakeWatchConfigSync());

  tearDown(() => sync.pushes.close());

  /// `WearApp` brings its own MaterialApp, so no `plApp` wrapper.
  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    ServerProfile? profile,
  }) =>
      pumpWear(
        tester,
        const WearApp(),
        wrapInApp: false,
        overrides: [
          serverProfileProvider.overrideWith(() => _ProfileOn(profile)),
          watchConfigSyncProvider.overrideWithValue(sync),
          wearTransportProvider.overrideWith(
              (ref) => HybridWearTransport(relay: _EmptyTransport())),
        ],
      );

  testWidgets('a push for the server already running is adopted silently',
      (tester) async {
    final container = await pumpApp(tester, profile: _workshop);

    // Same server, fresh secret — this is how a rotated JWT reaches the watch,
    // and stopping to ask about it would be noise on every phone launch.
    sync.pushes.add(_configFor(_workshop, key: 'bb_rotated'));
    await tester.pumpAndSettle();

    expect(sync.applied.single.apiKey, 'bb_rotated');
    expect(container.read(pendingWatchConfigProvider), isNull);
  });

  testWidgets('a push naming another server is offered, never applied',
      (tester) async {
    final container = await pumpApp(tester, profile: _workshop);

    sync.pushes.add(_configFor(const ServerProfile(
        baseUrl: 'http://garage.local:8000',
        authMode: AuthMode.apiKey,
        label: 'Garage')));
    await tester.pumpAndSettle();

    expect(sync.applied, isEmpty);
    expect(container.read(pendingWatchConfigProvider)?.profile.label, 'Garage');
  });

  testWidgets('with nothing configured the push still waits for a tap',
      (tester) async {
    final container = await pumpApp(tester);

    sync.pushes.add(_configFor(_workshop));
    await tester.pumpAndSettle();

    expect(sync.applied, isEmpty);
    expect(container.read(pendingWatchConfigProvider), isNotNull);
    // And the setup screen is what shows it. English here, not Polish: this
    // pumps `WearApp`, which builds its own MaterialApp on the system locale,
    // rather than the `plApp` harness the other wear tests wrap widgets in.
    expect(find.text('Use this server'), findsOneWidget);
  });
}
