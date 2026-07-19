/// Result of a pre-save connection diagnostic (`POST /printers/diagnostic`).
/// Defensive manual parsing — the check catalog evolves server-side, so unknown
/// ids/statuses are kept verbatim and rendered generically.
class PrinterDiagnosticResult {
  const PrinterDiagnosticResult({
    required this.ipAddress,
    required this.overall,
    required this.checks,
  });

  factory PrinterDiagnosticResult.fromJson(Map<String, dynamic> json) {
    final rawChecks = json['checks'];
    return PrinterDiagnosticResult(
      ipAddress: json['ip_address']?.toString() ?? '',
      overall: json['overall']?.toString() ?? 'problems',
      checks: [
        if (rawChecks is List)
          for (final c in rawChecks)
            if (c is Map) DiagnosticCheck.fromJson(Map<String, dynamic>.from(c)),
      ],
    );
  }

  final String ipAddress;

  /// "ok" | "warnings" | "problems".
  final String overall;
  final List<DiagnosticCheck> checks;
}

/// One diagnostic check. [id] is a stable key (port_mqtt, port_ftps, port_rtsps,
/// network_mode, subnet, mqtt_auth, developer_mode); [status] is
/// "pass" | "fail" | "warn" | "skip".
class DiagnosticCheck {
  const DiagnosticCheck({required this.id, required this.status});

  factory DiagnosticCheck.fromJson(Map<String, dynamic> json) => DiagnosticCheck(
        id: json['id']?.toString() ?? '',
        status: json['status']?.toString() ?? 'skip',
      );

  final String id;
  final String status;
}
