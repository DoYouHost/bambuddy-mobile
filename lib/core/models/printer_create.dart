/// Request body for `POST /printers/` (PrinterCreate). Write-only shape — the
/// server tests the MQTT connection with these before persisting, so a wrong
/// access code / IP is rejected instead of creating a dead printer row.
///
/// Hand-written [toJson] (no codegen): optional nulls are omitted so the server
/// applies its own defaults.
class PrinterCreate {
  const PrinterCreate({
    required this.name,
    required this.serialNumber,
    required this.ipAddress,
    required this.accessCode,
    this.model,
    this.location,
    this.autoArchive = true,
  });

  final String name;
  final String serialNumber;
  final String ipAddress;
  final String accessCode;
  final String? model;
  final String? location;

  /// Auto-archive completed prints (server default is true).
  final bool autoArchive;

  Map<String, dynamic> toJson() => {
        'name': name,
        'serial_number': serialNumber,
        'ip_address': ipAddress,
        'access_code': accessCode,
        'auto_archive': autoArchive,
        if (model != null && model!.isNotEmpty) 'model': model,
        if (location != null && location!.isNotEmpty) 'location': location,
      };
}
