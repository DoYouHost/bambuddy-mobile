import 'package:collection/collection.dart';
import 'package:json_annotation/json_annotation.dart';

part 'printer_status.g.dart';

const _listAmsUnitEquality = ListEquality<AmsUnit>();
const _listAmsTrayEquality = ListEquality<AmsTray>();
const _listHmsErrorEquality = ListEquality<HmsError>();
const _mapStringDoubleEquality = MapEquality<String, double>();
const _mapIntIntEquality = MapEquality<int, int>();

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
    this.stgCurName,
    this.coolingFanSpeed,
    this.bigFan1Speed,
    this.bigFan2Speed,
    this.heatbreakFanSpeed,
    this.speedLevel,
    this.chamberLight,
    this.airductMode,
    this.ams,
    this.vtTray,
    this.trayNow,
    this.activeExtruder,
    this.amsExtruderMap,
    this.model,
    this.wifiSignal,
    this.doorOpen,
    this.awaitingPlateClear,
    this.hmsErrors,
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
  @JsonKey(fromJson: _toDoubleOrNull)
  final double? progress;

  /// Remaining time in minutes.
  @JsonKey(fromJson: _toIntOrNull)
  final int? remainingTime;

  @JsonKey(fromJson: _toIntOrNull)
  final int? layerNum;

  @JsonKey(fromJson: _toIntOrNull)
  final int? totalLayers;

  /// Undocumented keys from server (usually nozzle/bed/chamber) — render
  /// whatever arrives, don't assume set.
  @JsonKey(fromJson: _toTemperaturesOrNull)
  final Map<String, double>? temperatures;

  /// Path to current print cover (e.g. `/api/v1/printers/1/cover`). Requires
  /// camera stream token as `?token=` parameter on fetch.
  final String? coverUrl;

  /// Current stage name from server (e.g. "Auto bed leveling", "Heating");
  /// null/empty outside prep phase. Comes in English.
  final String? stgCurName;

  /// Part cooling fan, 0–100%.
  @JsonKey(fromJson: _toIntOrNull)
  final int? coolingFanSpeed;

  /// Auxiliary fan (big fan 1), 0–100%.
  @JsonKey(fromJson: _toIntOrNull)
  final int? bigFan1Speed;

  /// Chamber fan (big fan 2), 0–100%.
  @JsonKey(fromJson: _toIntOrNull)
  final int? bigFan2Speed;

  /// Heatbreak fan, 0–100% (usually 0 — firmware-controlled).
  @JsonKey(fromJson: _toIntOrNull)
  final int? heatbreakFanSpeed;

  /// Bambu speed level: 1 Silent, 2 Standard, 3 Sport, 4 Ludicrous.
  @JsonKey(fromJson: _toIntOrNull)
  final int? speedLevel;

  /// Whether chamber light is on.
  final bool? chamberLight;

  /// Chamber airduct mode: 0 = cooling, 1 = heating. Other values → null
  /// in [airductIsHeating] (don't assume modes beyond known).
  @JsonKey(fromJson: _toIntOrNull)
  final int? airductMode;

  /// AMS units (one per module). Defensive parsing — non-map elements skipped,
  /// never breaks status.
  @JsonKey(fromJson: _toAmsListOrNull)
  final List<AmsUnit>? ams;

  /// External spool — same structure as AMS slot. Server usually provides 1–2
  /// entries (id 254/255).
  @JsonKey(fromJson: _toTrayListOrNull)
  final List<AmsTray>? vtTray;

  /// Global active slot number (AMS: unit*4 + slot; external 254/255).
  @JsonKey(fromJson: _toIntOrNull)
  final int? trayNow;

  /// Active extruder (nozzle) on dual-head printers (X2D/H2D); 0/1.
  /// null/0 on regular single-head.
  @JsonKey(fromJson: _toIntOrNull)
  final int? activeExtruder;

  /// Map "AMS unit ID → feeding extruder". Keys come as strings (e.g. `{"0":1}`)
  /// — normalize to int.
  @JsonKey(fromJson: _toExtruderMapOrNull)
  final Map<int, int>? amsExtruderMap;

  /// Printer model from server (e.g. "X2D", "P1S").
  final String? model;

  /// Wi-Fi signal strength in dBm (negative; closer to 0 = better). null = none/LAN.
  @JsonKey(fromJson: _toIntOrNull)
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
          other.stgCurName == stgCurName &&
          other.coolingFanSpeed == coolingFanSpeed &&
          other.bigFan1Speed == bigFan1Speed &&
          other.bigFan2Speed == bigFan2Speed &&
          other.heatbreakFanSpeed == heatbreakFanSpeed &&
          other.speedLevel == speedLevel &&
          other.chamberLight == chamberLight &&
          other.airductMode == airductMode &&
          _listAmsUnitEquality.equals(other.ams, ams) &&
          _listAmsTrayEquality.equals(other.vtTray, vtTray) &&
          other.trayNow == trayNow &&
          other.activeExtruder == activeExtruder &&
          _mapIntIntEquality.equals(other.amsExtruderMap, amsExtruderMap) &&
          other.model == model &&
          other.wifiSignal == wifiSignal &&
          other.doorOpen == doorOpen &&
          other.awaitingPlateClear == awaitingPlateClear &&
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
        stgCurName,
        coolingFanSpeed,
        bigFan1Speed,
        bigFan2Speed,
        heatbreakFanSpeed,
        speedLevel,
        chamberLight,
        airductMode,
        ams == null ? null : _listAmsUnitEquality.hash(ams),
        vtTray == null ? null : _listAmsTrayEquality.hash(vtTray),
        trayNow,
        activeExtruder,
        amsExtruderMap == null ? null : _mapIntIntEquality.hash(amsExtruderMap),
        model,
        wifiSignal,
        doorOpen,
        awaitingPlateClear,
        hmsErrors == null ? null : _listHmsErrorEquality.hash(hmsErrors),
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
  PrinterStatus mergedWith(PrinterStatus? previous) {
    if (previous == null) return this;
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
      stgCurName: stgCurName ?? previous.stgCurName,
      coolingFanSpeed: coolingFanSpeed ?? previous.coolingFanSpeed,
      bigFan1Speed: bigFan1Speed ?? previous.bigFan1Speed,
      bigFan2Speed: bigFan2Speed ?? previous.bigFan2Speed,
      heatbreakFanSpeed: heatbreakFanSpeed ?? previous.heatbreakFanSpeed,
      speedLevel: speedLevel ?? previous.speedLevel,
      chamberLight: chamberLight ?? previous.chamberLight,
      airductMode: airductMode ?? previous.airductMode,
      ams: ams ?? previous.ams,
      vtTray: vtTray ?? previous.vtTray,
      trayNow: trayNow ?? previous.trayNow,
      activeExtruder: activeExtruder ?? previous.activeExtruder,
      amsExtruderMap: amsExtruderMap ?? previous.amsExtruderMap,
      model: model ?? previous.model,
      wifiSignal: wifiSignal ?? previous.wifiSignal,
      doorOpen: doorOpen ?? previous.doorOpen,
      awaitingPlateClear: awaitingPlateClear ?? previous.awaitingPlateClear,
      hmsErrors: hmsErrors ?? previous.hmsErrors,
    );
  }

  /// Overlay temperature readings on previous: fresh keys override, missing
  /// inherit from last known (absent sensor in frame doesn't blank to "—").
  Map<String, double>? _mergeTemps(Map<String, double>? previous) {
    if (temperatures == null) return previous;
    if (previous == null) return temperatures;
    return {...previous, ...temperatures!};
  }

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

  /// External spools sorted by ID ascending (254, 255, …).
  List<AmsTray> get externalSpools {
    final list = [...?vtTray];
    list.sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));
    return list;
  }

  /// Dual-head machine — UI then distinguishes which material on which extruder
  /// (single-head doesn't need this).
  bool get isDualExtruder =>
      externalSpools.length > 1 || (amsExtruderMap?.length ?? 0) > 1;

  /// Extruder number fed by external spool with given `id`.
  ///
  /// H2D/X2D contract verified on live printer: spools map INVERSE to ID order —
  /// 254 → extruder 1 (left), 255 → extruder 0 (right). Hence inverted index
  /// vs [externalSpools] (ascending).
  int? extruderForExternal(int? trayId) {
    if (trayId == null) return null;
    final spools = externalSpools;
    final i = spools.indexWhere((t) => t.id == trayId);
    return i < 0 ? null : (spools.length - 1) - i;
  }

  /// Currently loaded material on printer (on active extruder).
  ///
  /// X2D/H2D contract assumption (verified live for AMS; adopted for spools per
  /// spec): `tray_now` ≥ 254 means external spool — then count spool feeding
  /// [activeExtruder] (254→extruder 0, 255→1). For `tray_now` < 254 it's AMS
  /// slot with global number `unit*4 + slot`.
  AmsTray? get activeTray {
    final now = trayNow;
    if (now == null) return null;

    // External spool: select by active extruder, not by ID alone
    // (on dual-head `tray_now` doesn't distinguish both spools unambiguously).
    if (now >= 254) {
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

    // AMS slot: global number = unit's real hardware id * 4 + slot number
    // (falling back to list position only when the unit reports no id —
    // `tray_now` is the firmware's own numbering, which tracks unit id, not
    // list position; see queue_mapping_sheet.dart / print_monitor.dart for
    // the same convention).
    final units = ams ?? const [];
    for (var u = 0; u < units.length; u++) {
      final unitId = units[u].id ?? u;
      for (final t in units[u].trays ?? const []) {
        if (unitId * 4 + (t.id ?? -1) == now) return t;
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
  const AmsUnit({this.id, this.humidity, this.temp, this.trays, this.isAmsHt});

  factory AmsUnit.fromJson(Map<String, dynamic> json) =>
      _$AmsUnitFromJson(json);

  @JsonKey(fromJson: _toIntOrNull)
  final int? id;

  /// Whether this is AMS-HT module (high-temperature) — distinguished in
  /// humidity/temperature notifications. Server key `is_ams_ht`.
  final bool? isAmsHt;

  /// Humidity inside AMS in percent (if module measures).
  @JsonKey(fromJson: _toIntOrNull)
  final int? humidity;

  /// Temperature inside AMS in °C (server sometimes sends as string).
  @JsonKey(fromJson: _toDoubleOrNull)
  final double? temp;

  /// Filament slots. Server key is `tray`.
  @JsonKey(name: 'tray', fromJson: _toTrayListOrNull)
  final List<AmsTray>? trays;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AmsUnit &&
          other.id == id &&
          other.isAmsHt == isAmsHt &&
          other.humidity == humidity &&
          other.temp == temp &&
          _listAmsTrayEquality.equals(other.trays, trays);

  @override
  int get hashCode => Object.hash(
        id,
        isAmsHt,
        humidity,
        temp,
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
  });

  factory AmsTray.fromJson(Map<String, dynamic> json) =>
      _$AmsTrayFromJson(json);

  @JsonKey(fromJson: _toIntOrNull)
  final int? id;

  /// Filament color as hex RRGGBBAA (e.g. "F55A74FF"); null/empty = none.
  final String? trayColor;

  /// Material type (e.g. "PLA", "PETG", "TPU"); null/empty = empty slot.
  final String? trayType;

  /// Brand variant (e.g. "PLA Basic") if server provides.
  final String? traySubBrands;

  /// Remaining amount in percent (0–100); -1 = unknown (no RFID tag).
  @JsonKey(fromJson: _toIntOrNull)
  final int? remain;

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
          other.remain == remain;

  @override
  int get hashCode =>
      Object.hash(id, trayColor, trayType, traySubBrands, remain);
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
  });

  factory HmsError.fromJson(Map<String, dynamic> json) =>
      _$HmsErrorFromJson(json);

  @JsonKey(fromJson: _toCodeStringOrNull)
  final String? code;

  final String? message;

  @JsonKey(fromJson: _toIntOrNull)
  final int? severity;

  /// HMS attribute (upper 32 bits of full code). From Bambu firmware.
  @JsonKey(fromJson: _toIntOrNull)
  final int? attr;

  /// Module/subsystem number (e.g. 5=mainboard, 7=AMS) — see `hmsModuleKey`.
  @JsonKey(fromJson: _toIntOrNull)
  final int? module;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HmsError &&
          other.code == code &&
          other.message == message &&
          other.severity == severity &&
          other.attr == attr &&
          other.module == module;

  @override
  int get hashCode => Object.hash(code, message, severity, attr, module);

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

  /// Readable canonical code with dashes: `0500-0600-0002-0070`. Falls back to
  /// raw `code` (after separator normalization) if full can't be composed.
  String get displayCode {
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

/// HMS error list — skip non-map elements (defensive parsing).
List<HmsError>? _toHmsListOrNull(dynamic value) {
  if (value is! List) return null;
  return [
    for (final e in value)
      if (e is Map) HmsError.fromJson(Map<String, dynamic>.from(e)),
  ];
}

double? _toDoubleOrNull(dynamic value) => switch (value) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };

int? _toIntOrNull(dynamic value) => switch (value) {
      num n => n.toInt(),
      String s => int.tryParse(s),
      _ => null,
    };

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
    final v = _toDoubleOrNull(entry.value);
    if (v != null) out[key] = v;
  }
  return out;
}

/// Map `AMS ID → extruder` with string keys (`{"0":1}`) → `{0:1}`.
Map<int, int>? _toExtruderMapOrNull(dynamic value) {
  if (value is! Map) return null;
  final out = <int, int>{};
  for (final entry in value.entries) {
    final k = _toIntOrNull(entry.key);
    final v = _toIntOrNull(entry.value);
    if (k != null && v != null) out[k] = v;
  }
  return out;
}

/// AMS unit list — skip non-map elements (defensive parsing).
List<AmsUnit>? _toAmsListOrNull(dynamic value) {
  if (value is! List) return null;
  return [
    for (final e in value)
      if (e is Map) AmsUnit.fromJson(Map<String, dynamic>.from(e)),
  ];
}

/// Filament slot list (AMS trays or spools) — skip non-map elements.
List<AmsTray>? _toTrayListOrNull(dynamic value) {
  if (value is! List) return null;
  return [
    for (final e in value)
      if (e is Map) AmsTray.fromJson(Map<String, dynamic>.from(e)),
  ];
}
