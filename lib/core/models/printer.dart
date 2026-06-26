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
  });

  factory Printer.fromJson(Map<String, dynamic> json) =>
      _$PrinterFromJson(json);

  final int id;
  final String name;
  final String? model;
  final String? ipAddress;
  final String? location;
  final bool? isActive;
}
