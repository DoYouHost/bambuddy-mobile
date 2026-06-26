import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../data/printer_commands_repository.dart';
import '../../providers.dart';

/// Control actions — key for marking what is "in flight" (spinner +
/// button lock).
enum ControlAction { pause, resume, stop, light, speed }

/// Command result returned to the widget that initiated the action — it
/// displays the SnackBar (notifier has no [BuildContext]).
enum ControlResult { ok, forbidden, error }

/// Optimistic overrides and "in-flight" state for one printer.
/// Overrides ([light]/[speedLevel]) overlay on live status, so tapping gives
/// instant effect; on success they disappear when real status catches up
/// (safety timer), on error — immediately (rollback).
class PendingControls {
  const PendingControls({
    this.light,
    this.speedLevel,
    this.inFlight = const {},
  });

  /// Optimistic chamber light state (null = no override → take from status).
  final bool? light;

  /// Optimistic speed level 1–4 (null = no override).
  final int? speedLevel;

  /// Actions currently in flight to server.
  final Set<ControlAction> inFlight;

  bool isBusy(ControlAction a) => inFlight.contains(a);

  bool get isEmpty =>
      light == null && speedLevel == null && inFlight.isEmpty;

  PendingControls setLight(bool? v) =>
      PendingControls(light: v, speedLevel: speedLevel, inFlight: inFlight);

  PendingControls setSpeed(int? v) =>
      PendingControls(light: light, speedLevel: v, inFlight: inFlight);

  PendingControls setInFlight(Set<ControlAction> v) =>
      PendingControls(light: light, speedLevel: speedLevel, inFlight: v);
}

class ControlsState {
  const ControlsState({this.pending = const {}, this.forbidden = false});

  final Map<int, PendingControls> pending;

  /// Sticky: any command returned 403 (key lacks `can_control_printer`) →
  /// we block control until profile change.
  final bool forbidden;

  PendingControls pendingFor(int id) =>
      pending[id] ?? const PendingControls();

  ControlsState copyWith({Map<int, PendingControls>? pending, bool? forbidden}) =>
      ControlsState(
        pending: pending ?? this.pending,
        forbidden: forbidden ?? this.forbidden,
      );
}

final controlsProvider =
    NotifierProvider<ControlsNotifier, ControlsState>(ControlsNotifier.new);

/// Sends control commands and maintains optimistic UI state. No navigation or
/// SnackBars — returns [ControlResult], and widget decides what to show.
class ControlsNotifier extends Notifier<ControlsState> {
  /// How long to keep optimistic override after success before discarding
  /// (real status from WS/polling should have caught up by then —
  /// without this, the chip would flicker to old value for ~a second).
  static const optimisticHold = Duration(seconds: 8);

  final Map<String, Timer> _clearTimers = {};

  @override
  ControlsState build() {
    // Server profile change → fresh state and discarded timers (different API key
    // may have different permissions, so sticky `forbidden` lock clears).
    ref.watch(serverProfileProvider);
    _cancelTimers();
    ref.onDispose(_cancelTimers);
    return const ControlsState();
  }

  PrinterCommandsRepository get _repo =>
      ref.read(printerCommandsRepositoryProvider);

  Future<ControlResult> pause(int id) =>
      _run(id, ControlAction.pause, () => _repo.pause(id));

  Future<ControlResult> resume(int id) =>
      _run(id, ControlAction.resume, () => _repo.resume(id));

  Future<ControlResult> stop(int id) =>
      _run(id, ControlAction.stop, () => _repo.stop(id));

  Future<ControlResult> setLight(int id, {required bool on}) => _run(
        id,
        ControlAction.light,
        () => _repo.setChamberLight(id, on: on),
        optimistic: 'light',
        applyLight: on,
      );

  Future<ControlResult> setSpeed(int id, int mode) => _run(
        id,
        ControlAction.speed,
        () => _repo.setPrintSpeed(id, mode),
        optimistic: 'speed',
        applySpeed: mode,
      );

  Future<ControlResult> _run(
    int id,
    ControlAction action,
    Future<void> Function() send, {
    String? optimistic,
    bool? applyLight,
    int? applySpeed,
  }) async {
    final before = state.pendingFor(id);

    // Optimistically: mark "in flight" and apply override (if action has one).
    var next = before.setInFlight({...before.inFlight, action});
    if (optimistic == 'light') next = next.setLight(applyLight);
    if (optimistic == 'speed') next = next.setSpeed(applySpeed);
    _setPending(id, next);

    try {
      await send();
      // Success: remove "in flight", keep override and schedule cleanup.
      _setPending(id, _withoutInFlight(state.pendingFor(id), action));
      if (optimistic != null) _scheduleClear(id, optimistic);
      return ControlResult.ok;
    } on AppApiException catch (e) {
      // Rollback: remove "in flight" and restore override to pre-action state
      // (surgically — to not cancel a concurrent different action).
      var rolled = _withoutInFlight(state.pendingFor(id), action);
      if (optimistic == 'light') rolled = rolled.setLight(before.light);
      if (optimistic == 'speed') rolled = rolled.setSpeed(before.speedLevel);
      _setPending(id, rolled);

      if (e is AuthException && e.code == AppErrorCode.forbidden) {
        state = state.copyWith(forbidden: true);
        return ControlResult.forbidden;
      }
      return ControlResult.error;
    }
  }

  PendingControls _withoutInFlight(PendingControls p, ControlAction a) =>
      p.setInFlight({...p.inFlight}..remove(a));

  void _setPending(int id, PendingControls p) {
    final m = {...state.pending};
    if (p.isEmpty) {
      m.remove(id);
    } else {
      m[id] = p;
    }
    state = state.copyWith(pending: m);
  }

  void _scheduleClear(int id, String field) {
    final key = '$id:$field';
    _clearTimers[key]?.cancel();
    _clearTimers[key] = Timer(optimisticHold, () {
      _clearTimers.remove(key);
      final cur = state.pending[id];
      if (cur == null) return;
      _setPending(id, field == 'light' ? cur.setLight(null) : cur.setSpeed(null));
    });
  }

  void _cancelTimers() {
    for (final t in _clearTimers.values) {
      t.cancel();
    }
    _clearTimers.clear();
  }
}
