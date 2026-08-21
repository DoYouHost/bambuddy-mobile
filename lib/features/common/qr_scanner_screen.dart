import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';

/// Fixed dark tokens regardless of system theme: this screen is a full-screen
/// camera overlay (always black chrome + light text for contrast on the live
/// preview), so it doesn't follow light/dark system theme like other screens.
const _kScanTokens = DashTokens.dark();

/// Full-screen QR code scanner, reusable across features. [extract] turns a raw
/// barcode value into the result [T] to return via [Navigator.pop] (returning
/// null ignores that read and keeps scanning). Closes on the first successful
/// extract; cancel/back → returns null. Camera permission is handled by
/// [MobileScanner] (runtime request + `errorBuilder` for denial).
class QrScannerScreen<T extends Object> extends StatefulWidget {
  const QrScannerScreen({
    super.key,
    required this.title,
    required this.hint,
    required this.extract,
  });

  /// App-bar title and the heading shown on the permission-denied fallback.
  final String title;

  /// Instruction line under the viewfinder.
  final String hint;

  /// Parses a scanned barcode into the value to return, or null to keep scanning.
  final T? Function(String raw) extract;

  @override
  State<QrScannerScreen<T>> createState() => _QrScannerScreenState<T>();
}

class _QrScannerScreenState<T extends Object>
    extends State<QrScannerScreen<T>> {
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
      final value = widget.extract(raw);
      if (value != null) {
        _handled = true;
        Navigator.of(context).pop(value);
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
      appBar: loggedAppBar(
        AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: t.textPrimary,
          elevation: 0,
          title: Text(
            widget.title,
            style: t.display.copyWith(letterSpacing: -0.3),
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
            ).tagged('scanner.torch'),
          ],
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) =>
                _ScannerError(error: error, title: widget.title, l10n: l10n),
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
                    widget.hint,
                    textAlign: TextAlign.center,
                    style: t.titleMd.copyWith(shadows: const [Shadow(blurRadius: 8, color: Colors.black)]),
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
  const _ScannerError({
    required this.error,
    required this.title,
    required this.l10n,
  });

  final MobileScannerException error;
  final String title;
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
              denied ? l10n.cameraPermissionTitle : title,
              textAlign: TextAlign.center,
              style: t.titleLg,
            ),
            if (denied) ...[
              const SizedBox(height: 8),
              Text(
                l10n.cameraPermissionBody,
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
            ).tagged('scanner.cancel'),
          ],
        ),
      ),
    );
  }
}
