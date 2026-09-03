// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'print_log_entry.dart';

// **************************************************************************
// CopyWithGenerator
// **************************************************************************

abstract class _$PrintLogEntryCWProxy {
  /// Creates a new instance with the provided field values.
  /// Passing `null` to a nullable field nullifies it, while `null` for a non-nullable field is ignored.
  ///
  /// Example:
  /// ```dart
  /// PrintLogEntry(...).copyWith(id: 12, name: "My name")
  /// ```
  PrintLogEntry call({
    int id,
    String status,
    DateTime createdAt,
    int? archiveId,
    String? printName,
    String? printerName,
    int? printerId,
    DateTime? startedAt,
    DateTime? completedAt,
    int? durationSeconds,
    String? filamentType,
    String? filamentColor,
    double? filamentUsedGrams,
    double? cost,
    double? energyKwh,
    double? energyCost,
    String? failureReason,
    String? thumbnailPath,
    int? createdById,
    String? createdByUsername,
  });
}

/// Callable proxy for `copyWith` functionality.
/// Use as `instanceOfPrintLogEntry.copyWith(...)`.
class _$PrintLogEntryCWProxyImpl implements _$PrintLogEntryCWProxy {
  const _$PrintLogEntryCWProxyImpl(this._value);

  final PrintLogEntry _value;

  /// Creates a new instance with the provided field values.
  /// Passing `null` to a nullable field nullifies it, while `null` for a non-nullable field is ignored.
  ///
  /// Example:
  /// ```dart
  /// PrintLogEntry(...).copyWith(id: 12, name: "My name")
  /// ```
  @override
  PrintLogEntry call({
    Object? id = const $CopyWithPlaceholder(),
    Object? status = const $CopyWithPlaceholder(),
    Object? createdAt = const $CopyWithPlaceholder(),
    Object? archiveId = const $CopyWithPlaceholder(),
    Object? printName = const $CopyWithPlaceholder(),
    Object? printerName = const $CopyWithPlaceholder(),
    Object? printerId = const $CopyWithPlaceholder(),
    Object? startedAt = const $CopyWithPlaceholder(),
    Object? completedAt = const $CopyWithPlaceholder(),
    Object? durationSeconds = const $CopyWithPlaceholder(),
    Object? filamentType = const $CopyWithPlaceholder(),
    Object? filamentColor = const $CopyWithPlaceholder(),
    Object? filamentUsedGrams = const $CopyWithPlaceholder(),
    Object? cost = const $CopyWithPlaceholder(),
    Object? energyKwh = const $CopyWithPlaceholder(),
    Object? energyCost = const $CopyWithPlaceholder(),
    Object? failureReason = const $CopyWithPlaceholder(),
    Object? thumbnailPath = const $CopyWithPlaceholder(),
    Object? createdById = const $CopyWithPlaceholder(),
    Object? createdByUsername = const $CopyWithPlaceholder(),
  }) {
    return PrintLogEntry(
      id: id == const $CopyWithPlaceholder() || id == null
          ? _value.id
          // ignore: cast_nullable_to_non_nullable
          : id as int,
      status: status == const $CopyWithPlaceholder() || status == null
          ? _value.status
          // ignore: cast_nullable_to_non_nullable
          : status as String,
      createdAt: createdAt == const $CopyWithPlaceholder() || createdAt == null
          ? _value.createdAt
          // ignore: cast_nullable_to_non_nullable
          : createdAt as DateTime,
      archiveId: archiveId == const $CopyWithPlaceholder()
          ? _value.archiveId
          // ignore: cast_nullable_to_non_nullable
          : archiveId as int?,
      printName: printName == const $CopyWithPlaceholder()
          ? _value.printName
          // ignore: cast_nullable_to_non_nullable
          : printName as String?,
      printerName: printerName == const $CopyWithPlaceholder()
          ? _value.printerName
          // ignore: cast_nullable_to_non_nullable
          : printerName as String?,
      printerId: printerId == const $CopyWithPlaceholder()
          ? _value.printerId
          // ignore: cast_nullable_to_non_nullable
          : printerId as int?,
      startedAt: startedAt == const $CopyWithPlaceholder()
          ? _value.startedAt
          // ignore: cast_nullable_to_non_nullable
          : startedAt as DateTime?,
      completedAt: completedAt == const $CopyWithPlaceholder()
          ? _value.completedAt
          // ignore: cast_nullable_to_non_nullable
          : completedAt as DateTime?,
      durationSeconds: durationSeconds == const $CopyWithPlaceholder()
          ? _value.durationSeconds
          // ignore: cast_nullable_to_non_nullable
          : durationSeconds as int?,
      filamentType: filamentType == const $CopyWithPlaceholder()
          ? _value.filamentType
          // ignore: cast_nullable_to_non_nullable
          : filamentType as String?,
      filamentColor: filamentColor == const $CopyWithPlaceholder()
          ? _value.filamentColor
          // ignore: cast_nullable_to_non_nullable
          : filamentColor as String?,
      filamentUsedGrams: filamentUsedGrams == const $CopyWithPlaceholder()
          ? _value.filamentUsedGrams
          // ignore: cast_nullable_to_non_nullable
          : filamentUsedGrams as double?,
      cost: cost == const $CopyWithPlaceholder()
          ? _value.cost
          // ignore: cast_nullable_to_non_nullable
          : cost as double?,
      energyKwh: energyKwh == const $CopyWithPlaceholder()
          ? _value.energyKwh
          // ignore: cast_nullable_to_non_nullable
          : energyKwh as double?,
      energyCost: energyCost == const $CopyWithPlaceholder()
          ? _value.energyCost
          // ignore: cast_nullable_to_non_nullable
          : energyCost as double?,
      failureReason: failureReason == const $CopyWithPlaceholder()
          ? _value.failureReason
          // ignore: cast_nullable_to_non_nullable
          : failureReason as String?,
      thumbnailPath: thumbnailPath == const $CopyWithPlaceholder()
          ? _value.thumbnailPath
          // ignore: cast_nullable_to_non_nullable
          : thumbnailPath as String?,
      createdById: createdById == const $CopyWithPlaceholder()
          ? _value.createdById
          // ignore: cast_nullable_to_non_nullable
          : createdById as int?,
      createdByUsername: createdByUsername == const $CopyWithPlaceholder()
          ? _value.createdByUsername
          // ignore: cast_nullable_to_non_nullable
          : createdByUsername as String?,
    );
  }
}

extension $PrintLogEntryCopyWith on PrintLogEntry {
  /// Returns a callable class used to build a new instance with modified fields.
  /// Example: `instanceOfPrintLogEntry.copyWith(...)`.
  // ignore: library_private_types_in_public_api
  _$PrintLogEntryCWProxy get copyWith => _$PrintLogEntryCWProxyImpl(this);
}
