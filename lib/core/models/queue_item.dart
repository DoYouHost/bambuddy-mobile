import 'package:json_annotation/json_annotation.dart';

part 'queue_item.g.dart';

/// Klasy statusu elementu kolejki — tolerancyjne na nieznane wartości serwera.
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

/// Element kolejki wydruku z `PrintQueueItemResponse`.
/// Parsowanie defensywne: poza id/position/status wszystko nullable, nieznane
/// klucze ignorowane — API bambuddy jest młode i ruchliwe.
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

  /// Surowy status z serwera (np. „printing", „completed") — nie enumujemy
  /// bezpośrednio, żeby nowe wartości nie wywalały parsera.
  /// Użyj [statusKind] do logiki warunkowej w UI.
  final String status;

  final int? printerId;
  final int? archiveId;
  final int? libraryFileId;
  final String? archiveName;
  final String? archiveThumbnail;

  /// Czy archiwum powiązanego wydruku zostało usunięte. Domyślnie false.
  @JsonKey(defaultValue: false)
  final bool archiveDeleted;

  final String? printerName;

  /// Szacowany czas wydruku w sekundach.
  final int? printTimeSeconds;

  /// Zużyty filament w gramach.
  final double? filamentUsedGrams;

  /// Typ filamentu — może być połączony przecinkami, np. „PETG, PLA".
  final String? filamentType;

  /// Kolor filamentu jako połączone heksy, np. „#FFD00B,#F55A74,#91202B".
  final String? filamentColor;

  /// Czy element przeskoczył w kolejce (jumped). Domyślnie false.
  @JsonKey(defaultValue: false)
  final bool beenJumped;

  final String? errorMessage;
  final String? waitingReason;
  final DateTime? createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;

  /// Tolerancyjny klasyfikator statusu — nieznane wartości serwera trafiają
  /// do [QueueItemStatusKind.unknown], nigdy nie wywalają UI.
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

  /// Czy element jest aktywny (czeka, zaplanowany, drukuje lub jest wstrzymany).
  bool get isActive =>
      statusKind == QueueItemStatusKind.printing ||
      statusKind == QueueItemStatusKind.paused ||
      statusKind == QueueItemStatusKind.pending ||
      statusKind == QueueItemStatusKind.scheduled;
}
