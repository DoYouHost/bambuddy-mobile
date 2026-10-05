import 'package:app_util/app_util.dart';
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';

import '../format/filament_colour.dart';
import 'json_utils.dart';

part 'archive.g.dart';

/// Archive entry from `ArchiveResponse`.
/// Defensive parsing: all fields except id/filename/status are nullable, unknown
/// keys ignored — the API is young and evolving.
///
/// [copyWith] is generated from the constructor (`skipFields` keeps it to the
/// one call shape). It used to be a hand-written `withFavorite` that re-listed
/// every field, so each new field had to be added twice or it was silently
/// dropped on the copy — which is exactly what nearly happened to `plate_id`.
@CopyWith(skipFields: true)
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class Archive {
  const Archive({
    required this.id,
    required this.filename,
    required this.status,
    this.printerId,
    this.printName,
    this.plateId,
    this.completedAt,
    this.thumbnailPath,
    this.timelapsePath,
    this.photos = const [],
    this.printTimeSeconds,
    this.filamentUsedGrams,
    this.totalFilamentActualGrams,
    this.runCount = 0,
    this.filamentType,
    this.filamentColor,
    this.cost,
    this.isFavorite = false,
    this.createdAt,
    this.designer,
    this.makerworldUrl,
    this.totalLayers,
    this.layerHeight,
    this.nozzleDiameter,
    this.slicedForModel,
    this.quantity,
    this.fileSize,
    this.duplicateCount = 0,
    this.duplicateSequence = 0,
    this.userVerdict,
    this.userVerdictSource,
    this.userVerdictAt,
    this.confirmRequested = false,
    this.failureReason,
    this.slicerAmsMapping,
  });

  factory Archive.fromJson(Map<String, dynamic> json) =>
      _$ArchiveFromJson(json);

  final int id;

  final String filename;

  /// Raw status from server (e.g. "completed", "printing") — not enum-backed
  /// to avoid breaking on new server values.
  final String status;

  final int? printerId;

  /// Human-readable print name from user or slicer.
  final String? printName;

  /// Which plate of a multi-plate 3MF this run printed (1-indexed), or null for
  /// a single-plate file — and on every server older than #2603, which does not
  /// send the field at all.
  ///
  /// Load-bearing rather than decorative: the print starts on
  /// `item.plate_id or 1` (`print_scheduler.py`), so a reprint that drops this
  /// prints plate 1 instead of the plate the archive is a record of.
  @JsonKey(fromJson: toIntOrNull)
  final int? plateId;

  final String? thumbnailPath;

  /// Server-side path of the recorded timelapse, or null when the print has
  /// none. Read as a presence flag only — the video is fetched through
  /// `Endpoints.archiveTimelapse`, never from this path.
  final String? timelapsePath;

  bool get hasTimelapse => (timelapsePath ?? '').isNotEmpty;

  /// Filenames of the photos attached to the print — the shot the server
  /// captures from the camera when the print ends (named `finish_…`) plus
  /// anything uploaded in the web UI. Fetched through `Endpoints.archivePhoto`;
  /// the server only serves a name that appears in this list.
  @JsonKey(fromJson: toStringList)
  final List<String> photos;

  bool get hasPhotos => photos.isNotEmpty;

  /// Print time in seconds.
  final int? printTimeSeconds;

  /// Filament used in grams.
  ///
  /// The archive's own figure: the slicer's estimate read out of the 3MF, or
  /// what a user typed to correct it. Not what any run measured — that is
  /// [totalFilamentActualGrams].
  final double? filamentUsedGrams;

  /// What the runs of this file actually used, summed over all of them
  /// (`_load_run_aggregates`). Per run that is the tracked spool delta where
  /// the slots were mapped to inventory, the slicer estimate for a completed
  /// print without tracking, and estimate x progress for one that stopped
  /// partway.
  ///
  /// Null on a server older than the aggregate, **and** whenever the sum comes
  /// to zero: the route answers `float(total) if total else None`, so "the runs
  /// used nothing" and "no figure" arrive as the same value. [runCount] is what
  /// separates them — runs that exist and summed to null recorded no filament,
  /// which is what a print cancelled before its first layer looks like.
  final double? totalFilamentActualGrams;

  /// How many runs of this file the print log holds. Zero both for a file that
  /// was never printed and on a server that does not send the aggregate.
  @JsonKey(defaultValue: 0)
  final int runCount;

  /// Filament type (e.g. "PETG", "PLA").
  final String? filamentType;

  /// Filament color as hex (e.g. "#FFFF00").
  final String? filamentColor;

  /// Print cost in server-configured currency.
  final double? cost;

  /// Whether marked as favorite. Defaults to false.
  @JsonKey(defaultValue: false)
  final bool isFavorite;

  @JsonKey(fromJson: dateTimeFromJson)
  final DateTime? createdAt;

  /// When the print on this archive last ended. Unlike [createdAt] it is
  /// rewritten on every run — a reprint reuses the archive row and refreshes
  /// this and `started_at`, leaving `created_at` on the original print
  /// (`main.py`, expected-archive branch; `ArchiveService.update_status`). So
  /// this, not the row's age, says which print just finished.
  @JsonKey(fromJson: dateTimeFromJson)
  final DateTime? completedAt;

  /// Model designer/author (e.g. from MakerWorld).
  final String? designer;

  /// Link to model on MakerWorld, if imported from there.
  final String? makerworldUrl;

  final int? totalLayers;

  /// Layer height in mm.
  final double? layerHeight;

  /// Nozzle diameter in mm.
  final double? nozzleDiameter;

  /// Printer model this file was sliced for (e.g. "X2D").
  final String? slicedForModel;

  final int? quantity;

  /// File size in bytes (for size sorting).
  final int? fileSize;

  /// How many other archives duplicate this one (server-computed). 0 = unique.
  @JsonKey(defaultValue: 0)
  final int duplicateCount;

  /// Position of this archive within its duplicate group, oldest first.
  /// 0 marks the original (kept when "hide duplicates" is on); >0 are copies.
  @JsonKey(defaultValue: 0)
  final int duplicateSequence;

  /// The user's judgement of the part (#1898) — deliberately apart from
  /// [status], which is the machine's: `completed` + [PrintVerdict.reject] is
  /// "the printer finished it, the part is scrap". Null when nobody answered,
  /// and on every server older than the feature.
  @JsonKey(fromJson: PrintVerdict.fromWire)
  final PrintVerdict? userVerdict;

  /// How [userVerdict] arrived: `dialog`, `link`, `plate_clear`,
  /// `printer_card`, `api` or `reaction` (`services/print_confirmation.py`
  /// `VERDICT_SOURCES`). Kept raw: the server may add one, and the label for an
  /// unknown source is simply no label.
  final String? userVerdictSource;

  @JsonKey(fromJson: dateTimeFromJson)
  final DateTime? userVerdictAt;

  /// Whether this print asked for an outcome — copied from the queue item's
  /// `confirm_outcome` at dispatch, or set for a print started outside
  /// bambuddy when `confirm_outcome_external_prints` is on. Absent (false) on
  /// an older server; its presence in the payload is what
  /// `ArchiveRepository.outcomeCapability` observes.
  @JsonKey(defaultValue: false)
  final bool confirmRequested;

  /// Why the print failed, or why a completed one was rejected — an i18n key
  /// from the failure-reason list, or free text an older web build wrote (see
  /// `failureReasonLabel`).
  final String? failureReason;

  /// The AMS mapping the slicer sent with this print, and the printer it was
  /// resolved against — `extra_data.slicer_ams_mapping`, only on archives a
  /// virtual printer received. The web offers it as one "Mapping" button for
  /// that printer alone (`archiveAmsMapping.ts`).
  @JsonKey(name: 'extra_data', fromJson: _slicerAmsMapping)
  final ({int printerId, List<int> mapping})? slicerAmsMapping;

  /// The question is still open: the web's "unconfirmed" badge. Only a
  /// completed print is asked — a failed one already has its answer.
  bool get awaitsVerdict =>
      status == 'completed' && confirmRequested && userVerdict == null;

  String get displayName => printName ?? filename;

  /// Copy with a flipped/overridden favorite flag — for optimistic UI updates
  /// (the only field the app mutates locally).
  ///
  /// Kept as its own name rather than letting callers reach for [copyWith]: the
  /// favorite flag is the one field the app is allowed to decide by itself, and
  /// a named method says so where a general-purpose copy would not.
  Archive withFavorite(bool value) => copyWith(isFavorite: value);

  /// Whether this archive is a sliced/printable file rather than a source
  /// project. Mirrors bambuddy's `isSlicedFile`: a `.gcode`/`.gcode.*` name, or
  /// any file carrying sliced metadata (layer count / print-time estimate).
  bool get isSliced {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.gcode') || lower.contains('.gcode.')) return true;
    return (totalLayers ?? 0) > 0 || (printTimeSeconds ?? 0) > 0;
  }

  /// Filament colors as a list of hex tokens (a print can use several).
  /// See [filamentColourTokens] for why they stay verbatim.
  List<String> get filamentColors => filamentColourTokens(filamentColor);
}

/// A user's verdict on a printed part, as `ArchiveUpdate.user_verdict` spells
/// it.
enum PrintVerdict {
  good('good'),
  reject('reject');

  const PrintVerdict(this.wire);

  final String wire;

  /// Null for a missing verdict and for a spelling this build does not know —
  /// an unknown verdict is not a verdict it can show.
  static PrintVerdict? fromWire(Object? value) =>
      values.where((v) => v.wire == value).firstOrNull;
}

({int printerId, List<int> mapping})? _slicerAmsMapping(Object? extraData) {
  if (extraData is! Map<String, dynamic>) return null;
  final saved = extraData['slicer_ams_mapping'];
  if (saved is! Map<String, dynamic>) return null;
  final printerId = toIntOrNull(saved['printer_id']);
  final mapping = saved['mapping'];
  if (printerId == null || mapping is! List || mapping.isEmpty) return null;
  final ids = <int>[];
  for (final v in mapping) {
    final id = toIntOrNull(v);
    if (id == null) return null;
    ids.add(id);
  }
  return (printerId: printerId, mapping: ids);
}
