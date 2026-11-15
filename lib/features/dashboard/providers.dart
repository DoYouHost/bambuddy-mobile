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

/// Whether anyone can see the dashboard: the app in the foreground and the
/// dashboard the tab on screen. What the dashboard's own polls (smart plugs, AI
/// detection) run on.
///
/// Two independent gates rather than one flag: coming back from the background
/// while the user sits on another tab must not quietly restart a loop, and
/// neither must switching tabs while the app is in the background. Kept in a
/// provider of its own because a poll that comes and goes with what is on the
/// cards (AI detection lives only while something prints) has to be born
/// silent when nobody is watching.
///
/// [DashboardNotifier] does not read it: the roster poll feeds the statuses
/// every tab and the print monitor use, so it runs off screen too and stops
/// only for the background.
final dashboardWatchedProvider = NotifierProvider<DashboardWatched, bool>(
  DashboardWatched.new,
);

class DashboardWatched extends Notifier<bool> {
  bool _foreground = true;
  bool _onScreen = true;

  @override
  bool build() => _foreground && _onScreen;

  /// The background needs none of it: the foreground service keeps the prints
  /// fresh there, and plug or detection data has no reader.
  void setForeground(bool foreground) {
    _foreground = foreground;
    state = _foreground && _onScreen;
  }

  /// Whether the dashboard is the tab on screen. Its polls feed controls that
  /// live there and nowhere else, so polling from another tab spends requests
  /// on numbers nobody can see — the plugs' loop alone was measured at a third
  /// of every log a user records.
  void setOnScreen(bool onScreen) {
    _onScreen = onScreen;
    state = _foreground && _onScreen;
  }
}

class DashboardState {
  const DashboardState({this.printers, this.error, this.authExpired = false});

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
    NotifierProvider.autoDispose<DashboardNotifier, DashboardState>(
      DashboardNotifier.new,
    );

/// REST polling every 5s. This pattern remains from M2 as backfill after
/// app resume and fallback when WebSocket fails.
class DashboardNotifier extends Notifier<DashboardState> {
  Timer? _timer;
  int _generation = 0;

  /// Whether the app is in the background. A flag rather than "no timer",
  /// because going to the background also closes the socket, and a socket that
  /// closes looks to [_retune] exactly like a network drop: it re-arms the very
  /// polling that had just been stopped, and the foreground service — which now
  /// owns freshness — ends up with the UI isolate polling alongside it.
  bool _paused = false;

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
      wsConnectionStateProvider.select(
        (s) => s.value == WsConnectionState.connected,
      ),
      (_, connected) => _retune(connected: connected, generation: generation),
    );

    _arm(connected: _wsConnectedNow(), generation: generation);
    ref.onDispose(() => _timer?.cancel());
    Future.microtask(() => _poll(generation));
    return const DashboardState();
  }

  bool _wsConnectedNow() =>
      ref.read(wsConnectionStateProvider).value == WsConnectionState.connected;

  void _arm({required bool connected, required int generation}) {
    _timer?.cancel();
    if (_paused) {
      _timer = null;
      return;
    }
    final interval = connected ? slowPollInterval : pollInterval;
    _timer = Timer.periodic(interval, (_) => _poll(generation));
  }

  /// WS state change: on connection loss immediately pull REST
  /// (fallback kicks in), speed up; on regain, slow down.
  ///
  /// In the background this only records the new interval for later: [_arm]
  /// leaves the timer off and the fallback poll is skipped, because down there
  /// the socket is closed on purpose and the background service is the one
  /// keeping state fresh.
  void _retune({required bool connected, required int generation}) {
    if (generation != _generation) return;
    _arm(connected: connected, generation: generation);
    if (!connected && !_paused) _poll(generation);
  }

  /// Pull-to-refresh: ask every printer to republish before re-reading the
  /// roster. The REST poll alone only re-reads what the server already holds,
  /// so a field the firmware never echoed (a slot assignment it swallowed, a
  /// state it stopped pushing) stays wrong however often the user pulls.
  ///
  /// Fire-and-forget on purpose: the republish arrives over the socket, not in
  /// this response, and a printer that is offline answers 400 — neither is a
  /// reason to fail the refresh the user asked for.
  Future<void> refresh() {
    nudgeRepublish();
    return _poll(_generation);
  }

  /// Ask the printers to republish their state — one when [printerId] is given,
  /// otherwise every printer on the roster.
  void nudgeRepublish([int? printerId]) {
    ref
        .read(printerCommandsRepositoryProvider)
        .nudgeRepublish(
          printerId != null
              ? [printerId]
              : [for (final p in state.printers ?? const []) p.printer.id],
        );
  }

  /// Pause REST polling when app goes background with active monitoring —
  /// foreground service (separate isolate) takes freshness, UI isolate must
  /// be silent because FGS keeps process alive and timer would keep ticking,
  /// feeding `printerStatusesProvider` → duplicate notification.
  void pausePolling() {
    _paused = true;
    _timer?.cancel();
    _timer = null;
  }

  /// Resume polling on return from background (rearm + immediate backfill).
  void resumePolling() {
    _paused = false;
    _arm(connected: _wsConnectedNow(), generation: _generation);
    _poll(_generation);
  }

  Future<void> _poll(int generation) async {
    final repo = ref.read(printersRepositoryProvider);
    try {
      final data = await repo.fetchAll();
      if (!ref.mounted) return;
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
      ref.read(printerStatusesProvider.notifier).lostContact();
      state = DashboardState(printers: state.printers, error: e);
    }
  }
}
