import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../common/qr_scanner_screen.dart';

/// Extracts spool id from bambuddy QR code content. Production format is URL
/// `https://<host>/inventory?spool=24` (param `spool`), but parser is intentionally
/// lenient — handles bare numbers, other param names, and id in path (`/inventory/spools/24`).
/// Returns null if nothing sensible can be read. Top-level (pure function) — testable without UI.
int? parseScannedSpoolId(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;

  // Bare number = spool id.
  final asInt = int.tryParse(s);
  if (asInt != null && asInt > 0) return asInt;

  final uri = Uri.tryParse(s);
  if (uri == null) return null;

  // Query param (production `spool`, plus variants as fallback).
  for (final key in const ['spool', 'spool_id', 'spoolId', 'id']) {
    final v = uri.queryParameters[key];
    final n = v == null ? null : int.tryParse(v.trim());
    if (n != null && n > 0) return n;
  }

  // Last numeric path segment (e.g. `/inventory/spools/24`).
  for (final seg in uri.pathSegments.reversed) {
    final n = int.tryParse(seg.trim());
    if (n != null && n > 0) return n;
  }
  return null;
}

/// Full-screen spool QR scanner. Thin wrapper over the shared [QrScannerScreen],
/// returning a spool id (`int`) via [Navigator.pop] on the first readable code.
class SpoolScannerScreen extends StatelessWidget {
  const SpoolScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return QrScannerScreen<int>(
      title: l10n.inventoryScanTitle,
      hint: l10n.inventoryScanHint,
      extract: parseScannedSpoolId,
    );
  }
}
