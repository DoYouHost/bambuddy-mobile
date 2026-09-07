/// Discovery environment info (`GET /discovery/info`).
class DiscoveryInfo {
  const DiscoveryInfo({required this.isDocker, required this.subnets});

  factory DiscoveryInfo.fromJson(Map<String, dynamic> json) {
    final raw = json['subnets'];
    return DiscoveryInfo(
      isDocker: json['is_docker'] == true,
      subnets: [
        if (raw is List)
          for (final s in raw)
            if (s != null) s.toString(),
      ],
    );
  }

  final bool isDocker;

  /// Candidate subnets in CIDR notation (e.g. "192.168.1.0/24").
  final List<String> subnets;
}

/// Subnet-scan progress (`GET /discovery/scan/status`, `POST /discovery/scan`).
class ScanStatus {
  const ScanStatus({
    required this.running,
    required this.scanned,
    required this.total,
  });

  factory ScanStatus.fromJson(Map<String, dynamic> json) => ScanStatus(
    running: json['running'] == true,
    scanned: (json['scanned'] as num?)?.toInt() ?? 0,
    total: (json['total'] as num?)?.toInt() ?? 0,
  );

  final bool running;
  final int scanned;
  final int total;
}

/// A printer found by SSDP or subnet scan (`GET /discovery/printers`).
class DiscoveredPrinter {
  const DiscoveredPrinter({
    required this.serial,
    required this.name,
    required this.ipAddress,
    this.model,
  });

  factory DiscoveredPrinter.fromJson(Map<String, dynamic> json) =>
      DiscoveredPrinter(
        serial: json['serial']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        ipAddress: json['ip_address']?.toString() ?? '',
        model: (json['model']?.toString().isEmpty ?? true)
            ? null
            : json['model'].toString(),
      );

  final String serial;
  final String name;
  final String ipAddress;
  final String? model;
}
