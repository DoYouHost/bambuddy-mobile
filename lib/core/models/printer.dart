import 'package:json_annotation/json_annotation.dart';

part 'printer.g.dart';

/// Printer configuration from `GET /printers` (PrinterResponse).
/// Defensive parsing: all except id/name are nullable, unknown keys ignored — API
/// is young and evolving.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class Printer {
  const Printer({
    required this.id,
    required this.name,
    this.model,
    this.ipAddress,
    this.location,
    this.isActive,
    this.serialNumber,
    this.nozzleCount,
    this.autoArchive,
    this.wearCostPerHour,
    this.servesWearCost = false,
  });

  factory Printer.fromJson(Map<String, dynamic> json) =>
      _$PrinterFromJson(json);

  final int id;
  final String name;
  final String? model;
  final String? ipAddress;
  final String? location;
  final bool? isActive;

  /// Hashed into the tag bambuddy links a spool without RFID by
  /// (`fallbackSpoolTag`).
  final String? serialNumber;

  /// 1 or 2, detected by the server from the printer's reports.
  final int? nozzleCount;

  final bool? autoArchive;

  /// What an hour of printing costs this printer in wear (#694); null = off.
  final double? wearCostPerHour;

  /// Whether the server knows [wearCostPerHour] at all — it sends the key,
  /// null or not, from 1.2.6. An older one would take the field on a `PATCH`
  /// and drop it without a word, so the editor offers it only on this answer.
  @JsonKey(readValue: _hasWearCostKey)
  final bool servesWearCost;
}

Object? _hasWearCostKey(Map<dynamic, dynamic> json, String _) =>
    json.containsKey('wear_cost_per_hour');

/// The distinct models of [printers], sorted, spelled exactly as the server
/// stores them: `target_model` and a pipeline's printer class are matched
/// against `Printer.model` with plain equality, so a normalised value would
/// match nothing.
List<String> distinctPrinterModels(Iterable<Printer> printers) => {
  for (final p in printers)
    if (p.model != null && p.model!.isNotEmpty) p.model!,
}.toList()..sort();
