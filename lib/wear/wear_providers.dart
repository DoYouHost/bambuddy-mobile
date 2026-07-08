import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'wear_status.dart';
import 'wear_transport.dart';

/// Transport for everything the watch asks of the server: relay through the
/// phone (Data Layer/BT) first, direct REST as fallback — see plan 05.
///
/// Deliberately NOT autoDispose: callers only ever `read` it, and an
/// autoDispose provider with no listeners is disposed right after creation —
/// which cancelled the relay's reply listener while a request was in flight
/// (command executed on the phone, watch reported a timeout). It also has to
/// keep [HybridWearTransport.lastMode] across polls for the adaptive cadence.
final wearTransportProvider = Provider<HybridWearTransport>((ref) {
  final relay = RelayTransport(ref.watch(watchConnectivityProvider));
  ref.onDispose(relay.dispose);
  // REST needs a configured profile; without one (relay-only watch) the
  // repositories can't even be constructed (apiClientProvider throws).
  final hasProfile = ref.watch(serverProfileProvider) != null;
  return HybridWearTransport(
    relay: relay,
    rest: hasProfile
        ? RestTransport(
            printers: ref.watch(printersRepositoryProvider),
            commands: ref.watch(printerCommandsRepositoryProvider),
            queue: ref.watch(queueRepositoryProvider),
          )
        : null,
  );
});

/// Fleet of printers with status, polled through [wearTransportProvider].
/// No WebSocket or background service on the watch (deliberate — battery);
/// the poll runs only while a screen watching it is mounted (autoDispose).
final wearFleetProvider =
    AsyncNotifierProvider.autoDispose<WearFleetNotifier, WearFleet>(
  WearFleetNotifier.new,
);

class WearFleetNotifier extends AutoDisposeAsyncNotifier<WearFleet> {
  Timer? _timer;
  bool _disposed = false;

  @override
  Future<WearFleet> build() async {
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
    });
    final fleet = await _fetch();
    _scheduleNext(fleet);
    return fleet;
  }

  Future<WearFleet> _fetch() => ref.read(wearTransportProvider).getFleet();

  /// Adaptive cadence: every relay poll wakes the phone over the bridge, so
  /// back off to 30 s when nothing is actively printing. Direct REST (or an
  /// active print) keeps the familiar 5 s.
  void _scheduleNext(WearFleet? fleet) {
    if (_disposed) return;
    final relaying = ref.read(wearTransportProvider).lastMode ==
        WearTransportMode.relay;
    final active = fleet?.printers.any((p) => switch (wearStateOf(p.status)) {
              WearState.printing || WearState.paused => true,
              _ => false,
            }) ??
        // Unknown fleet (fetch failed) → poll fast to recover quickly.
        true;
    final interval = relaying && !active
        ? const Duration(seconds: 30)
        : const Duration(seconds: 5);
    _timer?.cancel();
    _timer = Timer(interval, refresh);
  }

  /// Re-fetch in the background; keeps the last good data visible on transient
  /// errors instead of blanking the screen.
  Future<void> refresh() async {
    final next = await AsyncValue.guard(_fetch);
    if (_disposed) return;
    // Only surface an error if we have nothing to show; otherwise keep old data.
    if (!(next.hasError && state.hasValue)) {
      state = next;
    }
    _scheduleNext(next.valueOrNull ?? state.valueOrNull);
  }
}

/// Controller for the watch actions. Stateless facade over the transport;
/// callers manage their own in-flight/error UI.
final wearActionsProvider = Provider.autoDispose<WearActions>(
  (ref) => WearActions(ref),
);

class WearActions {
  WearActions(this._ref);

  final Ref _ref;

  WearTransport get _transport => _ref.read(wearTransportProvider);

  Future<void> pause(int printerId) => _transport.pause(printerId);

  Future<void> resume(int printerId) => _transport.resume(printerId);

  Future<void> stop(int printerId) => _transport.stop(printerId);

  Future<void> clearPlate(int printerId) => _transport.clearPlate(printerId);

  /// Start the next pending queue item on [printerId] (assign-then-start —
  /// see [QueueRepository.startNextPending], relayed or direct). Surfaces
  /// [StateError] `empty-queue` when the queue has nothing pending.
  Future<void> startNext(int printerId) => _transport.startNext(printerId);
}
