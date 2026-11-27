import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:app_diagnostics/app_diagnostics.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';

/// Fixed dark tokens regardless of system theme: this screen is a full-screen
/// camera overlay (always black chrome + light text for contrast on the live
/// preview), so it doesn't follow light/dark system theme like other screens.
const kScanTokens = DashTokens.dark(bambuddyBrand);

/// Full-screen QR code scanner, reusable across features. [extract] turns a raw
/// barcode value into the result [T] to return via [Navigator.pop] (returning
/// null ignores that read and keeps scanning). Closes on the first successful
/// extract; cancel/back → returns null. The controller starts the camera, which
/// asks for the permission; a camera that does not start (refused or broken) is
/// shown by this screen from the controller's error, in the room the header
/// leaves, with nothing drawn over it.
class QrScannerScreen<T extends Object> extends StatefulWidget {
  const QrScannerScreen({
    super.key,
    required this.title,
    required this.hint,
    required this.extract,
    this.header,
  });

  /// App-bar title, and the heading of the failure message for any error that is
  /// not a refused permission (that one names itself).
  final String title;

  /// Instruction line under the viewfinder.
  final String hint;

  /// Parses a scanned barcode into the value to return, or null to keep scanning.
  final T? Function(String raw) extract;

  /// Shown under the app bar, over the preview: a caller that offers another
  /// way to scan puts its switch here.
  final Widget? header;

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

  /// The frame to hold the code in, and what to do. Taps pass through it.
  Widget _viewfinder(DashTokens t) => IgnorePointer(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          key: const ValueKey('scanner_frame'),
          width: DashSize.d240,
          height: DashSize.d240,
          decoration: BoxDecoration(
            border: Border.all(color: t.accentGreen, width: DashStroke.heavy),
            borderRadius: BorderRadius.circular(DashRadius.lg),
          ),
        ),
        const SizedBox(height: DashSpace.xl),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DashSpace.xxl),
          child: Text(
            widget.hint,
            textAlign: TextAlign.center,
            style: t.titleMd.copyWith(
              shadows: const [
                Shadow(blurRadius: DashBlur.md, color: Colors.black),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _torch(DashTokens t) => ValueListenableBuilder<MobileScannerState>(
    valueListenable: _controller,
    builder: (context, state, _) {
      // Nothing to light when the camera did not start.
      if (state.error != null) return const SizedBox.shrink();
      final on = state.torchState == TorchState.on;
      // Off until the camera runs, which the controller refuses a toggle before,
      // and for ever on a phone with no flash.
      final usable =
          state.isRunning && state.torchState != TorchState.unavailable;
      return IconButton(
        onPressed: usable ? () => _controller.toggleTorch() : null,
        tooltip: AppLocalizations.of(context).scannerTorch,
        isSelected: on,
        // The colour is the button's, not the icon's own: an icon that sets
        // its own would not dim when the button is off.
        style: IconButton.styleFrom(
          foregroundColor: on ? t.accentGreen : t.textPrimary,
          disabledForegroundColor: t.textSecondary,
        ),
        icon: Icon(on ? Icons.flash_on : Icons.flash_off),
      ).tagged('scanner.torch');
    },
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = kScanTokens;
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
            style: t.display.copyWith(letterSpacing: DashTracking.tight),
          ),
          // With a header the torch sits under it instead, so the bar is the
          // same on every side of the scanner and the header does not move.
          actions: [if (widget.header == null) _torch(t)],
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // The camera's failure is drawn by this screen, not by the preview, so
          // that it takes the room under the header and nothing is drawn over it.
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => const SizedBox.shrink(),
          ),
          // The body runs behind the bar, and the safe area of a body there
          // already starts below it: no bar height of our own on top. What the
          // header and the torch leave is the viewfinder's, which shrinks into
          // it, so nothing overlaps at a large text or in landscape.
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  if (widget.header case final header?) ...[
                    SizedBox(width: double.infinity, child: header),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: DashSpace.sm,
                        ),
                        child: _torch(t),
                      ),
                    ),
                  ],
                  Expanded(
                    child: ValueListenableBuilder<MobileScannerState>(
                      valueListenable: _controller,
                      builder: (context, state, _) {
                        final error = state.error;
                        // Not before the camera is up (a permission prompt may
                        // be open): a frame that flashed up and went would
                        // promise a camera that is not coming.
                        if (error == null && !state.isInitialized) {
                          return const SizedBox.shrink();
                        }
                        if (error != null) {
                          return _ScannerError(
                            error: error,
                            title: widget.title,
                            l10n: l10n,
                          );
                        }
                        return LayoutBuilder(
                          builder: (context, box) => FittedBox(
                            // Down only: a frame is 240 dp, not whatever is left.
                            fit: BoxFit.scaleDown,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: box.maxWidth,
                              ),
                              child: _viewfinder(t),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
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
    final t = kScanTokens;
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Center(
      // Scrolls: in landscape at a large text this is taller than the screen.
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DashSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              denied ? Icons.no_photography_outlined : Icons.error_outline,
              color: t.textSecondary,
              size: DashIcon.xxl,
            ),
            const SizedBox(height: DashSpace.lg),
            Text(
              denied ? l10n.cameraPermissionTitle : title,
              textAlign: TextAlign.center,
              style: t.titleLg,
            ),
            if (denied) ...[
              const SizedBox(height: DashSpace.sm),
              Text(
                l10n.cameraPermissionBody,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: DashTokens.fontUi,
                  color: t.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: DashSpace.xl),
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
