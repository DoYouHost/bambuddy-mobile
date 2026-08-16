import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/action_outcome.dart';
import '../../core/api/api_exceptions.dart';
import '../../data/printer_commands_repository.dart';
import '../../providers.dart';

/// Control actions — key for marking what is "in flight" (spinner +
/// button lock).
enum ControlAction {
  pause,
  resume,
  stop,
  light,
  speed,
  temp,
  airduct,
  fan,
  dry,
  extruder,
  move,
  hms,
}

/// Commands answer with the shared [ActionOutcome] — see its doc for why the
/// failure travels intact instead of as a code the widget re-words.

/// Optimistic overrides and "in-flight" state for one printer.
/// Overrides ([light]/[speedLevel]/[tempTargets]/[airductHeating]) overlay on
/// live status, so tapping gives instant effect; on success they disappear when
/// real status catches up (safety timer), on error — immediately (rollback).
class PendingControls {
  const PendingControls({
    this.light,
    this.speedLevel,
    this.tempTargets = const {},
    this.fanSpeeds = const {},
    this.airductHeating,
    this.inFlight = const {},
  });

  /// Optimistic chamber light state (null = no override → take from status).
  final bool? light;

  /// Optimistic speed level 1–4 (null = no override).
  final int? speedLevel;

  /// Optimistic temperature setpoints keyed by sensor raw key
  /// ('nozzle', 'nozzle_2', 'bed', 'chamber'). Absent key = no override.
  final Map<String, int> tempTargets;

  /// Optimistic fan speeds (%) keyed by fan id ('part', 'aux', 'chamber').
  /// Absent key = no override.
  final Map<String, int> fanSpeeds;

  /// Optimistic airduct mode (true = heating, false = cooling; null = none).
  final bool? airductHeating;

  /// Actions currently in flight to server.
  final Set<ControlAction> inFlight;

  bool isBusy(ControlAction a) => inFlight.contains(a);

  int? tempTarget(String key) => tempTargets[key];

  int? fanSpeed(String key) => fanSpeeds[key];

  bool get isEmpty =>
      light == null &&
      speedLevel == null &&
      tempTargets.isEmpty &&
      fanSpeeds.isEmpty &&
      airductHeating == null &&
      inFlight.isEmpty;

  PendingControls _copyWith({
    bool? light,
    int? speedLevel,
    Map<String, int>? tempTargets,
    Map<String, int>? fanSpeeds,
    bool? airductHeating,
    Set<ControlAction>? inFlight,
  }) =>
      PendingControls(
        light: light ?? this.light,
        speedLevel: speedLevel ?? this.speedLevel,
        tempTargets: tempTargets ?? this.tempTargets,
        fanSpeeds: fanSpeeds ?? this.fanSpeeds,
        airductHeating: airductHeating ?? this.airductHeating,
        inFlight: inFlight ?? this.inFlight,
      );

  // Nullable fields can't use `_copyWith` to clear (a null arg means "keep"),
  // so each has an explicit setter that rebuilds preserving every other field.
  PendingControls setLight(bool? v) => PendingControls(
        light: v,
        speedLevel: speedLevel,
        tempTargets: tempTargets,
        fanSpeeds: fanSpeeds,
        airductHeating: airductHeating,
        inFlight: inFlight,
      );

  PendingControls setSpeed(int? v) => PendingControls(
        light: light,
        speedLevel: v,
        tempTargets: tempTargets,
        fanSpeeds: fanSpeeds,
        airductHeating: airductHeating,
        inFlight: inFlight,
      );

  PendingControls setAirduct(bool? v) => PendingControls(
        light: light,
        speedLevel: speedLevel,
        tempTargets: tempTargets,
        fanSpeeds: fanSpeeds,
        airductHeating: v,
        inFlight: inFlight,
      );

  /// Set (or clear, when [value] is null) the optimistic target for one sensor.
  PendingControls withTempTarget(String key, int? value) =>
      _copyWith(tempTargets: _patch(tempTargets, key, value));

  /// Set (or clear, when [value] is null) the optimistic speed for one fan.
  PendingControls withFanSpeed(String key, int? value) =>
      _copyWith(fanSpeeds: _patch(fanSpeeds, key, value));

  PendingControls setInFlight(Set<ControlAction> v) => _copyWith(inFlight: v);

  static Map<String, int> _patch(Map<String, int> src, String key, int? value) {
    final m = {...src};
    if (value == null) {
      m.remove(key);
    } else {
      m[key] = value;
    }
    return m;
  }
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
/// SnackBars — returns [ActionOutcome], and widget decides what to show.
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

  Future<ActionOutcome> pause(int id) =>
      _run(id, ControlAction.pause, () => _repo.pause(id));

  Future<ActionOutcome> resume(int id) =>
      _run(id, ControlAction.resume, () => _repo.resume(id));

  Future<ActionOutcome> stop(int id) =>
      _run(id, ControlAction.stop, () => _repo.stop(id));

  /// Clear the printer's error dialog. One in-flight marker covers every HMS
  /// button on the card on purpose: the firmware handles one error command at a
  /// time, and a second tap while the first is in the air is how a resume and a
  /// stop race each other.
  Future<ActionOutcome> clearHmsErrors(int id) =>
      _run(id, ControlAction.hms, () => _repo.clearHmsErrors(id));

  Future<ActionOutcome> executeHmsAction(
    int id, {
    required String printError,
    required String action,
    String? jobId,
  }) =>
      _run(
        id,
        ControlAction.hms,
        () => _repo.executeHmsAction(id,
            printError: printError, action: action, jobId: jobId),
      );

  Future<ActionOutcome> setLight(int id, {required bool on}) => _run(
        id,
        ControlAction.light,
        () => _repo.setChamberLight(id, on: on),
        apply: (p) => p.setLight(on),
        rollback: (before, rolled) => rolled.setLight(before.light),
        clearKey: 'light',
      );

  Future<ActionOutcome> setSpeed(int id, int mode) => _run(
        id,
        ControlAction.speed,
        () => _repo.setPrintSpeed(id, mode),
        apply: (p) => p.setSpeed(mode),
        rollback: (before, rolled) => rolled.setSpeed(before.speedLevel),
        clearKey: 'speed',
      );

  /// Nozzle target. [key] is the sensor's raw key ('nozzle'/'nozzle_2') so the
  /// optimistic setpoint overlays the right gauge; [nozzle] is the hardware
  /// index (0=right/default, 1=left) sent to the server.
  Future<ActionOutcome> setNozzleTemp(
    int id,
    String key,
    int target, {
    int nozzle = 0,
  }) =>
      _run(
        id,
        ControlAction.temp,
        () => _repo.setNozzleTemperature(id, target, nozzle: nozzle),
        apply: (p) => p.withTempTarget(key, target),
        rollback: (before, rolled) =>
            rolled.withTempTarget(key, before.tempTarget(key)),
        clearKey: 'temp:$key',
      );

  Future<ActionOutcome> setBedTemp(int id, int target) => _run(
        id,
        ControlAction.temp,
        () => _repo.setBedTemperature(id, target),
        apply: (p) => p.withTempTarget('bed', target),
        rollback: (before, rolled) =>
            rolled.withTempTarget('bed', before.tempTarget('bed')),
        clearKey: 'temp:bed',
      );

  Future<ActionOutcome> setChamberTemp(int id, int target) => _run(
        id,
        ControlAction.temp,
        () => _repo.setChamberTemperature(id, target),
        apply: (p) => p.withTempTarget('chamber', target),
        rollback: (before, rolled) =>
            rolled.withTempTarget('chamber', before.tempTarget('chamber')),
        clearKey: 'temp:chamber',
      );

  Future<ActionOutcome> setAirduct(int id, {required bool heating}) => _run(
        id,
        ControlAction.airduct,
        () => _repo.setAirductMode(id, heating: heating),
        apply: (p) => p.setAirduct(heating),
        rollback: (before, rolled) => rolled.setAirduct(before.airductHeating),
        clearKey: 'airduct',
      );

  /// Fan speed (%). [fan] is 'part', 'aux', or 'chamber'.
  Future<ActionOutcome> setFanSpeed(int id, String fan, int speed) => _run(
        id,
        ControlAction.fan,
        () => _repo.setFanSpeed(id, fan, speed),
        apply: (p) => p.withFanSpeed(fan, speed),
        rollback: (before, rolled) =>
            rolled.withFanSpeed(fan, before.fanSpeed(fan)),
        clearKey: 'fan:$fan',
      );

  /// Start AMS drying. No optimistic overlay — the AMS `dry_time`/`dry_status`
  /// in status reflects it within a poll/WS frame.
  Future<ActionOutcome> startDrying(
    int id, {
    required int amsId,
    required int temp,
    required int duration,
    String filament = '',
  }) =>
      _run(
        id,
        ControlAction.dry,
        () => _repo.startDrying(id,
            amsId: amsId, temp: temp, duration: duration, filament: filament),
      );

  Future<ActionOutcome> stopDrying(int id, {required int amsId}) => _run(
        id,
        ControlAction.dry,
        () => _repo.stopDrying(id, amsId: amsId),
      );

  /// Select the active extruder (0=right, 1=left) on dual-nozzle printers.
  /// No optimistic override — the caller keeps the switch locked until the live
  /// status reports the new active extruder (the physical switch takes time).
  Future<ActionOutcome> setExtruder(int id, int extruder) => _run(
        id,
        ControlAction.extruder,
        () => _repo.selectExtruder(id, extruder),
      );

  /// Manual movement jogs + homing. No optimistic overlay — these are momentary
  /// actions with no persistent status field to preview. All share
  /// [ControlAction.move], so the movement sheet locks while one is in flight.

  /// Relative nozzle-bed gap jog (mm). Negative decreases the gap ("up").
  Future<ActionOutcome> bedJog(int id, double distance, {bool force = false}) =>
      _run(id, ControlAction.move,
          () => _repo.bedJog(id, distance, force: force));

  /// Relative toolhead X/Y jog (mm).
  Future<ActionOutcome> xyJog(int id, {double x = 0, double y = 0}) =>
      _run(id, ControlAction.move, () => _repo.xyJog(id, x: x, y: y));

  /// Relative extrusion (mm). Positive extrudes, negative retracts.
  Future<ActionOutcome> extruderJog(int id, double distance) =>
      _run(id, ControlAction.move, () => _repo.extruderJog(id, distance));

  /// Full auto-home sequence (`G28`).
  Future<ActionOutcome> homeAxes(int id) =>
      _run(id, ControlAction.move, () => _repo.homeAxes(id));

  /// Runs a command with optimistic apply + rollback-on-error. [apply] overlays
  /// the optimistic override; [rollback] restores the touched field from
  /// [before] (surgically, preserving any concurrent different action);
  /// [clearKey] schedules discarding the override once real status catches up.
  Future<ActionOutcome> _run(
    int id,
    ControlAction action,
    Future<void> Function() send, {
    PendingControls Function(PendingControls p)? apply,
    PendingControls Function(PendingControls before, PendingControls rolled)?
        rollback,
    String? clearKey,
  }) async {
    final before = state.pendingFor(id);

    // Optimistically: mark "in flight" and apply override (if action has one).
    var next = before.setInFlight({...before.inFlight, action});
    if (apply != null) next = apply(next);
    _setPending(id, next);

    try {
      await send();
      // Success: remove "in flight", keep override and schedule cleanup.
      _setPending(id, _withoutInFlight(state.pendingFor(id), action));
      if (clearKey != null) _scheduleClear(id, clearKey);
      return ActionOutcome.ok;
    } on AppApiException catch (e) {
      // Rollback: remove "in flight" and restore override to pre-action state.
      var rolled = _withoutInFlight(state.pendingFor(id), action);
      if (rollback != null) rolled = rollback(before, rolled);
      _setPending(id, rolled);

      final outcome = ActionOutcome.failed(e, action: 'printer.${action.name}');
      // Sticky: one refusal is enough to stop offering controls this session.
      if (outcome.isForbidden) state = state.copyWith(forbidden: true);
      return outcome;
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
      final PendingControls updated;
      if (field == 'light') {
        updated = cur.setLight(null);
      } else if (field == 'speed') {
        updated = cur.setSpeed(null);
      } else if (field == 'airduct') {
        updated = cur.setAirduct(null);
      } else if (field.startsWith('temp:')) {
        updated = cur.withTempTarget(field.substring('temp:'.length), null);
      } else if (field.startsWith('fan:')) {
        updated = cur.withFanSpeed(field.substring('fan:'.length), null);
      } else {
        updated = cur;
      }
      _setPending(id, updated);
    });
  }

  void _cancelTimers() {
    for (final t in _clearTimers.values) {
      t.cancel();
    }
    _clearTimers.clear();
  }
}
