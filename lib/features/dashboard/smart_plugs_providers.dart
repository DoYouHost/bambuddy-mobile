import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/action_outcome.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/models/smart_plug.dart';
import '../../data/smart_plugs_repository.dart';
import '../../providers.dart';

/// Smart plug polling rate. Status only via REST (not WS), so we maintain
/// our own fixed interval — independent of printer WS health.
const smartPlugPollInterval = Duration(seconds: 5);

/// Snapshot of smart plugs for dashboard: configuration (with printer
/// assignment), live statuses (power/state) and optimistic/"in-flight" control state.
class SmartPlugsState {
  const SmartPlugsState({
    this.plugs = const [],
    this.statuses = const {},
    this.optimistic = const {},
    this.inFlight = const {},
    this.forbidden = false,
  });

  /// Configuration of all plugs (each carries `printerId`).
  final List<SmartPlug> plugs;

  /// Live status per `plugId` (null entry = unreachable/failed).
  final Map<int, SmartPlugStatus> statuses;

  /// Optimistic on/off override per `plugId` — instant effect of tap,
  /// before real status catches up (then cleaned).
  final Map<int, bool> optimistic;

  /// Plugs with command in flight (spinner + switch lock).
  final Set<int> inFlight;

  /// Sticky: command returned 403 (key lacks permissions) → block control.
  final bool forbidden;

  /// Plug to show on printer card: assigned, enabled, and marked visible.
  /// First match (usually one).
  SmartPlug? plugForPrinterCard(int printerId) {
    for (final p in plugs) {
      if (p.printerId == printerId && p.visibleOnCard) return p;
    }
    return null;
  }

  SmartPlugStatus? statusFor(int plugId) => statuses[plugId];

  bool isBusy(int plugId) => inFlight.contains(plugId);

  /// Effective on/off state: optimistic override takes priority over status,
  /// status over last known from config.
  bool? effectiveOn(SmartPlug plug) =>
      optimistic[plug.id] ?? statusFor(plug.id)?.isOn ?? plug.lastIsOn;

  /// Total active power [W] across all reachable plugs (entire farm).
  double get totalPowerW {
    var sum = 0.0;
    for (final s in statuses.values) {
      sum += s.powerW ?? 0;
    }
    return sum;
  }

  /// Whether anything to show in power context (at least 1 plug at all).
  bool get hasAnyPlug => plugs.isNotEmpty;

  SmartPlugsState copyWith({
    List<SmartPlug>? plugs,
    Map<int, SmartPlugStatus>? statuses,
    Map<int, bool>? optimistic,
    Set<int>? inFlight,
    bool? forbidden,
  }) =>
      SmartPlugsState(
        plugs: plugs ?? this.plugs,
        statuses: statuses ?? this.statuses,
        optimistic: optimistic ?? this.optimistic,
        inFlight: inFlight ?? this.inFlight,
        forbidden: forbidden ?? this.forbidden,
      );
}

final smartPlugsProvider =
    AutoDisposeNotifierProvider<SmartPlugsNotifier, SmartPlugsState>(
  SmartPlugsNotifier.new,
);

/// Fetches plug list and polls statuses in loop (5s), and sends on/off
/// commands with optimistic override and rollback (pattern like [ControlsNotifier]).
/// Auto-dispose: lives only when dashboard observes it.
class SmartPlugsNotifier extends AutoDisposeNotifier<SmartPlugsState> {
  Timer? _timer;
  int _generation = 0;

  /// How long to keep optimistic override after success before discarding
  /// (real status will have caught up — otherwise switch would flicker back).
  static const _optimisticHold = Duration(seconds: 8);
  final Map<int, Timer> _clearTimers = {};

  /// Two independent gates rather than one flag: coming back from the
  /// background while the user sits on another tab must not quietly restart the
  /// loop, and neither must switching tabs while the app is in the background.
  bool _foreground = true;
  bool _onScreen = true;

  bool get _shouldPoll => _foreground && _onScreen;

  @override
  SmartPlugsState build() {
    // Rebuild on profile change (different server/key → different plugs,
    // sticky `forbidden` lock clears).
    ref.watch(serverProfileProvider);
    ref.watch(smartPlugsRepositoryProvider);
    final generation = ++_generation;

    _arm(generation);
    ref.onDispose(() {
      _timer?.cancel();
      for (final t in _clearTimers.values) {
        t.cancel();
      }
      _clearTimers.clear();
    });
    if (_shouldPoll) Future.microtask(() => _poll(generation));
    return const SmartPlugsState();
  }

  void _arm(int generation) {
    _timer?.cancel();
    _timer = _shouldPoll
        ? Timer.periodic(smartPlugPollInterval, (_) => _poll(generation))
        : null;
  }

  /// Background → silence (FGS doesn't need plug data; don't hit server).
  void pausePolling() => _gate(() => _foreground = false);

  /// Return from background → resume loop and immediately pull state.
  void resumePolling() => _gate(() => _foreground = true);

  /// Whether the dashboard is the tab on screen. Plug controls and the farm
  /// total live there and nowhere else, so polling from another tab spends a
  /// request every five seconds on a number nobody can see — measured at a
  /// third of every log a user records.
  void setOnScreen(bool onScreen) => _gate(() => _onScreen = onScreen);

  void _gate(void Function() change) {
    final was = _shouldPoll;
    change();
    if (was == _shouldPoll) return;
    _arm(_generation);
    // Back on screen: catch up now rather than five seconds from now.
    if (_shouldPoll) _poll(_generation);
  }

  Future<void> refresh() => _poll(_generation);

  Future<void> _poll(int generation) async {
    final repo = ref.read(smartPlugsRepositoryProvider);
    final List<SmartPlug> plugs;
    try {
      plugs = await repo.fetchPlugs();
    } on AuthException {
      return; // dashboardProvider will redirect to /setup
    } on AppApiException {
      return; // transient network error — keep last known state
    }
    if (generation != _generation) return;

    // Poll statuses for enabled plugs (power into farm total), in parallel.
    // Unreachable return null → skip in map. [fetchStatus] rethrows
    // AuthException (per-endpoint 401/403, if list passed) — catch here
    // because dashboardProvider will redirect to /setup anyway; without this
    // would be unhandled async error in Timer tick.
    final enabled = plugs.where((p) => p.enabled ?? true).toList();
    final List<SmartPlugStatus?> results;
    try {
      results = await Future.wait(enabled.map((p) => repo.fetchStatus(p.id)));
    } on AppApiException {
      return;
    }
    if (generation != _generation) return;

    final statuses = <int, SmartPlugStatus>{};
    for (var i = 0; i < enabled.length; i++) {
      final s = results[i];
      if (s != null) statuses[enabled[i].id] = s;
    }
    state = state.copyWith(plugs: plugs, statuses: statuses);
  }

  /// Toggle plug (on/off/toggle) with optimistic override.
  /// Answers with the shared [ActionOutcome]; the widget decides whether to
  /// show it, never what it says.
  Future<ActionOutcome> control(int plugId, SmartPlugAction action) async {
    final plug = state.plugs.firstWhere(
      (p) => p.id == plugId,
      orElse: () => SmartPlug(id: plugId),
    );
    final desiredOn = switch (action) {
      SmartPlugAction.on => true,
      SmartPlugAction.off => false,
      SmartPlugAction.toggle => !(state.effectiveOn(plug) ?? false),
    };

    final before = state.optimistic[plugId];
    state = state.copyWith(
      optimistic: {...state.optimistic, plugId: desiredOn},
      inFlight: {...state.inFlight, plugId},
    );

    try {
      await ref.read(smartPlugsRepositoryProvider).control(plugId, action);
      _clearInFlight(plugId);
      _scheduleClearOptimistic(plugId);
      unawaited(_poll(_generation)); // pull real state + power
      return ActionOutcome.ok;
    } on AppApiException catch (e) {
      // Rollback override to pre-action state.
      final opt = {...state.optimistic};
      if (before == null) {
        opt.remove(plugId);
      } else {
        opt[plugId] = before;
      }
      state = state.copyWith(
        optimistic: opt,
        inFlight: {...state.inFlight}..remove(plugId),
      );
      final outcome = ActionOutcome.failed(e, action: 'plug.${action.name}');
      // Sticky, like the printer controls: one refusal stops offering the
      // switch rather than letting every tap fail the same way.
      if (outcome.isForbidden) state = state.copyWith(forbidden: true);
      return outcome;
    }
  }

  void _clearInFlight(int plugId) {
    state = state.copyWith(inFlight: {...state.inFlight}..remove(plugId));
  }

  void _scheduleClearOptimistic(int plugId) {
    _clearTimers[plugId]?.cancel();
    _clearTimers[plugId] = Timer(_optimisticHold, () {
      _clearTimers.remove(plugId);
      if (!state.optimistic.containsKey(plugId)) return;
      state = state.copyWith(
        optimistic: {...state.optimistic}..remove(plugId),
      );
    });
  }
}
