import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/watch/watch_config_sync.dart';
import '../providers.dart';
import 'wear_fleet_cache.dart';
import 'wear_status.dart';
import 'wear_transport.dart';

/// Config the phone has pushed but the watch has not adopted — either it has no
/// profile yet, or the push names a different server than the one running. Kept
/// here so the setup screen can ask before switching and the settings screen can
/// offer the switch later; [WearApp] is what fills it.
///
/// Nothing is persisted: the Data Layer latches the last context itself, so a
/// dropped offer is re-read from there on the next launch.
final pendingWatchConfigProvider =
    NotifierProvider<PendingWatchConfig, WatchConfig?>(PendingWatchConfig.new);

class PendingWatchConfig extends Notifier<WatchConfig?> {
  @override
  WatchConfig? build() => null;

  void offer(WatchConfig config) => state = config;

  void dismiss() => state = null;

  /// Persist [config] as this watch's server, clear the offer and re-read the
  /// profile so the app re-routes. Rethrows what secure storage threw, and a failure
  /// leaves the offer standing (docs/wear-fleet-poll.md, "Adopting a pushed config").
  Future<void> adopt(WatchConfig config) async {
    await ref.read(watchConfigSyncProvider).apply(config);
    state = null;
    // Only a changed profile is worth the invalidate: it rebuilds the transport and
    // disposes the relay's reply listener under a request already on the bridge.
    if (ref.read(serverProfileProvider) != config.profile) {
      ref.invalidate(serverProfileProvider);
    }
  }
}

/// Transport for everything the watch asks of the server: relay through the phone
/// first, direct REST as fallback. Not `autoDispose` (docs/wear-fleet-poll.md, "Transport").
final wearTransportProvider = Provider<HybridWearTransport>((ref) {
  final profile = ref.watch(serverProfileProvider);
  // REST needs a configured profile; only called on a branch that has one.
  RestTransport rest() => RestTransport(
    printers: ref.watch(printersRepositoryProvider),
    commands: ref.watch(printerCommandsRepositoryProvider),
    queue: ref.watch(queueRepositoryProvider),
    serverVersion: ref.watch(serverVersionServiceProvider),
  );
  // Demo runs in this process, so there is nothing for the phone to answer.
  if (profile != null && profile.isDemo) {
    return HybridWearTransport.restOnly(rest());
  }
  final relay = RelayTransport(ref.watch(watchConnectivityProvider));
  ref.onDispose(relay.dispose);
  return HybridWearTransport(
    relay: relay,
    rest: profile == null ? null : rest(),
  );
});

/// The connected server's version, for the settings footer. `autoDispose`: only that
/// screen asks. Never fails: every failure is one answer, `null`, because a footer
/// is not the place to explain which it was.
final wearServerVersionProvider = FutureProvider.autoDispose<String?>((
  ref,
) async {
  try {
    // Watched: an answer through the previous transport is about the previous server.
    return await ref.watch(wearTransportProvider).getServerVersion();
  } on Object {
    return null;
  }
});

/// The watch's cold-start cache. Not `autoDispose`: it carries the floor between
/// writes ([WearFleetCache.minInterval]) across polls.
final wearFleetCacheProvider = Provider<WearFleetCache>(
  (ref) => WearFleetCache(ref.watch(settingsRepositoryProvider)),
);

/// Fleet of printers with status, polled through [wearTransportProvider].
/// No WebSocket or background service on the watch (deliberate — battery);
/// the poll runs only while a screen watching it is mounted (autoDispose).
final wearFleetProvider =
    AsyncNotifierProvider.autoDispose<WearFleetNotifier, WearFleet>(
      WearFleetNotifier.new,
    );

class WearFleetNotifier extends AutoDisposeAsyncNotifier<WearFleet> {
  Timer? _timer;

  /// Which run of this notifier is the current one, bumped by every build and every
  /// poll. Not a one-way "disposed" latch (docs/wear-fleet-poll.md, "three flags and an epoch").
  int _epoch = 0;

  /// Whether the notifier is mounted at all; [_epoch] cannot answer that alone.
  bool _alive = false;

  /// Set while the app is in the background: every relay poll wakes the phone.
  /// Checked in [_scheduleNext], so a fetch in flight cannot re-arm the timer.
  bool _paused = false;

  /// Whether [epoch] is still the run this notifier is doing.
  bool _current(int epoch) => _alive && epoch == _epoch;

  @override
  Future<WearFleet> build() async {
    _alive = true;
    final epoch = ++_epoch;
    ref.onDispose(() {
      _alive = false;
      _timer?.cancel();
    });
    // Watched: switching the server empties the state and re-reads the cache for the
    // new URL.
    final profile = ref.watch(serverProfileProvider);
    final cached = ref.read(wearFleetCacheProvider).load(profile);
    if (cached != null) {
      // Painted at once, refreshed underneath through a zero-length timer, since the
      // poll may only start once `build` has returned. Not while paused: the resume
      // hook starts it (docs/wear-fleet-poll.md, "build").
      if (!_paused) _timer = Timer(Duration.zero, refresh);
      return cached;
    }
    // Fetched even while paused: `build` owes its caller a fleet (docs/wear-fleet-poll.md, "build").
    final fleet = await _fetch(epoch);
    // Superseded: arming a timer here would cancel the current run's.
    if (_current(epoch)) _scheduleNext(fleet);
    return fleet;
  }

  Future<WearFleet> _fetch(int epoch) async {
    // Read before the request: a poll answering in the same turn as a server switch
    // must not file the old fleet under the new URL.
    final profile = ref.read(serverProfileProvider);
    final fleet = await ref.read(wearTransportProvider).getFleet();
    // Not awaited, never fatal, and skipped once superseded.
    if (_current(epoch)) {
      unawaited(ref.read(wearFleetCacheProvider).save(fleet, profile));
    }
    return fleet;
  }

  /// Adaptive cadence: every relay poll wakes the phone over the bridge, so
  /// back off to 30 s when nothing is actively printing. Direct REST (or an
  /// active print) keeps the familiar 5 s.
  void _scheduleNext(WearFleet? fleet, {bool afterFailure = false}) {
    if (!_alive || _paused) return;
    final relaying =
        ref.read(wearTransportProvider).lastMode == WearTransportMode.relay;
    final active =
        fleet?.printers.any(
          (p) => switch (wearStateOf(p.status)) {
            WearState.printing || WearState.paused => true,
            _ => false,
          },
        ) ??
        // Unknown fleet (fetch failed) → poll fast to recover quickly.
        true;
    // Also slower after a failed poll that left a frame on screen (docs/wear-fleet-poll.md, "Cadence").
    final interval = (relaying && !active) || (afterFailure && fleet != null)
        ? const Duration(seconds: 30)
        : const Duration(seconds: 5);
    _timer?.cancel();
    _timer = Timer(interval, refresh);
  }

  /// Stops the poll until something asks for a [refresh] again — which is what
  /// coming back to the foreground does.
  void stopPolling() {
    _paused = true;
    _timer?.cancel();
  }

  /// Re-fetch in the background; keeps the last good data visible on transient
  /// errors instead of blanking the screen.
  ///
  /// Also the way out of [stopPolling]: every caller — the resume hook, pull to
  /// refresh, the tick after a command — means the screen is being watched
  /// again.
  Future<void> refresh() async {
    if (!_alive) return;
    // Nothing may outrun a build: what this wrote would be replaced by the build's own
    // answer. `isLoading` alone is the guard (docs/wear-fleet-poll.md, "refresh").
    if (state.isLoading) return;
    // Before anything else, or a tick armed earlier matures while this request is out.
    _timer?.cancel();
    _paused = false;
    // A fired tick cannot be cancelled; the epoch makes the older poll give way.
    final epoch = ++_epoch;
    // Whether this run has confirmed what is on screen; a cached frame has not.
    final unconfirmed = state.valueOrNull?.stale ?? false;
    final next = await AsyncValue.guard(() => _fetch(epoch));
    if (!_current(epoch)) return;

    if (next.hasError && state.hasValue && !unconfirmed) {
      // Confirmed data survives a dropped poll: one bad tick should not blank a
      // screen that was right a moment ago.
      _scheduleNext(state.valueOrNull, afterFailure: true);
      return;
    }

    // Everything else goes through as an error, the never-confirmed frame included.
    state = next;
    // After an error, the retry's rebuild starts the poll again.
    if (next.hasError) return;
    _scheduleNext(next.valueOrNull);
  }
}

/// What a screen should draw out of [wearFleetProvider]: an error is always the
/// answer, never the old frame Riverpod keeps behind it (docs/wear-fleet-poll.md, "WearFleetView.drawable").
extension WearFleetView on AsyncValue<WearFleet> {
  WearFleet? get drawable => hasError ? null : valueOrNull;
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

  /// Clear the printer's active error dialog — one command for the printer, not
  /// per fault, exactly as on the phone.
  Future<void> clearHmsErrors(int printerId) =>
      _transport.clearHmsErrors(printerId);

  /// Run one of the firmware's remediation actions. [printError] is the fault's
  /// `full_code`, passed through untouched all the way to the printer.
  Future<void> executeHmsAction(
    int printerId, {
    required String printError,
    required String action,
    String? jobId,
  }) => _transport.executeHmsAction(
    printerId,
    printError: printError,
    action: action,
    jobId: jobId,
  );
}
