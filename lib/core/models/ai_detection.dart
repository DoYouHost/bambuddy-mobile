import 'package:app_util/app_util.dart';

import 'value_equality.dart';

/// What the server's AI failure detection says about one running print, as the
/// web's `aiDetectionClass` (`frontend/src/utils/aiDetection.ts`) reads it.
enum AiDetectionClass {
  failure,
  warning,
  safe,

  /// The last poll produced no verdict: the print is not being watched.
  error,

  /// Monitored, but no result has come back yet. Also every class this app
  /// does not know — never [safe], which would call an unwatched print healthy
  /// (server #2952).
  unknown;

  static AiDetectionClass parse(Object? value) => switch (value) {
    'failure' => failure,
    'warning' => warning,
    'safe' => safe,
    'error' => error,
    _ => unknown,
  };

  /// Whether this is a verdict, so the measurement beside it means something.
  bool get isVerdict => this == failure || this == warning || this == safe;
}

/// One printer's entry of `per_printer` on `GET /obico/printer-status` or
/// `GET /octoeverywhere/printer-status`. The server keeps an entry only while a
/// monitored print runs.
class AiDetection with ValueEquality {
  const AiDetection({
    required this.cls,
    this.frameCount = 0,
    this.score,
    this.printQuality,
    this.ratesQuality = false,
    this.error,
    this.errorCode,
  });

  factory AiDetection.fromJson(Map<String, dynamic> json) => AiDetection(
    cls: AiDetectionClass.parse(json['class']),
    frameCount: toIntOrNull(json['frame_count']) ?? 0,
    score: toDoubleOrNull(json['score']),
    printQuality: toIntOrNull(json['print_quality']),
    ratesQuality: json.containsKey('print_quality'),
    error: toStringOrNull(json['error']),
    errorCode: toStringOrNull(json['error_code']),
  );

  /// `error_code` when OctoEverywhere's free plan has run out
  /// (`OCTOEVERYWHERE_USAGE_LIMIT` in the web's `aiDetection.ts`).
  static const usageLimitCode = 'OE_FREE_USAGE_LIMIT_REACHED';

  final AiDetectionClass cls;
  final int frameCount;

  /// Obico's failure score, 0 and up. Null from OctoEverywhere.
  final double? score;

  /// OctoEverywhere's print quality, 1 (worst) to 10 (best). Null before its
  /// first result, and always from Obico.
  final int? printQuality;

  /// Whether the entry carries the `print_quality` key at all, which is how the
  /// web tells the two providers apart: OctoEverywhere sends it as null before
  /// its first result.
  final bool ratesQuality;

  /// Why the last poll produced no verdict. Null when it succeeded, and for a
  /// session without `settings:read`: the reason can name a configured URL, so
  /// the server withholds it and still sends the [AiDetectionClass.error] class.
  final String? error;
  final String? errorCode;

  bool get usageLimitReached => errorCode == usageLimitCode;

  @override
  List<Object?> get props => [
    cls,
    frameCount,
    score,
    printQuality,
    ratesQuality,
    error,
    errorCode,
  ];
}

/// `GET /obico/printer-status` or `GET /octoeverywhere/printer-status`: whether
/// detection is on, for which printers, and what it says about the prints that
/// are running. Deliberately no configuration, so `printers:read` is enough.
class AiDetectionStatus with ValueEquality {
  const AiDetectionStatus({
    required this.enabled,
    this.monitoredPrinters,
    this.perPrinter = const {},
  });

  factory AiDetectionStatus.fromJson(Map<String, dynamic> json) {
    final monitored = json['monitored_printers'];
    final entries = json['per_printer'];
    return AiDetectionStatus(
      enabled: json['enabled'] == true,
      monitoredPrinters: monitored is List
          ? {for (final id in monitored) ?toIntOrNull(id)}
          : null,
      perPrinter: {
        if (entries is Map)
          for (final MapEntry(:key, :value) in entries.entries)
            if (toIntOrNull(key) case final id?)
              if (value is Map)
                id: AiDetection.fromJson(Map<String, dynamic>.from(value)),
      },
    );
  }

  final bool enabled;

  /// Null when every printer is monitored.
  final Set<int>? monitoredPrinters;

  /// By printer id. JSON object keys are strings, so they are parsed here.
  final Map<int, AiDetection> perPrinter;

  /// The entry to show on [printerId]'s card, or null: detection off, the
  /// printer outside the monitored set, or no monitored print running — the
  /// three conditions of the web's badge (`isAiMonitored` and the
  /// `aiDetection` prop in `PrintersPage.tsx`).
  AiDetection? detectionFor(int printerId) {
    if (!enabled) return null;
    final monitored = monitoredPrinters;
    if (monitored != null && !monitored.contains(printerId)) return null;
    return perPrinter[printerId];
  }

  @override
  List<Object?> get props => [enabled, monitoredPrinters, perPrinter];
}
