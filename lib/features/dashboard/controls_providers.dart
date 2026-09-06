import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ams/slot_configuration.dart';
import '../../core/api/action_outcome.dart';
import '../../core/settings/server_profile.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/models/ams_filament_preset.dart';
import '../../data/ams_slot_config_repository.dart';
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
  ams,
}

/// The server permission a control route is gated on.
///
/// A 403 says "this key may not do *that*", not "this key may not do anything",
/// and the two are different in the UI: one refusal on the shared permission
/// takes every driving control off the card, while a refusal on a narrower one
/// may only take its own button. Naming the scope is what keeps a route with its
/// own gate from silently disabling the rest.
enum ControlPermission {
  /// `printers:control` — everything that drives the printer: the job, the
  /// lights, temperatures, fans, jogs, drying, HMS, AMS load/unload.
  control,

  /// `printers:ams_rfid` — re-reading a slot's RFID tag, and nothing else. A key
  /// allowed to control the printer can still be refused here.
  amsRfid,
}

/// Commands answer with the shared [ActionOutcome] — see its doc for why the
/// failure travels intact instead of as a code the widget re-words.

/// Result of configuring a slot: whether the printer took the filament, and
/// separately what became of the preset name.
///
/// Two answers because they are two permissions and two consequences. A slot
/// whose name was not remembered is configured correctly and *labelled wrongly*
/// — the sheet keeps showing whatever preset the server still has on file.
typedef SlotConfigOutcome = ({ActionOutcome outcome, SlotNameOutcome name});

/// What happened to the slot→preset mapping.
enum SlotNameOutcome {
  /// The server recorded which preset the slot was given.
  saved,

  /// The server refused to record it. Worth telling the user: the sheet will
  /// keep offering the *previous* preset next time it opens.
  refused,

  /// Not even attempted, because this connection cannot do it. Saving needs
  /// `printers:update`, which bambuddy denies to every API key no matter which
  /// scopes it was created with (`core/auth.py`, `_APIKEY_DENIED_PERMISSIONS`)
  /// — so on a key-authenticated session the route is a guaranteed 403 and a
  /// warning the user cannot act on. The sheet leans on the printer's own
  /// filament id instead.
  unavailable,
}

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
  }) => PendingControls(
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
  const ControlsState({this.pending = const {}, this.refused = const {}});

  final Map<int, PendingControls> pending;

  /// Permissions this key has already been refused (403). Sticky for the
  /// session — the answer will not change until the server profile does, and
  /// re-offering a button that just failed only teaches the user to distrust
  /// the card. Cleared on a profile change, since another key may differ.
  final Set<ControlPermission> refused;

  /// Whether a command needing [permission] is known to be refused.
  bool isRefused(ControlPermission permission) => refused.contains(permission);

  PendingControls pendingFor(int id) => pending[id] ?? const PendingControls();

  ControlsState copyWith({
    Map<int, PendingControls>? pending,
    Set<ControlPermission>? refused,
  }) => ControlsState(
    pending: pending ?? this.pending,
    refused: refused ?? this.refused,
  );
}

final controlsProvider = NotifierProvider<ControlsNotifier, ControlsState>(
  ControlsNotifier.new,
);

/// Whether commands needing [ControlPermission] are known to be refused.
///
/// Every control on the card asks this before offering itself, so the question
/// lives here rather than as a `select` each widget spells out: which gate a
/// button sits behind is a fact about the route, and re-deciding it in eight
/// widgets is how one of them ends up watching the wrong one.
final controlRefusedProvider = Provider.family<bool, ControlPermission>(
  (ref, permission) =>
      ref.watch(controlsProvider.select((s) => s.isRefused(permission))),
);

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
    // Server profile change → fresh state and discarded timers (another API key
    // may hold other permissions, so the [ControlsState.refused] set clears).
    ref.watch(serverProfileProvider);
    _cancelTimers();
    ref.onDispose(_cancelTimers);
    return const ControlsState();
  }

  PrinterCommandsRepository get _repo =>
      ref.read(printerCommandsRepositoryProvider);

  AmsSlotConfigRepository get _slotConfig =>
      ref.read(amsSlotConfigRepositoryProvider);

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
  }) => _run(
    id,
    ControlAction.hms,
    () => _repo.executeHmsAction(
      id,
      printError: printError,
      action: action,
      jobId: jobId,
    ),
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
  }) => _run(
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
  }) => _run(
    id,
    ControlAction.dry,
    () => _repo.startDrying(
      id,
      amsId: amsId,
      temp: temp,
      duration: duration,
      filament: filament,
    ),
  );

  Future<ActionOutcome> stopDrying(int id, {required int amsId}) =>
      _run(id, ControlAction.dry, () => _repo.stopDrying(id, amsId: amsId));

  /// Load filament from one slot. [trayId] is the global tray number — build it
  /// with [amsLoadTrayId] rather than by hand. [extruderId] names the hotend to
  /// feed and belongs only to a printer with a Filament Track Switch fitted.
  ///
  /// The three AMS actions share [ControlAction.ams] so that a slot sheet locks
  /// as a whole: load, unload and an RFID re-read all move the same filament
  /// path, and two of them in the air at once is a jam, not a race the firmware
  /// sorts out.
  Future<ActionOutcome> amsLoad(int id, int trayId, {int? extruderId}) => _run(
    id,
    ControlAction.ams,
    () => _repo.amsLoad(id, trayId, extruderId: extruderId),
  );

  /// Unload filament. [trayId] names the slot, which on a dual-nozzle printer
  /// is the only way to say which of the two hotends to empty.
  Future<ActionOutcome> amsUnload(int id, {int? trayId}) =>
      _run(id, ControlAction.ams, () => _repo.amsUnload(id, trayId: trayId));

  /// Re-read one slot's RFID tag. Ids are local to the unit.
  ///
  /// The only route on the card behind [ControlPermission.amsRfid]: a key that
  /// may drive the printer can still be refused this one, and that refusal must
  /// cost nothing but this button.
  Future<ActionOutcome> refreshAmsSlot(
    int id, {
    required int amsId,
    required int slotId,
  }) => _run(
    id,
    ControlAction.ams,
    () => _repo.refreshAmsSlot(id, amsId: amsId, slotId: slotId),
    permission: ControlPermission.amsRfid,
  );

  /// Write a filament configuration into one slot, and remember which preset it
  /// was — the printer keeps only a filament id, so without the mapping the slot
  /// can be shown but not named.
  ///
  /// Ids are **local** to the unit here, unlike [amsLoad]: the external spool is
  /// unit 255 with slot 0 (Ext-L) or 1 (Ext-R), which is the same pair the
  /// inventory assignment already uses.
  ///
  /// The mapping is saved separately and cannot fail the write: it needs
  /// `printers:update`, a permission of its own, and by the time it runs the
  /// filament is already set on the printer. Failing the whole action over the
  /// label would report a change that did happen as one that did not.
  ///
  /// See [SlotNameOutcome] for the three ways that second call can end.
  Future<SlotConfigOutcome> configureSlot(
    int id, {
    required int amsId,
    required int trayId,
    required SlotConfiguration configuration,
    required AmsFilamentPreset preset,
  }) async {
    // An API key is refused `printers:update` by the server whatever scopes it
    // holds, so the call is skipped rather than sent to be denied.
    final canName =
        ref.read(serverProfileProvider)?.authMode != AuthMode.apiKey;
    var name = canName ? SlotNameOutcome.saved : SlotNameOutcome.unavailable;

    final outcome = await _run(id, ControlAction.ams, () async {
      await _slotConfig.configureSlot(
        id,
        amsId: amsId,
        trayId: trayId,
        configuration: configuration,
      );
      if (!canName) return;
      try {
        await _slotConfig.saveSlotPreset(
          id,
          amsId: amsId,
          trayId: trayId,
          preset: preset,
          presetName: configuration.traySubBrands,
        );
      } on AppApiException {
        name = SlotNameOutcome.refused;
      }
    });
    return (outcome: outcome, name: name);
  }

  /// Clear a slot's filament configuration, and the saved mapping with it.
  Future<ActionOutcome> resetSlot(
    int id, {
    required int amsId,
    required int trayId,
  }) => _run(
    id,
    ControlAction.ams,
    () => _slotConfig.resetSlot(id, amsId: amsId, trayId: trayId),
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
      _run(
        id,
        ControlAction.move,
        () => _repo.bedJog(id, distance, force: force),
      );

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
  ///
  /// [permission] is the server gate this route sits behind, and decides what a
  /// 403 costs: only the buttons that need the same permission go away.
  Future<ActionOutcome> _run(
    int id,
    ControlAction action,
    Future<void> Function() send, {
    PendingControls Function(PendingControls p)? apply,
    PendingControls Function(PendingControls before, PendingControls rolled)?
    rollback,
    String? clearKey,
    ControlPermission permission = ControlPermission.control,
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
      // One refusal answers for every route behind the same gate, and for none
      // of the routes behind another.
      if (outcome.isForbidden) {
        state = state.copyWith(refused: {...state.refused, permission});
      }
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
