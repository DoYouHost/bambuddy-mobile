import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/api/ws_client.dart';
import '../../data/printers_repository.dart';
import '../../providers.dart';
import 'ws_providers.dart';

/// Fast polling — fallback when WS not connected (status freshness).
const pollInterval = Duration(seconds: 5);

/// Slow polling when WS is `connected` — WS carries status freshness, REST
/// only pulls printer roster, which changes rarely.
const slowPollInterval = Duration(seconds: 60);

class DashboardState {
  const DashboardState({
    this.printers,
    this.error,
    this.authExpired = false,
  });

  /// Last successfully fetched data — stays visible if next poll fails
  /// (banner instead of blank screen).
  final List<PrinterWithStatus>? printers;

  /// Last poll error (null = last poll OK); translated in UI.
  final AppApiException? error;

  /// Session/key rejected and unrenewable — UI redirects to /setup.
  final bool authExpired;

  bool get loading => printers == null && error == null;
  bool get stale => printers != null && error != null;
}

final dashboardProvider =
    AutoDisposeNotifierProvider<DashboardNotifier, DashboardState>(
  DashboardNotifier.new,
);

/// REST polling every 5s. This pattern remains from M2 as backfill after
/// app resume and fallback when WebSocket fails.
class DashboardNotifier extends AutoDisposeNotifier<DashboardState> {
  Timer? _timer;
  int _generation = 0;

  @override
  DashboardState build() {
    // Rebuild on profile/client change (e.g. server change).
    ref.watch(printersRepositoryProvider);
    final generation = ++_generation;

    // Poll rate depends on WS: connected → slow (60s, roster only),
    // otherwise → fast (5s, fallback). Listen via ref.listen, NOT watch —
    // otherwise each WS flap would rebuild notifier and reset list to spinner.
    // State stays, only timer interval changes.
    ref.listen(
      wsConnectionStateProvider
          .select((s) => s.valueOrNull == WsConnectionState.connected),
      (_, connected) => _retune(connected: connected, generation: generation),
    );

    _arm(connected: _wsConnectedNow(), generation: generation);
    ref.onDispose(() => _timer?.cancel());
    Future.microtask(() => _poll(generation));
    return const DashboardState();
  }

  bool _wsConnectedNow() =>
      ref.read(wsConnectionStateProvider).valueOrNull ==
      WsConnectionState.connected;

  void _arm({required bool connected, required int generation}) {
    _timer?.cancel();
    final interval = connected ? slowPollInterval : pollInterval;
    _timer = Timer.periodic(interval, (_) => _poll(generation));
  }

  /// WS state change: on connection loss immediately pull REST
  /// (fallback kicks in), speed up; on regain, slow down.
  void _retune({required bool connected, required int generation}) {
    if (generation != _generation) return;
    _arm(connected: connected, generation: generation);
    if (!connected) _poll(generation);
  }

  Future<void> refresh() => _poll(_generation);

  /// Pause REST polling when app goes background with active monitoring —
  /// foreground service (separate isolate) takes freshness, UI isolate must
  /// be silent because FGS keeps process alive and timer would keep ticking,
  /// feeding `printerStatusesProvider` → duplicate notification.
  void pausePolling() {
    _timer?.cancel();
    _timer = null;
  }

  /// Resume polling on return from background (rearm + immediate backfill).
  void resumePolling() {
    _arm(connected: _wsConnectedNow(), generation: _generation);
    _poll(_generation);
  }

  Future<void> _poll(int generation) async {
    final repo = ref.read(printersRepositoryProvider);
    try {
      final data = await repo.fetchAll();
      if (generation != _generation) return; // result from previous life
      // Hook into shared statuses map: polling feeds same provider as WS,
      // so PrintMonitor catches changes also on REST fallback (not just live
      // socket). Done before `state` so UI and monitor see same thing in same tick.
      ref.read(printerStatusesProvider.notifier).ingestPoll(data);
      state = DashboardState(printers: data);
    } on AuthException {
      if (generation != _generation) return;
      _timer?.cancel();
      state = DashboardState(printers: state.printers, authExpired: true);
    } on AppApiException catch (e) {
      if (generation != _generation) return;
      state = DashboardState(printers: state.printers, error: e);
    }
  }
}
