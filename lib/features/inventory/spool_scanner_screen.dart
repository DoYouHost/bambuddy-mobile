import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';

/// Fixed dark tokens regardless of system theme: this screen is a full-screen
/// camera overlay (always black chrome + light text for contrast on the live
/// preview), so it doesn't follow light/dark system theme like other screens.
const _kScanTokens = DashTokens.dark();

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

/// Full-screen spool QR code scanner. Closes on first successful read, returns spool id
/// via [Navigator.pop] (`int`). Cancel/back → returns null. Manages camera controller
/// (start/stop with lifecycle, dispose). Camera permission handled by [MobileScanner]
/// (runtime request + `errorBuilder` for denial).
class SpoolScannerScreen extends StatefulWidget {
  const SpoolScannerScreen({super.key});

  @override
  State<SpoolScannerScreen> createState() => _SpoolScannerScreenState();
}

class _SpoolScannerScreenState extends State<SpoolScannerScreen> {
  // `autoStart: false` + explicit `start()` in initState — pattern from official package example.
  // We DON'T manage lifecycle with manual observer: start/stop would race with permission
  // request (dialog puts app to sleep) and leave detached texture → black preview on real device.
  final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );

  /// Guard against multiple pops — camera can fire several reads before screen closes.
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    unawaited(_controller.start());
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final id = parseScannedSpoolId(raw);
      if (id != null) {
        _handled = true;
        Navigator.of(context).pop(id);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = _kScanTokens;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: t.textPrimary,
        elevation: 0,
        title: Text(
          l10n.inventoryScanTitle,
          style: TextStyle(
            fontFamily: DashTokens.fontUi,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: t.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => _controller.toggleTorch(),
            icon: ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (context, state, _) => Icon(
                state.torchState == TorchState.on
                    ? Icons.flash_on
                    : Icons.flash_off,
                color: state.torchState == TorchState.on
                    ? t.accentGreen
                    : t.textPrimary,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) =>
                _ScannerError(error: error, l10n: l10n),
          ),
          IgnorePointer(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    border: Border.all(color: t.accentGreen, width: 3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    l10n.inventoryScanHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: DashTokens.fontUi,
                      color: t.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      shadows: const [Shadow(blurRadius: 8, color: Colors.black)],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fallback message when camera is unavailable — usually permission denial.
/// Show clear reason and back button.
class _ScannerError extends StatelessWidget {
  const _ScannerError({required this.error, required this.l10n});

  final MobileScannerException error;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final t = _kScanTokens;
    final denied =
        error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              denied ? Icons.no_photography_outlined : Icons.error_outline,
              color: t.textSecondary,
              size: 56,
            ),
            const SizedBox(height: 16),
            Text(
              denied
                  ? l10n.inventoryScanPermissionTitle
                  : l10n.inventoryScanTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: DashTokens.fontUi,
                color: t.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (denied) ...[
              const SizedBox(height: 8),
              Text(
                l10n.inventoryScanPermissionBody,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: DashTokens.fontUi, color: t.textSecondary),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              style: dashPrimaryButtonStyle(t),
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text(MaterialLocalizations.of(context).closeButtonLabel),
            ),
          ],
        ),
      ),
    );
  }
}
