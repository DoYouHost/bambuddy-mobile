import 'dart:async';

import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/wear/screens/wear_printer_control_screen.dart';
import 'package:bambuddy_mobile/wear/wear_fleet_cache.dart';
import 'package:bambuddy_mobile/wear/wear_providers.dart';
import 'package:bambuddy_mobile/wear/wear_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

/// A relay that has been asked but has not answered — the 4 s the phone gets
/// before the watch gives up on it, which is the whole window this feature
/// exists to fill.
class _HangingTransport implements WearTransport {
  final _answer = Completer<WearFleet>();
  int calls = 0;

  void answerWith(WearFleet fleet) => _answer.complete(fleet);

  void failWith(Object error) => _answer.completeError(error);

  @override
  Future<WearFleet> getFleet() {
    calls++;
    return _answer.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not this test\'s');
}

const _printerName = 'X1C';

Map<String, dynamic> _wire({int progress = 42}) => {
  'printers': [
    {
      'printer': {'id': 7, 'name': _printerName},
      'status': {
        'id': 7,
        'connected': true,
        'state': 'RUNNING',
        'progress': progress,
      },
    },
  ],
  'queuePending': 0,
};

/// A cache already holding last run's fleet.
///
/// A stub rather than a seeded `SharedPreferences`, because [pumpWear] resets
/// the mock store to empty on its way in — and what these tests are about is
/// what the notifier and the screen do *given* a cache. That the real one reads
/// and writes prefs correctly is `wear_fleet_cache_test.dart`.
class _SeededCache implements WearFleetCache {
  _SeededCache([this._fleet]);

  final WearFleet? _fleet;

  @override
  WearFleet? load(ServerProfile? profile) => _fleet;

  @override
  Future<void> save(WearFleet fleet, ServerProfile? profile) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not this test\'s');
}

/// The cache override plus the hanging relay behind it — the cold-start shape
/// all three widget tests set up.
List<Override> _coldStart(WearTransport transport, {WearFleet? cached}) => [
  fakeServerProfileOverride(),
  wearFleetCacheProvider.overrideWithValue(_SeededCache(cached)),
  wearTransportProvider.overrideWithValue(
    HybridWearTransport.restOnly(transport),
  ),
];

void main() {
  testWidgets('cold start paints the cached fleet instead of a spinner, '
      'dimmed until the poll lands', (tester) async {
    final transport = _HangingTransport();

    await pumpWear(
      tester,
      const WearPrinterControlBody(printerId: 7),
      overrides: _coldStart(
        transport,
        cached: wearFleetFromJson(_wire(progress: 42), stale: true),
      ),
    );

    // The poll is still out — and the printer is already on screen.
    expect(transport.calls, 1);
    expect(find.text(_printerName), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(_dimOpacity(tester), 0.6);

    transport.answerWith(wearFleetFromJson(_wire(progress: 80)));
    await tester.pumpAndSettle();

    // Fresh data: same screen, no longer dimmed.
    expect(find.text(_printerName), findsOneWidget);
    expect(_dimOpacity(tester), isNull);
  });

  testWidgets('a failed poll leaves the stale frame up and still refreshable', (
    tester,
  ) async {
    final transport = _HangingTransport();

    await pumpWear(
      tester,
      const WearPrinterControlBody(printerId: 7),
      overrides: _coldStart(
        transport,
        cached: wearFleetFromJson(_wire(), stale: true),
      ),
    );

    transport.failWith(StateError('phone unreachable'));
    await tester.pumpAndSettle();

    // Dimmed, not blanked and not frozen: `wearDimIfStale` takes no pointers
    // away, so pull-to-refresh is still the way out of a server that is down.
    expect(find.text(_printerName), findsOneWidget);
    expect(_dimOpacity(tester), 0.6);
  });

  testWidgets('no command may be sent from a cached frame', (tester) async {
    final transport = _HangingTransport();

    await pumpWear(
      tester,
      const WearPrinterControlBody(printerId: 7),
      overrides: _coldStart(
        transport,
        cached: wearFleetFromJson(_wire(), stale: true),
      ),
    );

    // A printing X1C: Pause and Stop are both on offer, and both act on a job
    // this frame only remembers.
    expect(find.byType(FilledButton), findsWidgets);
    expect(
      _enabledButtons(tester),
      isEmpty,
      reason: 'a Stop aimed at the last run can land on whatever prints now',
    );
    // And it says why, rather than greying out with no explanation.
    expect(find.text(plWearWaitingForState), findsOneWidget);

    transport.answerWith(wearFleetFromJson(_wire(progress: 80)));
    await tester.pumpAndSettle();

    // Live again: the buttons come back and the line goes away.
    expect(_enabledButtons(tester), isNotEmpty);
    expect(find.text(plWearWaitingForState), findsNothing);
  });

  testWidgets('with no cache the first frame is the spinner it always was', (
    tester,
  ) async {
    final transport = _HangingTransport();

    // No cache: `_SeededCache` answers null, exactly as the real one does on a
    // first run or after a server switch.
    await pumpWear(
      tester,
      const WearPrinterControlBody(printerId: 7),
      overrides: _coldStart(transport),
    );

    expect(find.text(_printerName), findsNothing);

    transport.answerWith(wearFleetFromJson(_wire()));
    await tester.pumpAndSettle();

    expect(find.text(_printerName), findsOneWidget);
    expect(_dimOpacity(tester), isNull);
  });

  test(
    'a successful poll writes the cache the next cold start reads',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final transport = _HangingTransport();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          fakeServerProfileOverride(),
          wearTransportProvider.overrideWithValue(
            HybridWearTransport.restOnly(transport),
          ),
        ],
      );
      addTearDown(container.dispose);

      final first = container.listen(wearFleetProvider, (_, _) {});
      transport.answerWith(wearFleetFromJson(_wire()));
      await container.read(wearFleetProvider.future);
      // The write is deliberately not awaited by the poll, so let it land.
      await pumpEventQueue();
      first.close();

      expect(
        container
            .read(wearFleetCacheProvider)
            .load(container.read(serverProfileProvider)),
        isNotNull,
      );
    },
  );
}

/// `pumpWear` runs the tree in Polish (`plApp`), so this is what the waiting
/// line reads as on screen.
const plWearWaitingForState = 'Oczekiwanie na aktualny stan';

/// Every command button that would actually fire if tapped. `FilledButton` is
/// what every action on this screen is built from — the disabled placeholders
/// among them are exactly the ones this counts as off.
Iterable<FilledButton> _enabledButtons(WidgetTester tester) => tester
    .widgetList<FilledButton>(find.byType(FilledButton))
    .where((b) => b.onPressed != null);

/// The opacity `wearDimIfStale` applied, or null when it applied none. Read off
/// the tree rather than asserted as a widget type, so the test says what the
/// user sees rather than which widget was used to say it.
double? _dimOpacity(WidgetTester tester) {
  final opacities = tester.widgetList<Opacity>(find.byType(Opacity));
  for (final o in opacities) {
    if (o.opacity < 1.0) return o.opacity;
  }
  return null;
}
