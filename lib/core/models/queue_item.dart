import 'package:json_annotation/json_annotation.dart';

import 'calibration_option.dart';
import 'json_utils.dart';

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

  /// Chamber target override in °C (0–60). Null = derive from filament defaults.
  final int? preheatChamberTargetOverride;

  /// Auto-print G-code injection.
  @JsonKey(defaultValue: false)
  final bool gcodeInjection;

  /// Dual-nozzle-rack physical pick (H2C/O1C2); opaque, forwarded verbatim.
  final List<int>? nozzleMapping;

  /// Model the file was sliced for, e.g. "X2D". Drives the `Any <model>` label
  /// and dual-nozzle option visibility.
  final String? slicedForModel;

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
