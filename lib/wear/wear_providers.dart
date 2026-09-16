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
  /// profile so the app re-routes. Rethrows what secure storage threw: whether
  /// that failure becomes a red line, a spinner coming back or nothing at all is
  /// the screen's business, and only the screen knows whether it is still alive
  /// to show it — a notifier cannot check somebody else's `mounted`.
  ///
  /// Failing leaves the offer standing, so the button that started this is still
  /// there to try again.
  Future<void> adopt(WatchConfig config) async {
    await ref.read(watchConfigSyncProvider).apply(config);
    state = null;
    ref.invalidate(serverProfileProvider);
  }
}

/// Transport for everything the watch asks of the server: relay through the
/// phone (Data Layer/BT) first, direct REST as fallback — see plan 05.
///
/// Deliberately NOT autoDispose: callers only ever `read` it, and an
/// autoDispose provider with no listeners is disposed right after creation —
/// which cancelled the relay's reply listener while a request was in flight
/// (command executed on the phone, watch reported a timeout). It also has to
/// keep [HybridWearTransport.lastMode] across polls for the adaptive cadence.
final wearTransportProvider = Provider<HybridWearTransport>((ref) {
  final profile = ref.watch(serverProfileProvider);
  // REST needs a configured profile; without one (a relay-only watch) the
  // repositories can't even be constructed (apiClientProvider throws) — so this
  // is only ever called on a branch that has one.
  RestTransport rest() => RestTransport(
    printers: ref.watch(printersRepositoryProvider),
    commands: ref.watch(printerCommandsRepositoryProvider),
    queue: ref.watch(queueRepositoryProvider),
    serverVersion: ref.watch(serverVersionServiceProvider),
  );
  // Demo runs entirely in this process (the API client swaps in the fake
  // backend), so there is nothing for the phone to answer — and asking it would
  // hand back the real fleet from the real server it is configured for. Demo is
  // itself a profile, which is how REST is there to take the relay's place.
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

/// The connected server's version, for the settings footer. `autoDispose`
/// because only that screen asks and the answer cannot change without the
/// server restarting — which drops the session anyway.
///
/// Never fails: the phone being out of reach, a phone too old to know the
/// action (it stays silent, and the watch's timeout is what ends the wait), a
/// server too old for the route — all of it is one answer to the reader, and a
/// footer is not the place to explain which of them it was.
final wearServerVersionProvider = FutureProvider.autoDispose<String?>((
  ref,
) async {
  try {
    // Watched, not read: the transport is rebuilt when the profile changes,
    // and an answer obtained through the previous one is about the previous
    // server.
    return await ref.watch(wearTransportProvider).getServerVersion();
  } on Object {
    return null;
  }
});

/// The watch's cold-start cache. Not `autoDispose`: it carries the floor
/// between writes ([WearFleetCache.minInterval]) across polls, and a fresh
/// instance per read would let every poll write.
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
  bool _disposed = false;

  /// Set while the watch app is in the background. Every relay poll wakes the
  /// phone over Bluetooth, and a screen nobody is looking at has nothing to
  /// update — the phone's own screens have stopped their polls on pause since
  /// they were written, and this one never did.
  ///
  /// Checked in [_scheduleNext] rather than only at [stopPolling], because a
  /// fetch already in flight when the app goes away would otherwise come back
  /// and re-arm the timer the pause had just cancelled.
  bool _paused = false;

  @override
  Future<WearFleet> build() async {
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
    });
    // Watched, not read: switching the server on the watch has to empty this,
    // not leave the old server's printers on screen until a poll happens to
    // replace them. The rebuild resets the state and re-reads the cache, which
    // is keyed by base URL and so answers nothing for the new server.
    final profile = ref.watch(serverProfileProvider);
    final cached = ref.read(wearFleetCacheProvider).load(profile);
    if (cached != null) {
      // Painted at once, refreshed underneath. A zero-length timer rather than
      // a direct call: [refresh] assigns `state`, which Riverpod refuses until
      // `build` has returned — and the timer is already the field `onDispose`
      // cancels, so a screen left before the first poll takes it with it.
      _timer = Timer(Duration.zero, refresh);
      return cached;
    }
    final fleet = await _fetch();
    _scheduleNext(fleet);
    return fleet;
  }

  Future<WearFleet> _fetch() async {
    final fleet = await ref.read(wearTransportProvider).getFleet();
    // Not awaited, and never fatal: writing the cache is not part of the poll
    // this caller is waiting on. Skipped once disposed, where `ref` throws.
    if (!_disposed) {
      unawaited(
        ref
            .read(wearFleetCacheProvider)
            .save(fleet, ref.read(serverProfileProvider)),
      );
    }
    return fleet;
  }

  /// Adaptive cadence: every relay poll wakes the phone over the bridge, so
  /// back off to 30 s when nothing is actively printing. Direct REST (or an
  /// active print) keeps the familiar 5 s.
  void _scheduleNext(WearFleet? fleet, {bool afterFailure = false}) {
    if (_disposed || _paused) return;
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
    // Two reasons to slow down, and the second one arrived with the cold-start
    // cache: a poll that failed while something is still on screen. Before the
    // cache a failed first fetch left the provider in its error state and
    // `_scheduleNext` was never reached at all, so an unreachable phone cost
    // nothing; keeping the frame means keeping the timer, and 5 s of that only
    // wakes the bridge for an answer that is not coming.
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
    // Before anything else: a tick armed earlier would otherwise mature while
    // this request is still out — and a relay call can be out for 15 s waiting
    // on a phone whose engine is booting — putting a second identical RPC on
    // the bridge. Every path back in here re-arms it on the way out.
    _timer?.cancel();
    _paused = false;
    // Whether what is on screen has ever been confirmed by this run. A frame
    // restored from the cache has not, and it is the difference between the two
    // things a failure can mean here.
    final unconfirmed = state.valueOrNull?.stale ?? false;
    final next = await AsyncValue.guard(_fetch);
    if (_disposed) return;

    if (next.hasError && state.hasValue && !unconfirmed) {
      // Confirmed data survives a dropped poll: one bad tick should not blank a
      // screen that was right a moment ago.
      _scheduleNext(state.valueOrNull, afterFailure: true);
      return;
    }

    // Everything else, the never-confirmed frame included: a failed connection
    // has to read as a failed connection. The cache buys a first frame, not a
    // licence to keep showing last run's printers while nothing can be reached
    // — so the error goes through and `WearHome` offers its retry.
    state = next;
    // Nothing on screen to keep fresh, and the retry re-creates the provider,
    // which is what starts the poll again. Left running it would wake the
    // bridge every few seconds behind an error the user is already looking at.
    if (next.hasError) return;
    _scheduleNext(next.valueOrNull);
  }
}

/// What a screen should draw out of [wearFleetProvider].
///
/// Riverpod's notifier keeps the previous value when the state is set to an
/// error, so `valueOrNull` still answers with the fleet that was on screen. For
/// a screen switching on the variant — `WearHome` and its `when` — that is
/// invisible; for a body reading `valueOrNull` it is the difference between
/// reporting a dead bridge and drawing last run's printers under it.
///
/// An error is always the answer here, never the old frame: [WearFleetNotifier]
/// only ever sets one where the data on screen has not been confirmed, and a
/// `build` that fails after a server switch must not leave the previous
/// server's printers up either.
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
