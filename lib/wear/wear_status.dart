import 'package:flutter/material.dart';

import '../core/models/printer_status.dart';

/// Normalized printer state for the watch UI. Kept intentionally coarse — the
/// watch only needs a glanceable label/color and which control buttons to show.
enum WearState { offline, printing, paused, finished, failed, idle }

/// Derives a [WearState] from a (possibly null) [PrinterStatus]. Mirrors the
/// derivation used by the home widget / dashboard so the watch reads the same.
WearState wearStateOf(PrinterStatus? s) {
  if (s == null || s.connected == false) return WearState.offline;
  if (s.isPaused) return WearState.paused;
  if (s.isPrinting) return WearState.printing;
  switch (s.state?.toUpperCase()) {
    case 'FINISH':
    case 'FINISHED':
      return WearState.finished;
    case 'FAILED':
      return WearState.failed;
  }
  return WearState.idle;
}

extension WearStateView on WearState {
  String get label => switch (this) {
        WearState.offline => 'Offline',
        WearState.printing => 'Printing',
        WearState.paused => 'Paused',
        WearState.finished => 'Finished',
        WearState.failed => 'Failed',
        WearState.idle => 'Idle',
      };

  Color get color => switch (this) {
        WearState.offline => const Color(0xFF9E9E9E),
        WearState.printing => const Color(0xFF4CAF50),
        WearState.paused => const Color(0xFFFFB300),
        WearState.finished => const Color(0xFF42A5F5),
        WearState.failed => const Color(0xFFEF5350),
        WearState.idle => const Color(0xFF90A4AE),
      };
}

/// "1h 23m" from remaining minutes; empty when unknown.
String formatEta(int? minutes) {
  if (minutes == null || minutes <= 0) return '';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}
