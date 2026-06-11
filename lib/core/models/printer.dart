import 'package:json_annotation/json_annotation.dart';

part 'printer.g.dart';

/// Konfiguracja drukarki z `GET /printers` (PrinterResponse).
/// Parsowanie defensywne: poza id/name wszystko nullable, nieznane
/// klucze ignorowane — API bambuddy jest młode i ruchliwe.
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
