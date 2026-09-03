import 'package:collection/collection.dart';
import 'package:json_annotation/json_annotation.dart';

import '../ams/fts_routing.dart';
import '../ams/slot_addressing.dart';
import 'json_utils.dart';

part 'printer_status.g.dart';

const _listAmsUnitEquality = ListEquality<AmsUnit>();
const _listAmsTrayEquality = ListEquality<AmsTray>();
const _listHmsErrorEquality = ListEquality<HmsError>();
const _listNozzleEquality = ListEquality<NozzleInfo>();
const _stringListEquality = ListEquality<String>();
const _mapStringDoubleEquality = MapEquality<String, double>();
const _mapIntIntEquality = MapEquality<int, int>();
const _mapIntExtruderSlotEquality = MapEquality<int, ExtruderSlot>();
const _mapIntStringEquality = MapEquality<int, String>();

/// Printer status from `GET /printers/{id}/status` (and eventually from WS
/// `printer_status` frames in M2). Central DTO — follows defensive parsing pattern:
/// nullable fields, numbers via tolerant converters accepting int/double/string,
/// unknown keys ignored, never force-unwrap server data.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class PrinterStatus {
  const PrinterStatus({
    required this.id,
    this.name,
    this.connected,
    this.state,
    this.currentPrint,
    this.gcodeFile,
    this.progress,
    this.remainingTime,
    this.layerNum,
    this.totalLayers,
    this.temperatures,
    this.coverUrl,
    this.stgCur,
    this.stgCurName,
    this.coolingFanSpeed,
    this.bigFan1Speed,
    this.bigFan2Speed,
    this.leftAuxFanSpeed,
    this.exhaustFanPresent,
    this.heatbreakFanSpeed,
    this.speedLevel,
    this.chamberLight,
    this.airductMode,
    this.ams,
    this.vtTray,
    this.trayNow,
    this.activeExtruder,
    this.amsExtruderMap,
    this.amsSwitchInlet,
    this.model,
    this.wifiSignal,
    this.doorOpen,
    this.awaitingPlateClear,
    this.hmsErrors,
    this.supportsDrying,
    this.nozzles,
    this.filaSwitch,
    this.extruderSlots,
  });

  factory PrinterStatus.fromJson(Map<String, dynamic> json) =>
      _$PrinterStatusFromJson(json);

  final int id;
  final String? name;
  final bool? connected;

  /// Raw state from server (e.g. RUNNING/IDLE/FAILED) — not enum-backed to allow
  /// new values without breaking.
  final String? state;
  final String? currentPrint;
  final String? gcodeFile;

  /// Progress in percent 0–100.
  @JsonKey(fromJson: toDoubleOrNull)
  final double? progress;

  /// Remaining time in minutes.
  @JsonKey(fromJson: toIntOrNull)
  final int? remainingTime;

  @JsonKey(fromJson: toIntOrNull)
  final int? layerNum;

  @JsonKey(fromJson: toIntOrNull)
  final int? totalLayers;

  /// Undocumented keys from server (usually nozzle/bed/chamber) — render
  /// whatever arrives, don't assume set.
  @JsonKey(fromJson: _toTemperaturesOrNull)
  final Map<String, double>? temperatures;

  /// Path to current print cover (e.g. `/api/v1/printers/1/cover`). Requires
  /// camera stream token as `?token=` parameter on fetch.
  final String? coverUrl;

  /// Which stage the printer reports it is in: `0` is plain printing, `1`–`254`
  /// a named stage, `-1` (X1) and `255` (A1/P1) none. Read it through
  /// [inNamedStage] — that is the question every caller has.
  ///
  /// It is also the only stage field the WebSocket carries:
  /// `mc_print_sub_stage`, which bambuddy's own first-layer guard consults, is
  /// REST-only (`printer_state_to_dict`).
  @JsonKey(fromJson: toIntOrNull)
  final int? stgCur;

  /// Current stage name from server (e.g. "Auto bed leveling", "Heating");
  /// null/empty outside prep phase. Comes in English.
  final String? stgCurName;

  /// Part cooling fan, 0–100%.
  @JsonKey(fromJson: toIntOrNull)
  final int? coolingFanSpeed;

  /// Auxiliary fan (big fan 1), 0–100%.
  @JsonKey(fromJson: toIntOrNull)
  final int? bigFan1Speed;

  /// Chamber / exhaust fan (big fan 2), 0–100%.
  @JsonKey(fromJson: toIntOrNull)
  final int? bigFan2Speed;

  /// Left auxiliary part cooling fan, 0–100% — a P2S accessory kit, factory
  /// fitted on the X2D. Reported only from the printer's airduct data (part
  /// id 10), never mirrored into a `big_fanX_speed` field, so `null` covers
  /// both "server too old to send it" and "printer doesn't have this fan".
  /// Either way there is nothing to show, so no server-version gate is needed.
  /// Controlled with `fan=aux2` (server ≥ 1.2.5.2; older ones answer 400, which
  /// we never reach because the tile only renders when this is non-null).
  @JsonKey(fromJson: toIntOrNull)
  final int? leftAuxFanSpeed;

  /// Whether the chamber exhaust fan is physically fitted (airduct part id 3).
  /// Deliberately nullable to keep three states apart: `null` = server older
  /// than 1.2.5.2, which never reported presence; `false` = the printer sent a
  /// full airduct inventory without the fan; `true` = fitted.
  ///
  /// Only meaningful on P2S/X2D, where this fan is an add-on kit. Everywhere
  /// else the server sends `false` — X1C/P1S are on the old protocol and report
  /// no airduct at all — so it must never be used as a general gate, or every
  /// one of those printers would lose its chamber fan tile. See
  /// `usesExhaustFanLabel`.
  final bool? exhaustFanPresent;

  /// Heatbreak fan, 0–100% (usually 0 — firmware-controlled).
  @JsonKey(fromJson: toIntOrNull)
  final int? heatbreakFanSpeed;

  /// Bambu speed level: 1 Silent, 2 Standard, 3 Sport, 4 Ludicrous.
  @JsonKey(fromJson: toIntOrNull)
  final int? speedLevel;

  /// Whether chamber light is on.
  final bool? chamberLight;

  /// Chamber airduct mode: 0 = cooling, 1 = heating. Other values → null
  /// in [airductIsHeating] (don't assume modes beyond known).
  @JsonKey(fromJson: toIntOrNull)
  final int? airductMode;

  /// AMS units (one per module). Defensive parsing — non-map elements skipped,
  /// never breaks status.
  @JsonKey(fromJson: _toAmsListOrNull)
  final List<AmsUnit>? ams;

  /// External spool — same structure as AMS slot. Server usually provides 1–2
  /// entries (id 254/255).
  @JsonKey(fromJson: _toTrayListOrNull)
  final List<AmsTray>? vtTray;

  /// The firmware's global tray number for the loaded slot — see
  /// [globalTrayId] for the encodings.
  @JsonKey(fromJson: toIntOrNull)
  final int? trayNow;

  /// Active extruder (nozzle) on dual-head printers (X2D/H2D); 0/1.
  /// null/0 on regular single-head.
  @JsonKey(fromJson: toIntOrNull)
  final int? activeExtruder;

  /// Map "AMS unit ID → feeding extruder". Keys come as strings (e.g. `{"0":1}`)
  /// — normalize to int.
  @JsonKey(fromJson: _toExtruderMapOrNull)
  final Map<int, int>? amsExtruderMap;

  /// Map "AMS unit ID → Filament Track Switch inlet" (`{0: "A"}`), sent only by
  /// servers that know the accessory and only while one is fitted. An FTS-bound
  /// AMS reaches BOTH nozzles, so it is missing from [amsExtruderMap] and must
  /// not be labelled left or right — the inlet says where its slots sit between
  /// prints, which is what [extruderForSlot] answers with.
  @JsonKey(fromJson: _toInletMapOrNull)
  final Map<int, String>? amsSwitchInlet;

  /// Printer model from server (e.g. "X2D", "P1S").
  final String? model;

  /// Wi-Fi signal strength in dBm (negative; closer to 0 = better). null = none/LAN.
  @JsonKey(fromJson: toIntOrNull)
  final int? wifiSignal;

  /// Whether door/cover is open (if printer reports it).
  final bool? doorOpen;

  /// Whether machine awaits print removal from plate before next task
  /// (key `awaiting_plate_clear`). Source of "plate not empty" event.
  final bool? awaitingPlateClear;

  /// Active printer HMS errors (`hms_errors`). List can be empty = no errors;
  /// element shape varies across server versions, so parse defensively
  /// (see [HmsError]).
  @JsonKey(fromJson: _toHmsListOrNull)
  final List<HmsError>? hmsErrors;

  /// Whether this printer model/firmware supports AMS drying commands
  /// (`supports_drying`, printer-level). Gates the AMS Dry action.
  final bool? supportsDrying;

  /// Fitted nozzles, index 0 first (left/primary). Read for the diameter, which
  /// the AMS slot configuration has to send and which nothing else reports.
  @JsonKey(fromJson: _toNozzleListOrNull)
  final List<NozzleInfo>? nozzles;

  /// The Filament Track Switch accessory, or null on a printer without one —
  /// and on every server that does not report the field yet, which is the same
  /// answer: no switch, load the old way.
  @JsonKey(fromJson: _toFilaSwitchOrNull)
  final FilaSwitch? filaSwitch;

  /// Which AMS slot each hotend is fed from, keyed by extruder id (0 = right /
  /// main, 1 = left / deputy). Null on servers and printers that do not report
  /// it; [trayNow] is printer-wide and cannot answer the same question, because
  /// with two hotends loaded it names only one of them.
  @JsonKey(fromJson: _toExtruderSlotMapOrNull)
  final Map<int, ExtruderSlot>? extruderSlots;

  /// Which extruder one AMS slot feeds, or null when the printer has not said.
  /// See [slotExtruder] for why this refuses to guess. [trayId] only changes the
  /// answer for the external holder (unit 255), where it names the side.
  int? extruderForSlot(int amsId, int trayId) => slotExtruder(
        amsId: amsId,
        trayId: trayId,
        amsExtruderMap: amsExtruderMap,
        amsSwitchInlet: amsSwitchInlet,
      );

  /// Diameter of the nozzle one AMS slot feeds, as the string the server and the
  /// printer both use (`0.4`). Null when the printer has not reported its
  /// nozzles, and null when it wears two different ones and nothing says which
  /// side this slot is on — a caller that must send something falls back to
  /// `0.4`, but that guess belongs at the call site, not here.
  ///
  /// [nozzles] always carries two entries; on a single-nozzle machine the second
  /// one is an empty stub, which is why the count proves nothing and the
  /// distinct *reported* diameters are what decide whether the side matters.
  String? nozzleDiameterFor(int amsId, int trayId) {
    final fitted = nozzles ?? const <NozzleInfo>[];
    final reported = [for (final n in fitted) n.nozzleDiameter?.trim() ?? ''];
    final distinct = reported.where((d) => d.isNotEmpty).toSet();
    if (distinct.isEmpty) return null;
    // One size across the machine — the side cannot change the answer.
    if (distinct.length == 1) return distinct.first;
    final extruder = extruderForSlot(amsId, trayId);
    if (extruder == null || extruder < 0 || extruder >= reported.length) {
      return null;
    }
    final own = reported[extruder];
    return own.isEmpty ? null : own;
  }

  /// Value equality — `ingestPoll` uses this to skip publishing a merged
  /// status that's identical in content to the one already in state (REST
  /// polling otherwise builds a fresh `PrinterStatus` every 5s via
  /// `mergedWith`, so reference equality alone never matches even when
  /// nothing on the server changed).
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrinterStatus &&
          other.id == id &&
          other.name == name &&
          other.connected == connected &&
          other.state == state &&
          other.currentPrint == currentPrint &&
          other.gcodeFile == gcodeFile &&
          other.progress == progress &&
          other.remainingTime == remainingTime &&
          other.layerNum == layerNum &&
          other.totalLayers == totalLayers &&
          _mapStringDoubleEquality.equals(other.temperatures, temperatures) &&
          other.coverUrl == coverUrl &&
          other.stgCur == stgCur &&
          other.stgCurName == stgCurName &&
          other.coolingFanSpeed == coolingFanSpeed &&
          other.bigFan1Speed == bigFan1Speed &&
          other.bigFan2Speed == bigFan2Speed &&
          other.leftAuxFanSpeed == leftAuxFanSpeed &&
          other.exhaustFanPresent == exhaustFanPresent &&
          other.heatbreakFanSpeed == heatbreakFanSpeed &&
          other.speedLevel == speedLevel &&
          other.chamberLight == chamberLight &&
          other.airductMode == airductMode &&
          _listAmsUnitEquality.equals(other.ams, ams) &&
          _listAmsTrayEquality.equals(other.vtTray, vtTray) &&
          other.trayNow == trayNow &&
          other.activeExtruder == activeExtruder &&
          _mapIntIntEquality.equals(other.amsExtruderMap, amsExtruderMap) &&
          _mapIntStringEquality.equals(other.amsSwitchInlet, amsSwitchInlet) &&
          other.model == model &&
          other.wifiSignal == wifiSignal &&
          other.doorOpen == doorOpen &&
          other.awaitingPlateClear == awaitingPlateClear &&
          other.supportsDrying == supportsDrying &&
          _listNozzleEquality.equals(other.nozzles, nozzles) &&
          other.filaSwitch == filaSwitch &&
          _mapIntExtruderSlotEquality.equals(
              other.extruderSlots, extruderSlots) &&
          _listHmsErrorEquality.equals(other.hmsErrors, hmsErrors);

  @override
  int get hashCode => Object.hashAll([
        id,
        name,
        connected,
        state,
        currentPrint,
        gcodeFile,
        progress,
        remainingTime,
        layerNum,
        totalLayers,
        temperatures == null ? null : _mapStringDoubleEquality.hash(temperatures),
        coverUrl,
        stgCur,
        stgCurName,
        coolingFanSpeed,
        bigFan1Speed,
        bigFan2Speed,
        leftAuxFanSpeed,
        exhaustFanPresent,
        heatbreakFanSpeed,
        speedLevel,
        chamberLight,
        airductMode,
        ams == null ? null : _listAmsUnitEquality.hash(ams),
        vtTray == null ? null : _listAmsTrayEquality.hash(vtTray),
        trayNow,
        activeExtruder,
        amsExtruderMap == null ? null : _mapIntIntEquality.hash(amsExtruderMap),
        amsSwitchInlet == null
            ? null
            : _mapIntStringEquality.hash(amsSwitchInlet),
        model,
        wifiSignal,
        doorOpen,
        awaitingPlateClear,
        hmsErrors == null ? null : _listHmsErrorEquality.hash(hmsErrors),
        supportsDrying,
        nozzles == null ? null : _listNozzleEquality.hash(nozzles),
        filaSwitch,
        extruderSlots == null
            ? null
            : _mapIntExtruderSlotEquality.hash(extruderSlots),
      ]);

  /// Merge fresh frame into previous state of same printer. Core rule:
  /// **never zero known value** — any field the new frame doesn't carry (`null`)
  /// inherits last known. Why: neither REST nor WS guarantees complete snapshot —
  /// they carry disjoint subsets (WS lacks `airduct_mode`; REST lacks
  /// `model`/`vt_tray`/`cover_url`/`stg_cur_name`/…), plus single booting printer
  /// poll is often partial/noisy. Unconditional overwrite of "live" fields
  /// (progress, temps, fans) would briefly blank them to "—", next poll restores
  /// → flicker every 5s on REST fallback (before WS connects). Field genuinely
  /// changing always arrives non-null (e.g. `connected:false`, fan `0`), so
  /// propagates; inheritance only catches missing field, not change.
  ///
  /// `temperatures` merged PER-KEY (overlay): missing sensor in frame doesn't
  /// blank its tile, present sensors get fresh reads.
  ///
  /// Exception to the whole "never zero" rule: a `connected:false` result is
  /// normalised by [_clearedIfOffline] — a disconnected printer has no live
  /// state, and its frame's telemetry is only the server's stale cache.
  PrinterStatus mergedWith(PrinterStatus? previous) {
    if (previous == null) return _clearedIfOffline();
    // Exception to inheritance rule: cover is tied to SPECIFIC file. When frame
    // carries different `gcode_file`/`current_print` than previous (new print or
    // entering calibration phase "auto_cali_for_user_param.gcode"), previous
    // print's cover no longer applies — must NOT inherit, else card & widget
    // briefly show previous model preview (calibration has no own cover, frame
    // carries null). Inheritance stays if file unchanged — REST lacks
    // `cover_url` so without this cover would flicker every poll.
    final job = gcodeFile ?? currentPrint;
    final prevJob = previous.gcodeFile ?? previous.currentPrint;
    final jobChanged = job != null && prevJob != null && job != prevJob;
    final inheritedCover = jobChanged ? null : previous.coverUrl;
    return PrinterStatus(
      id: id,
      name: name ?? previous.name,
      connected: connected ?? previous.connected,
      state: state ?? previous.state,
      currentPrint: currentPrint ?? previous.currentPrint,
      gcodeFile: gcodeFile ?? previous.gcodeFile,
      progress: progress ?? previous.progress,
      remainingTime: remainingTime ?? previous.remainingTime,
      layerNum: layerNum ?? previous.layerNum,
      totalLayers: totalLayers ?? previous.totalLayers,
      temperatures: _mergeTemps(previous.temperatures),
      coverUrl: coverUrl ?? inheritedCover,
      stgCur: stgCur ?? previous.stgCur,
      stgCurName: stgCurName ?? previous.stgCurName,
      coolingFanSpeed: coolingFanSpeed ?? previous.coolingFanSpeed,
      bigFan1Speed: bigFan1Speed ?? previous.bigFan1Speed,
      bigFan2Speed: bigFan2Speed ?? previous.bigFan2Speed,
      leftAuxFanSpeed: leftAuxFanSpeed ?? previous.leftAuxFanSpeed,
      exhaustFanPresent: exhaustFanPresent ?? previous.exhaustFanPresent,
      heatbreakFanSpeed: heatbreakFanSpeed ?? previous.heatbreakFanSpeed,
      speedLevel: speedLevel ?? previous.speedLevel,
      chamberLight: chamberLight ?? previous.chamberLight,
      airductMode: airductMode ?? previous.airductMode,
      ams: ams ?? previous.ams,
      vtTray: vtTray ?? previous.vtTray,
      trayNow: trayNow ?? previous.trayNow,
      activeExtruder: activeExtruder ?? previous.activeExtruder,
      amsExtruderMap: amsExtruderMap ?? previous.amsExtruderMap,
      amsSwitchInlet: amsSwitchInlet ?? previous.amsSwitchInlet,
      model: model ?? previous.model,
      wifiSignal: wifiSignal ?? previous.wifiSignal,
      doorOpen: doorOpen ?? previous.doorOpen,
      awaitingPlateClear: awaitingPlateClear ?? previous.awaitingPlateClear,
      hmsErrors: hmsErrors ?? previous.hmsErrors,
      supportsDrying: supportsDrying ?? previous.supportsDrying,
      nozzles: nozzles ?? previous.nozzles,
      filaSwitch: filaSwitch ?? previous.filaSwitch,
      extruderSlots: extruderSlots ?? previous.extruderSlots,
    )._clearedIfOffline();
  }

  /// Blank runtime telemetry when the printer is disconnected. On the backend an
  /// MQTT drop flips `connected:false` but never clears the last-known state
  /// (see bambu_mqtt `_on_disconnect`), so a disconnected frame still carries
  /// "printing at 60%, nozzle 210°C". Left alone, [mergedWith]'s inheritance
  /// then pins that stale snapshot forever — the card/widget keep showing a
  /// ghost job, a wrong state label, and frozen temps. An offline printer has no
  /// live state, so drop it: `state`, the job, progress, temps, fans, lights,
  /// door, wifi, speed, airduct, stage.
  ///
  /// `exhaustFanPresent` is kept rather than dropped: it says which fans the
  /// machine physically has, not what they are doing, and surviving the outage
  /// means a base P2S doesn't flash a chamber tile on reconnect while waiting
  /// for its first airduct frame (`null` there falls back to "show it").
  ///
  /// `awaitingPlateClear` is kept for a different reason: it is not the
  /// printer's state at all. The plate-clear gate is bambuddy's own flag, held
  /// in its database so it survives the printer being switched off, and
  /// acknowledging it sends nothing to the machine. Dropping it here hid the
  /// only control that releases the gate on exactly the printers that need it —
  /// with Auto Power Off the end of every print is "gate up, printer off" —
  /// and made the queue's pre-start acknowledgement skip a printer that was
  /// waiting (server #2864).
  ///
  /// Kept: identity/hardware (`name`/`model`/`supportsDrying`/`nozzles`/`filaSwitch`),
  /// the physical AMS inventory
  /// (`ams`/`vtTray`/`amsExtruderMap`/`amsSwitchInlet`/`extruderSlots`/`trayNow`/`activeExtruder`)
  /// which survives a power-off, and `hmsErrors` — [PrintMonitor] pauses its HMS
  /// clear-grace clock on the carried-forward codes so a fault known before the
  /// outage doesn't re-alert on reconnect.
  ///
  /// `awaitingPlateClear` is kept for a different reason: it is not printer
  /// telemetry at all but a Bambuddy-side gate the server persists, and with
  /// Auto Power Off "finished, bed still full, printer switched off" is the
  /// normal end state. Dropping it left the acknowledgement unreachable exactly
  /// when it is needed. Carrying it forward cannot resurrect a stale gate on an
  /// older server either: those answer the status route for a disconnected
  /// printer with an explicit `awaiting_plate_clear: false`, which wins over the
  /// inherited value in [mergedWith] the same as any other field.
  PrinterStatus _clearedIfOffline() {
    if (connected != false) return this;
    return PrinterStatus(
      id: id,
      name: name,
      connected: false,
      model: model,
      supportsDrying: supportsDrying,
      nozzles: nozzles,
      exhaustFanPresent: exhaustFanPresent,
      ams: ams,
      vtTray: vtTray,
      amsExtruderMap: amsExtruderMap,
      amsSwitchInlet: amsSwitchInlet,
      trayNow: trayNow,
      activeExtruder: activeExtruder,
      filaSwitch: filaSwitch,
      extruderSlots: extruderSlots,
      hmsErrors: hmsErrors,
      awaitingPlateClear: awaitingPlateClear,
    );
  }

  /// Overlay temperature readings on previous: fresh keys override, missing
  /// inherit from last known (absent sensor in frame doesn't blank to "—").
  Map<String, double>? _mergeTemps(Map<String, double>? previous) {
    if (temperatures == null) return previous;
    if (previous == null) return temperatures;
    return {...previous, ...temperatures!};
  }

  /// Whether this model calls its enclosure fan the *exhaust* fan rather than
  /// the chamber fan. P2S/X2D follow the printer's own screen and Bambu Studio
  /// here; every other enclosed model (X1/P1S/H2*) says "chamber". Mirrors the
  /// server's `uses_exhaust_fan_label`, including its normalization, so a model
  /// reported as an internal code (`N7`/`N6`) resolves the same way.
  bool get usesExhaustFanLabel => const {'P2S', 'X2D', 'N7', 'N6'}
      .contains(model?.trim().toUpperCase().replaceAll(RegExp(r'[ -]'), ''));

  /// Whether to offer the enclosure fan (big fan 2) at all.
  ///
  /// On P2S/X2D that fan is the External Exhaust Fan kit — an accessory, not
  /// standard equipment — and the printer reports `big_fan2_speed` regardless,
  /// so the speed alone cannot tell a fitted machine from a base one. Servers
  /// from 1.2.5.2 answer that with [exhaustFanPresent]; older ones don't know,
  /// and `null` there keeps the pre-1.2.5.2 behaviour of showing the fan rather
  /// than hiding a control that works.
  bool get chamberFanAvailable =>
      bigFan2Speed != null &&
      (!usesExhaustFanLabel || (exhaustFanPresent ?? true));

  /// true = heating, false = cooling, null = none/unknown mode.
  bool? get airductIsHeating => switch (airductMode) {
        0 => false,
        1 => true,
        _ => null,
      };

  /// Speed percent matching [speedLevel] (Bambu mapping);
  /// null if level unknown/unset.
  int? get speedPercent => switch (speedLevel) {
        1 => 50,
        2 => 100,
        3 => 124,
        4 => 166,
        _ => null,
      };

  /// Whether print job is running — including prep phases (heating, auto bed
  /// leveling, pause) where `progress`/`remainingTime` may be zero but server
  /// reports active state. Falls back to progress data if server omits state.
  bool get isPrinting {
    switch (state?.toUpperCase()) {
      case 'RUNNING':
      case 'PREPARE':
      case 'PAUSE':
      case 'PAUSED':
        return true;
      case 'IDLE':
      case 'FINISH':
      case 'FINISHED':
      case 'FAILED':
        return false;
    }
    return (progress ?? 0) > 0 && (remainingTime ?? 0) > 0;
  }

  /// Prep phase: active print but no real progress yet — show stage name
  /// instead of 0% bar in UI.
  bool get isPreparing => isPrinting && (progress ?? 0) <= 0;

  /// Whether the printer reports being in a stage of its own rather than
  /// plainly printing: bed levelling, bed scanning, homing, nozzle cleaning, a
  /// pause, a filament change (`STAGE_NAMES` in the server's `bambu_mqtt.py`).
  ///
  /// Reads [stgCur] rather than [stgCurName], which is derived server-side and
  /// says "Printing" at stage 0 — a non-null name settles nothing. Different
  /// question from [isPreparing], which is about the percentage.
  ///
  /// Null counts as no stage. The field has been in every status the server
  /// sends since v0.1.6, older than any version this app talks to, so its
  /// absence means an unexpected shape rather than an old server — and for
  /// what reads this (whether a layer or a percentage describes the job) the
  /// answer that keeps the previous behaviour is the safe one.
  bool get inNamedStage {
    final stage = stgCur;
    return stage != null && stage > 0 && stage < 255;
  }

  /// Whether "print" is printer built-in calibration (e.g. file
  /// `auto_cali_for_user_param.gcode`). No own cover, so UI doesn't show
  /// thumbnail — else would hang previous model preview (cover inherited before
  /// frame zeroes it — see [mergedWith]).
  bool get isCalibration {
    final file = (gcodeFile ?? currentPrint)?.toLowerCase();
    if (file == null || file.isEmpty) return false;
    return file.contains('auto_cali') || file.contains('_cali_for_');
  }

  /// Print paused. Controls show "Resume" instead of "Pause". From server,
  /// so appears English in various forms.
  bool get isPaused => switch (state?.toUpperCase()) {
        'PAUSE' || 'PAUSED' => true,
        _ => false,
      };

  /// External spools sorted by global id ascending (254 = Ext-L first).
  List<AmsTray> get externalSpools {
    final list = [...?vtTray];
    list.sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));
    return list;
  }

  /// Dual-head machine — UI then distinguishes which material on which extruder
  /// (single-head doesn't need this).
  bool get isDualExtruder =>
      externalSpools.length > 1 ||
      (amsExtruderMap?.length ?? 0) > 1 ||
      // A Filament Track Switch exists to feed two nozzles from one AMS, and
      // the units it binds drop out of `ams_extruder_map` — on such a machine
      // the inlet map is the only thing left saying "dual".
      (amsSwitchInlet?.isNotEmpty ?? false);

  /// Extruder fed by the external spool whose `vt_tray` id is [trayId], or null
  /// when this printer reports no such spool.
  ///
  /// The pair is inverted against id order — [extruderForExternalSide] holds
  /// that table and the live verification behind it. A printer with a single
  /// holder has a single nozzle, and that one is extruder 0 however the holder
  /// happens to be numbered.
  int? extruderForExternal(int? trayId) {
    final spools = externalSpools;
    if (!spools.any((t) => t.id == trayId)) return null;
    return spools.length == 1 ? 0 : extruderForExternalSide(externalSideOf(trayId));
  }

  /// Currently loaded material on printer (on active extruder).
  ///
  /// `tray_now` is the firmware's global tray number, so it is read through
  /// [globalTrayId] — see that table for the three encodings behind it. An
  /// external spool is picked by [activeExtruder] rather than by the number
  /// alone: on a dual-head machine `tray_now` does not tell the two apart.
  AmsTray? get activeTray {
    final now = trayNow;
    if (now == null) return null;

    if (isExternalHolder(now)) {
      final spools = externalSpools;
      if (spools.isEmpty) return null;
      final ext = activeExtruder ?? 0;
      for (final t in spools) {
        if (extruderForExternal(t.id) == ext) return t;
      }
      // Fallback: match by ID, else first spool.
      return spools.firstWhere(
        (t) => t.id == now,
        orElse: () => spools.first,
      );
    }

    // Keyed on the unit's real hardware id, falling back to list position only
    // when it reports none: `tray_now` tracks the id, not the position, and a
    // machine left with one unit reporting id 1 gets that wrong either way.
    final units = ams ?? const [];
    for (var u = 0; u < units.length; u++) {
      final unitId = units[u].id ?? u;
      for (final t in units[u].trays ?? const []) {
        final slot = t.id;
        // An id-less tray cannot be addressed; assuming slot 0 for it would
        // match some other unit's slot rather than admit the gap.
        if (slot == null) continue;
        if (globalTrayId(amsId: unitId, trayId: slot) == now) return t;
      }
    }
    return null;
  }

  /// Whether there is any data to expand in details section (AMS, external
  /// spool, or connectivity/model metadata).
  bool get hasDetails =>
      (ams != null && ams!.isNotEmpty) ||
      (vtTray != null && vtTray!.isNotEmpty) ||
      model != null ||
      wifiSignal != null ||
      doorOpen != null;
}

/// Single AMS unit: humidity, temperature, and slots (trays).
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class AmsUnit {
  const AmsUnit({
    this.id,
    this.humidity,
    this.temp,
    this.trays,
    this.isAmsHt,
    this.dryTime,
    this.dryStatus,
    this.moduleType,
  });

  factory AmsUnit.fromJson(Map<String, dynamic> json) =>
      _$AmsUnitFromJson(json);

  @JsonKey(fromJson: toIntOrNull)
  final int? id;

  /// Whether this is AMS-HT module (high-temperature) — distinguished in
  /// humidity/temperature notifications. Server key `is_ams_ht`.
  final bool? isAmsHt;

  /// Humidity inside AMS in percent (if module measures).
  @JsonKey(fromJson: toIntOrNull)
  final int? humidity;

  /// Temperature inside AMS in °C (server sometimes sends as string).
  @JsonKey(fromJson: toDoubleOrNull)
  final double? temp;

  /// Filament slots. Server key is `tray`.
  @JsonKey(name: 'tray', fromJson: _toTrayListOrNull)
  final List<AmsTray>? trays;

  /// Minutes of drying remaining (`dry_time`); 0/null = not drying.
  @JsonKey(fromJson: toIntOrNull)
  final int? dryTime;

  /// Drying status (`dry_status`): 0=Off, 1=Checking, 2=Drying, 3=Cooling,
  /// 4=Stopping, 5=Error.
  @JsonKey(fromJson: toIntOrNull)
  final int? dryStatus;

  /// Module type: 'n3f' (AMS 2 Pro), 'n3s' (AMS-HT), 'ams' (original AMS), …
  /// Only the drying-capable modules ('n3f'/'n3s') accept dry commands.
  final String? moduleType;

  /// Whether this AMS module can dry filament (AMS 2 Pro or AMS-HT).
  bool get canDry => moduleType == 'n3f' || moduleType == 'n3s';

  /// AMS-HT (high-temp) module — dries hotter (up to 85 °C vs 65 °C).
  bool get isHtDryModule => moduleType == 'n3s';

  /// Whether a drying cycle is currently running (time remaining or an active
  /// status phase).
  bool get isDrying => (dryTime ?? 0) > 0 || (dryStatus ?? 0) == 2;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AmsUnit &&
          other.id == id &&
          other.isAmsHt == isAmsHt &&
          other.humidity == humidity &&
          other.temp == temp &&
          other.dryTime == dryTime &&
          other.dryStatus == dryStatus &&
          other.moduleType == moduleType &&
          _listAmsTrayEquality.equals(other.trays, trays);

  @override
  int get hashCode => Object.hash(
        id,
        isAmsHt,
        humidity,
        temp,
        dryTime,
        dryStatus,
        moduleType,
        trays == null ? null : _listAmsTrayEquality.hash(trays),
      );
}

/// Filament slot (AMS tray or external spool). Only fields needed for chips —
/// color, material, remaining amount; rest ignored.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class AmsTray {
  const AmsTray({
    this.id,
    this.trayColor,
    this.trayType,
    this.traySubBrands,
    this.remain,
    this.trayInfoIdx,
    this.caliIdx,
    this.tagUid,
    this.trayUuid,
  });

  factory AmsTray.fromJson(Map<String, dynamic> json) =>
      _$AmsTrayFromJson(json);

  @JsonKey(fromJson: toIntOrNull)
  final int? id;

  /// Filament color as hex RRGGBBAA (e.g. "F55A74FF"); null/empty = none.
  final String? trayColor;

  /// Material type (e.g. "PLA", "PETG", "TPU"); null/empty = empty slot.
  final String? trayType;

  /// Brand variant (e.g. "PLA Basic") if server provides.
  final String? traySubBrands;

  /// Remaining amount in percent (0–100); -1 = unknown (no RFID tag).
  @JsonKey(fromJson: toIntOrNull)
  final int? remain;

  /// Bambu filament id the printer has bound to this slot (`GFL05`, or a user
  /// preset's own id). Identifies which preset the slot is configured with —
  /// [traySubBrands] is only its name, and two presets can share one.
  final String? trayInfoIdx;

  /// Calibration profile the slot is using; -1 or null = the printer's default
  /// K. Read when re-opening the slot configuration so the K profile already in
  /// force is the one preselected.
  @JsonKey(fromJson: toIntOrNull)
  final int? caliIdx;

  /// RFID identifiers of the physical spool in the slot. The server sends both
  /// as null when the firmware reports an unwritten tag (empty or all-zero
  /// string), so a non-null value here means a real, readable tag.
  final String? tagUid;
  final String? trayUuid;

  /// Empty slot: no material or fully transparent color (alpha 00).
  bool get isEmpty {
    final type = trayType?.trim();
    if (type == null || type.isEmpty) return true;
    final color = trayColor;
    return color != null && color.length == 8 && color.endsWith('00');
  }

  /// Material label for chip (brand variant, if sensible).
  String? get materialLabel {
    final sub = traySubBrands?.trim();
    if (sub != null && sub.isNotEmpty) return sub;
    final type = trayType?.trim();
    return (type == null || type.isEmpty) ? null : type;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AmsTray &&
          other.id == id &&
          other.trayColor == trayColor &&
          other.trayType == trayType &&
          other.traySubBrands == traySubBrands &&
          other.remain == remain &&
          other.trayInfoIdx == trayInfoIdx &&
          other.caliIdx == caliIdx &&
          other.tagUid == tagUid &&
          other.trayUuid == trayUuid;

  @override
  int get hashCode => Object.hash(id, trayColor, trayType, traySubBrands,
      remain, trayInfoIdx, caliIdx, tagUid, trayUuid);
}

/// One fitted nozzle, from the status response's `nozzles` (index 0 =
/// left/primary). Only the diameter is read: the AMS slot configuration has to
/// send it, and it is also the key the printer's calibration table is indexed
/// by.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class NozzleInfo {
  const NozzleInfo({this.nozzleType, this.nozzleDiameter});

  factory NozzleInfo.fromJson(Map<String, dynamic> json) =>
      _$NozzleInfoFromJson(json);

  /// `stainless_steel` / `hardened_steel`.
  final String? nozzleType;

  /// As a string, e.g. `0.4` — the form both the server and the printer's own
  /// calibration table use, so it is never parsed into a number here.
  final String? nozzleDiameter;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NozzleInfo &&
          other.nozzleType == nozzleType &&
          other.nozzleDiameter == nozzleDiameter;

  @override
  int get hashCode => Object.hash(nozzleType, nozzleDiameter);
}

/// The Filament Track Switch (FTS), from the status response's `fila_switch`.
///
/// The accessory sits between the AMS units and the hotends: with one fitted an
/// AMS is no longer wired to a nozzle but plumbed into one of the switch's two
/// inlets, from where either hotend is reachable. That is why it matters here —
/// the firmware then has nothing to derive a load's target from and drops a
/// command that does not name one, so `PrinterCommandsRepository.amsLoad` has to
/// send the hotend and the user has to be asked which.
///
/// Only the two questions the app asks are read. The switch's own routing table
/// (`in`/`out`/`stat`/`info`) is the server's business.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class FilaSwitch {
  const FilaSwitch({this.installed = false, this.ready = false});

  factory FilaSwitch.fromJson(Map<String, dynamic> json) =>
      _$FilaSwitchFromJson(json);

  /// Whether the accessory is fitted at all.
  @JsonKey(fromJson: toBoolOrFalse)
  final bool installed;

  /// Whether every AMS has been bound to one of the switch's two inlets on the
  /// printer's own "Manual AMS Setup" screen. Until that is done the switch can
  /// route nothing, and a load command is dropped whatever hotend it names —
  /// Bambu Studio refuses one up front rather than send it, and so does the app.
  ///
  /// Absent on a server that reports `fila_switch` but predates the field: read
  /// as false, which blocks the load with an explanation rather than sending a
  /// command that would silently do nothing.
  @JsonKey(fromJson: toBoolOrFalse)
  final bool ready;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FilaSwitch &&
          other.installed == installed &&
          other.ready == ready;

  @override
  int get hashCode => Object.hash(installed, ready);
}

/// Which AMS slot one hotend is currently fed from, from `extruder_slots`.
///
/// Ids are **local** — [amsId] is the unit, [slotId] the slot within it — so
/// they compare against a slot's own coordinates, not against the global tray
/// number the load command takes.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class ExtruderSlot {
  const ExtruderSlot({this.amsId, this.slotId, this.hasFilament = false});

  factory ExtruderSlot.fromJson(Map<String, dynamic> json) =>
      _$ExtruderSlotFromJson(json);

  /// Null when this hotend is fed from nothing.
  @JsonKey(fromJson: toIntOrNull)
  final int? amsId;

  @JsonKey(fromJson: toIntOrNull)
  final int? slotId;

  @JsonKey(fromJson: toBoolOrFalse)
  final bool hasFilament;

  /// Whether this hotend is fed from the given slot.
  bool holds({required int amsId, required int slotId}) =>
      this.amsId == amsId && this.slotId == slotId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExtruderSlot &&
          other.amsId == amsId &&
          other.slotId == slotId &&
          other.hasFilament == hasFilament;

  @override
  int get hashCode => Object.hash(amsId, slotId, hasFilament);
}

/// Single printer HMS error from `hms_errors`. Server reports in two shapes per
/// version: `{code, attr, module, severity}` or `{code, message}` — so all
/// nullable, and `code` normalized to string (can be hex-string or number).
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class HmsError {
  const HmsError({
    this.code,
    this.message,
    this.severity,
    this.attr,
    this.module,
    this.actions = const [],
    this.jobId,
    this.fullCode,
    this.description,
  });

  factory HmsError.fromJson(Map<String, dynamic> json) =>
      _$HmsErrorFromJson(json);

  @JsonKey(fromJson: _toCodeStringOrNull)
  final String? code;

  final String? message;

  @JsonKey(fromJson: toIntOrNull)
  final int? severity;

  /// HMS attribute (upper 32 bits of full code). From Bambu firmware.
  @JsonKey(fromJson: toIntOrNull)
  final int? attr;

  /// Module/subsystem number, Bambu's `(attr >> 24) & 0xFF` (e.g. 5=mainboard,
  /// 7=AMS). Reported, never rendered: the code's own description is the only
  /// thing the UI shows (see `hmsIsDisplayable`).
  @JsonKey(fromJson: toIntOrNull)
  final int? module;

  /// Remediation actions the firmware offers for this fault, as `HMSAction`
  /// keys (`RESUME_PRINTING`, `IGNORE_RESUME`, …). The server resolves them from
  /// Bambu's catalog against the printer model, so the app renders what arrives
  /// instead of guessing. Empty on servers older than 0.2.4.8 and for faults
  /// Bambu lists no action for.
  @JsonKey(fromJson: _toStringListOrEmpty)
  final List<String> actions;

  /// `subtask_id` snapshotted onto the fault when it was parsed. Echoed back
  /// with the action so the firmware matches it to the right job.
  @JsonKey(fromJson: toStringOrNull)
  final String? jobId;

  /// The identifier the firmware matches HMS commands against, 8 hex chars for
  /// a `print_error` fault and 16 for an `hms[]` one, sent verbatim as
  /// `HmsActionBody.print_error`. Never rebuild it from [attr]/[code]: for the
  /// `print_error` path `attr` holds the whole 32-bit value, so the 16-char
  /// [ecode] this class composes would be a code the printer does not know, and
  /// the firmware drops such a command without a word.
  ///
  /// Null when the fault carries no identifier — the signal that no action can
  /// be offered for it. Two different servers arrive at that: one too old to
  /// send the field at all, and a current one whose `HMSError.full_code`
  /// defaults to `""`, which the parser folds into null so a blank never
  /// reaches the route (its regex demands 8 or 16 hex digits and answers 422).
  @JsonKey(fromJson: toStringOrNull)
  final String? fullCode;

  /// The sentence the server's own fault catalog holds for this code (server
  /// 1.2.5.4+, `#2926`). Null on older servers and on any code its table does
  /// not cover, which is most of the `hms[]` channel. English only — the server
  /// ships one language — so it is read as the fallback behind this app's own
  /// localized catalog, never before it (`HmsCatalog.describe`).
  @JsonKey(fromJson: toStringOrNull)
  final String? description;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HmsError &&
          other.code == code &&
          other.message == message &&
          other.severity == severity &&
          other.attr == attr &&
          other.module == module &&
          _stringListEquality.equals(other.actions, actions) &&
          other.jobId == jobId &&
          other.fullCode == fullCode &&
          other.description == description;

  @override
  int get hashCode => Object.hash(code, message, severity, attr, module,
      _stringListEquality.hash(actions), jobId, fullCode, description);

  /// Numeric value of `code` (firmware sends hex-string "0x20070" or number);
  /// null if `code` already in canonical form with separators.
  int? get _codeInt {
    final c = code?.trim();
    if (c == null || c.isEmpty) return null;
    if (c.contains('_') || c.contains('-')) return null;
    final hex = c.toLowerCase().startsWith('0x') ? c.substring(2) : c;
    return int.tryParse(hex, radix: 16);
  }

  /// Full 16-hex HMS code (`attr`+`code`) used by Bambu catalog, e.g.
  /// `0500060000020070`. null if missing `attr` or `code` not numeric.
  String? get ecode {
    final a = attr;
    final c = _codeInt;
    if (a == null || c == null) return null;
    return (a.toRadixString(16).padLeft(8, '0') +
            c.toRadixString(16).padLeft(8, '0'))
        .toUpperCase();
  }

  /// Bambu's short form `MMMM_EEEE` — module from `attr`'s high half, error
  /// from `code`'s low half. The key the print-error catalog is written in, and
  /// the fallback the server itself uses to look a fault up
  /// (`bambu_mqtt.py::_update_state`). null when `code` is not numeric.
  String? get shortCode {
    final a = attr;
    final c = _codeInt;
    if (a == null || c == null) return null;
    // An `hms[]` fault keeps the module in attr's high half; a `print_error`
    // one stores the whole 32-bit value there, and its low half is the module
    // — hence the fallback, which mirrors the server's own getShortCode.
    final module = (a >> 16) & 0xFFFF != 0
        ? (a >> 16) & 0xFFFF
        : ((a >> 8) & 0xFF) << 8 | (a & 0xFF);
    return '${module.toRadixString(16).padLeft(4, '0')}_'
            '${(c & 0xFFFF).toRadixString(16).padLeft(4, '0')}'
        .toUpperCase();
  }

  /// Readable canonical code with dashes: `0500-0600-0002-0070` for an `hms[]`
  /// fault, `0300-8004` for a `print_error` one — the form its own screen shows
  /// it in. Falls back to raw `code` (after separator normalization) when
  /// neither can be composed.
  String get displayCode {
    final full = fullCode;
    if (full != null && full.length == 8) {
      return '${full.substring(0, 4)}-${full.substring(4)}'.toUpperCase();
    }
    final e = ecode;
    if (e != null && e.length == 16) {
      return '${e.substring(0, 4)}-${e.substring(4, 8)}'
          '-${e.substring(8, 12)}-${e.substring(12, 16)}';
    }
    final c = code?.trim();
    if (c == null || c.isEmpty) return '?';
    return c.replaceAll('_', '-').replaceAll(' ', '-').toUpperCase();
  }
}

/// HMS code arrives as string (`"0x20070"`, `"0500_0100"`) or number — convert
/// to string for dedup in sets.
String? _toCodeStringOrNull(dynamic value) => switch (value) {
      String s when s.trim().isNotEmpty => s.trim(),
      num n => n.toString(),
      _ => null,
    };

/// Action keys — non-string elements dropped rather than crashing the frame.
///
/// Private on purpose, next to `json_utils`'s [toStringList]: this one trims and
/// drops what is left blank, because an empty action key would be echoed back to
/// the firmware as a command. Unifying the two would change what one of them
/// parses.
List<String> _toStringListOrEmpty(dynamic value) {
  if (value is! List) return const [];
  return [
    for (final e in value)
      if (e is String && e.trim().isNotEmpty) e.trim(),
  ];
}

/// The status is merged frame by frame, so every list here is read through
/// [parseJsonListOrNull]: a frame that does not carry the block has to answer
/// null (inherit what is known) rather than an empty list (the hardware is
/// gone). Each one is still a named function because `@JsonKey(fromJson:)`
/// takes a tear-off, not a closure.
List<HmsError>? _toHmsListOrNull(dynamic value) =>
    parseJsonListOrNull(value, HmsError.fromJson);

Map<String, double>? _toTemperaturesOrNull(dynamic value) {
  if (value is! Map) return null;
  final out = <String, double>{};
  for (final entry in value.entries) {
    final key = entry.key.toString();
    // The server mixes non-temperature metadata into this map (e.g.
    // `chamber_target_set_time`, a unix timestamp). Such keys parse as a
    // double and would render as a bogus sensor tile — drop time fields.
    // Real sensor keys (nozzle/bed/chamber + `_target`) never end in `_time`.
    if (key.endsWith('_time')) continue;
    final v = toDoubleOrNull(entry.value);
    if (v != null) out[key] = v;
  }
  return out;
}

/// Map `AMS ID → extruder` with string keys (`{"0":1}`) → `{0:1}`.
Map<int, int>? _toExtruderMapOrNull(dynamic value) =>
    parseJsonMapByIdOrNull(value, toIntOrNull);

/// `{ams_id: "A"|"B"}` — the inlet as the server spells it. [extruderForInlet]
/// is what decides whether a value means anything, so an unknown letter travels
/// rather than being dropped here.
Map<int, String>? _toInletMapOrNull(dynamic value) =>
    parseJsonMapByIdOrNull(value, toStringOrNull);

List<AmsUnit>? _toAmsListOrNull(dynamic value) =>
    parseJsonListOrNull(value, AmsUnit.fromJson);

/// Filament slots — AMS trays and external spools share one shape.
List<AmsTray>? _toTrayListOrNull(dynamic value) =>
    parseJsonListOrNull(value, AmsTray.fromJson);

List<NozzleInfo>? _toNozzleListOrNull(dynamic value) =>
    parseJsonListOrNull(value, NozzleInfo.fromJson);

/// Booleans the server may omit on an older version of a block it already
/// sends. Absent reads as false everywhere it is used here, and false is the
/// cautious answer in each case: no switch fitted, not set up, nothing loaded.
FilaSwitch? _toFilaSwitchOrNull(dynamic value) =>
    parseJsonObjectOrNull(value, FilaSwitch.fromJson);

/// Map `extruder id → slot` with string keys (`{"0": {...}}`) → `{0: ...}`.
Map<int, ExtruderSlot>? _toExtruderSlotMapOrNull(dynamic value) =>
    parseJsonMapByIdOrNull(
        value, (e) => parseJsonObjectOrNull(e, ExtruderSlot.fromJson));
