import 'package:json_annotation/json_annotation.dart';

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
    this.printerName,
    this.printTimeSeconds,
    this.filamentUsedGrams,
    this.filamentType,
    this.filamentColor,
    this.beenJumped = false,
    this.errorMessage,
    this.waitingReason,
    this.createdAt,
    this.startedAt,
    this.completedAt,
  });

  factory QueueItem.fromJson(Map<String, dynamic> json) =>
      _$QueueItemFromJson(json);

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

  final String? printerName;

  /// Estimated print time in seconds.
  final int? printTimeSeconds;

  /// Used filament in grams.
  final double? filamentUsedGrams;

  /// Filament type — may be comma-separated, e.g. "PETG, PLA".
  final String? filamentType;

  /// Filament color as combined hex values, e.g. "#FFD00B,#F55A74,#91202B".
  final String? filamentColor;

  /// Whether item jumped in queue. Defaults to false.
  @JsonKey(defaultValue: false)
  final bool beenJumped;

  final String? errorMessage;
  final String? waitingReason;
  final DateTime? createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;

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
