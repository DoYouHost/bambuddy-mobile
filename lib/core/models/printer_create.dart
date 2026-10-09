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

/// Request body for `PATCH /printers/{id}` (PrinterUpdate), shaped like the
/// web's edit dialog sends it (`EditPrinterModal.doSave`): every field each
/// time, the access code only when one was typed.
class PrinterUpdate {
  const PrinterUpdate({
    required this.name,
    required this.ipAddress,
    required this.autoArchive,
    required this.isActive,
    this.accessCode,
    this.model,
    this.location,
    this.wearCostPerHour,
    this.sendWearCost = false,
  });

  final String name;
  final String ipAddress;
  final bool autoArchive;

  /// False puts the printer in maintenance mode (#1476).
  final bool isActive;
  final String? accessCode;
  final String? model;
  final String? location;

  /// Null or 0 turns wear cost off, as the web sends it.
  final double? wearCostPerHour;

  /// Left out for a server that does not know the field.
  final bool sendWearCost;

  Map<String, dynamic> toJson() => {
    'name': name,
    'ip_address': ipAddress,
    'auto_archive': autoArchive,
    'is_active': isActive,
    // Left out when not set, as the web does.
    if (model != null && model!.isNotEmpty) 'model': model,
    // Null clears the location; leaving it out would keep the old one.
    'location': (location == null || location!.isEmpty) ? null : location,
    if (accessCode != null && accessCode!.isNotEmpty) 'access_code': accessCode,
    if (sendWearCost)
      'wear_cost_per_hour': (wearCostPerHour ?? 0) > 0 ? wearCostPerHour : null,
  };
}
