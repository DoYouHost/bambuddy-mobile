import 'package:json_annotation/json_annotation.dart';

import 'calibration_option.dart';
import 'json_utils.dart';
import 'variant_group.dart';

part 'queue_item.g.dart';

/// Queue item status kinds — tolerant of unknown server values.
enum QueueItemStatusKind {
  pending,
  scheduled,
  printing,
  paused,
  completed,
  cancelled,
  failed,
  unknown,
}

/// Print queue item from `PrintQueueItemResponse`.
/// Defensive parsing: all except id/position/status are nullable, unknown keys
/// ignored — API is young and evolving.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class QueueItem {
  const QueueItem({
    required this.id,
    required this.position,
    required this.status,
    this.printerId,
    this.archiveId,
    this.libraryFileId,
    this.archiveName,
    this.archiveThumbnail,
    this.archiveDeleted = false,
    this.libraryFileName,
    this.libraryFileThumbnail,
    this.printerName,
    this.printTimeSeconds,
    this.filamentUsedGrams,
    this.filamentType,
    this.filamentColor,
    this.amsMapping,
    this.beenJumped = false,
    this.variants = const [],
    this.archiveHasSlicerAmsMapping = false,
    this.errorMessage,
    this.waitingReason,
    this.createdAt,
    this.startedAt,
    this.completedAt,
    // Editable fields (Edit Queue Item screen). Defaults mirror the server's
    // `PrintQueueItemResponse` so an item missing them still edits sanely.
    this.targetModel,
    this.targetLocation,
    this.filamentOverrides,
    this.scheduledTime,
    this.requirePreviousSuccess = false,
    this.autoOffAfter = false,
    this.manualStart = false,
    this.plateId,
    this.bedLevelling = CalibrationOption.auto,
    this.flowCali = CalibrationOption.auto,
    this.vibrationCali = true,
    this.layerInspect = false,
    this.timelapse = false,
    this.useAms = true,
    this.nozzleOffsetCali = CalibrationOption.auto,
    this.preheatOverride = 'inherit',
    this.preheatChamberTargetOverride,
    this.gcodeInjection = false,
    this.nozzleMapping,
    this.slicedForModel,
  });

  factory QueueItem.fromJson(Map<String, dynamic> json) =>
      _$QueueItemFromJson(json);

  /// A print job the user is configuring BEFORE it exists server-side — what
  /// the create form starts from (see `QueueEditScreen` in create mode).
  ///
  /// [plateId] matters for a reprint: the print starts on `plate_id or 1`
  /// server-side, so a draft that drops the archive's plate reprints plate 1 of
  /// a multi-plate file instead of the plate the archive is a record of.
  ///
  /// [id] and [position] are placeholders that nothing reads: create posts a
  /// body built from the form, and the item gets its real identity from the
  /// server's response. [name] and [thumbnail] land on the archive or library
  /// fields depending on which source id is given, so `displayName` and the
  /// header thumbnail work the same as for a real item.
  factory QueueItem.draft({
    int? archiveId,
    int? libraryFileId,
    String? name,
    String? thumbnail,
    int? printerId,
    String? printerName,
    String? filamentType,
    String? filamentColor,
    String? slicedForModel,
    int? plateId,
    bool manualStart = false,
  }) {
    final isArchive = archiveId != null;
    return QueueItem(
      id: 0,
      position: 0,
      status: 'pending',
      archiveId: archiveId,
      libraryFileId: libraryFileId,
      archiveName: isArchive ? name : null,
      archiveThumbnail: isArchive ? thumbnail : null,
      libraryFileName: isArchive ? null : name,
      libraryFileThumbnail: isArchive ? null : thumbnail,
      printerId: printerId,
      printerName: printerName,
      filamentType: filamentType,
      filamentColor: filamentColor,
      slicedForModel: slicedForModel,
      plateId: plateId,
      manualStart: manualStart,
    );
  }

  final int id;
  final int position;

  /// Raw status from server (e.g. "printing", "completed") — not directly
  /// enum-backed to allow new values without breaking. Use [statusKind]
  /// for conditional logic in UI.
  final String status;

  final int? printerId;
  final int? archiveId;
  final int? libraryFileId;
  final String? archiveName;
  final String? archiveThumbnail;

  /// Whether associated print archive was deleted. Defaults to false.
  @JsonKey(defaultValue: false)
  final bool archiveDeleted;

  /// Name/thumbnail for items queued from a library file (no archive). Without
  /// these the tile falls back to `#id` and a placeholder.
  final String? libraryFileName;
  final String? libraryFileThumbnail;

  final String? printerName;

  /// Estimated print time in seconds.
  final int? printTimeSeconds;

  /// Used filament in grams.
  final double? filamentUsedGrams;

  /// Filament type — may be comma-separated, e.g. "PETG, PLA".
  final String? filamentType;

  /// Filament color as combined hex values, e.g. "#FFD00B,#F55A74,#91202B".
  final String? filamentColor;

  /// AMS slot mapping: `ams_mapping[i]` = global AMS tray (`unit*4 + slot`, or
  /// 254/255 for external spools) feeding the file's i-th filament. Null until
  /// the user maps it. Used to prefill the mapping sheet.
  final List<int>? amsMapping;

  /// Whether item jumped in queue. Defaults to false.
  @JsonKey(defaultValue: false)
  final bool beenJumped;

  /// Whether dispatch will reuse the AMS slots the slicer itself resolved for
  /// the source archive, instead of the scheduler re-deriving them from the
  /// file's filament type and colour (`archive_has_slicer_ams_mapping`, server
  /// ≥ 1.2.5.2). The distinction matters with two spools of the same material
  /// and colour, where re-deriving picks either one.
  ///
  /// The server sets this only when the saved mapping was resolved against
  /// *this* row's own printer — a tray number means nothing on another machine
  /// — so it already answers "will it actually be reused", not "does one
  /// exist". Absent on older servers, which is the same as no saved mapping:
  /// they never stored one.
  @JsonKey(defaultValue: false)
  final bool archiveHasSlicerAmsMapping;

  final String? errorMessage;
  final String? waitingReason;

  @JsonKey(fromJson: dateTimeFromJson)
  final DateTime? createdAt;
  @JsonKey(fromJson: dateTimeFromJson)
  final DateTime? startedAt;
  @JsonKey(fromJson: dateTimeFromJson)
  final DateTime? completedAt;

  // --- Editable fields (Edit Queue Item screen) ---

  /// Target printer model for model-based assignment (`Any <model>`). Mutually
  /// exclusive with [printerId] server-side.
  final String? targetModel;

  /// Location filter, only meaningful together with [targetModel].
  final String? targetLocation;

  /// Sparse per-slot overrides for model-based assignment, e.g.
  /// `[{"slot_id":1,"type":"PLA","color":"#FFFFFF","force_color_match":false}]`.
  /// Null = use the file's original values.
  final List<Map<String, dynamic>>? filamentOverrides;

  /// Scheduled start time. Null = ASAP/queue (eligible immediately).
  @JsonKey(fromJson: dateTimeFromJson)
  final DateTime? scheduledTime;

  /// Only start if the previous print succeeded.
  @JsonKey(defaultValue: false)
  final bool requirePreviousSuccess;

  /// Power off the printer after this print finishes.
  @JsonKey(defaultValue: false)
  final bool autoOffAfter;

  /// Requires a manual trigger to start (staged). Only settable in queue mode.
  @JsonKey(defaultValue: false)
  final bool manualStart;

  /// 1-indexed plate for multi-plate 3MF; null = auto/plate 1.
  final int? plateId;

  /// Print options — defaults mirror the server model.
  ///
  /// The three calibrations are tri-state from bambuddy 1.2.5 on and plain
  /// booleans before it; [calibrationFromJson] reads either, which is what keeps
  /// the queue screen from emptying itself against a newer server (see
  /// [CalibrationOption]). The other four never migrated and stay booleans.
  @JsonKey(fromJson: calibrationFromJson)
  final CalibrationOption bedLevelling;
  @JsonKey(fromJson: calibrationFromJson)
  final CalibrationOption flowCali;
  @JsonKey(defaultValue: true)
  final bool vibrationCali;
  @JsonKey(defaultValue: false)
  final bool layerInspect;
  @JsonKey(defaultValue: false)
  final bool timelapse;
  @JsonKey(defaultValue: true)
  final bool useAms;
  @JsonKey(fromJson: calibrationFromJson)
  final CalibrationOption nozzleOffsetCali;

  /// Preheat & heat-soak override: `inherit` | `on` | `off`.
  @JsonKey(defaultValue: 'inherit')
  final String preheatOverride;

  /// Chamber target override in °C. Null = derive from filament defaults. The
  /// accepted ceiling is the server's, not a constant — see
  /// [ServerVersion.chamberMaxTargetC].
  final int? preheatChamberTargetOverride;

  /// Auto-print G-code injection.
  @JsonKey(defaultValue: false)
  final bool gcodeInjection;

  /// Dual-nozzle-rack physical pick (H2C/O1C2); opaque, forwarded verbatim.
  final List<int>? nozzleMapping;

  /// Model the file was sliced for, e.g. "X2D". Drives the `Any <model>` label
  /// and dual-nozzle option visibility.
  final String? slicedForModel;

  /// Cross-model alternatives in priority order (server #671) — several sliced
  /// files, one job, whichever printer frees up first. Empty for every ordinary
  /// item and on every server before 1.2.6.
  ///
  /// Present only until dispatch resolves one onto the row, after which
  /// [libraryFileId] and [targetModel] name the candidate that actually ran. So
  /// a non-empty list also means "not started yet".
  @JsonKey(fromJson: _variantsFromJson)
  final List<PrintVariant> variants;

  /// Whether this item is still choosing between printers rather than waiting
  /// for one. Drives the `Any of N` label instead of `Any <model>`.
  bool get isCrossModel => variants.isNotEmpty;

  /// Tile title: archive name, else library file name, else `#id`.
  String get displayName => archiveName ?? libraryFileName ?? '#$id';

  /// Tolerant status classifier — unknown server values map to
  /// [QueueItemStatusKind.unknown], never break UI.
  QueueItemStatusKind get statusKind {
    switch (status.toLowerCase()) {
      case 'pending':
      case 'queued':
        return QueueItemStatusKind.pending;
      case 'scheduled':
        return QueueItemStatusKind.scheduled;
      case 'printing':
        return QueueItemStatusKind.printing;
      case 'paused':
        return QueueItemStatusKind.paused;
      case 'completed':
        return QueueItemStatusKind.completed;
      case 'cancelled':
      case 'canceled':
        return QueueItemStatusKind.cancelled;
      case 'failed':
      case 'error':
        return QueueItemStatusKind.failed;
      default:
        return QueueItemStatusKind.unknown;
    }
  }

  /// Whether item is active (pending, scheduled, printing, or paused).
  bool get isActive =>
      statusKind == QueueItemStatusKind.printing ||
      statusKind == QueueItemStatusKind.paused ||
      statusKind == QueueItemStatusKind.pending ||
      statusKind == QueueItemStatusKind.scheduled;
}

List<PrintVariant> _variantsFromJson(dynamic value) =>
    parseJsonList(value, PrintVariant.fromJson);
