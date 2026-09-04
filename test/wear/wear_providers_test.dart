import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/wear/wear_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../helpers/fake_watch_connectivity.dart';

import '../helpers.dart';

void main() {
  test(
      'wearTransportProvider survives being only read '
      '(autoDispose killed the reply listener mid-request)', () async {
    final container = ProviderContainer(overrides: [
      watchConnectivityProvider.overrideWithValue(FakeWatchConnectivity()),
      noServerProfileOverride,
    ]);
    addTearDown(container.dispose);

    final first = container.read(wearTransportProvider);
    // With autoDispose an unlistened provider is torn down right here —
    // cancelling the relay's reply subscription while a call is in flight.
    await pumpEventQueue();
    final second = container.read(wearTransportProvider);

    expect(identical(first, second), isTrue);
  });
}
