import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../l10n/app_localizations.dart';

/// Wyłuskuje id szpuli z treści kodu QR bambuddy. Format produkcyjny to URL
/// `https://<host>/inventory?spool=24` (parametr `spool`), ale parser jest
/// celowo tolerancyjny — radzi sobie też z gołą liczbą, innymi nazwami
/// parametru oraz id w ścieżce (`/inventory/spools/24`). Zwraca null, gdy nic
/// sensownego nie da się odczytać. Top-level (czysta funkcja) — testowalne bez UI.
int? parseScannedSpoolId(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;

  // Goła liczba = id szpuli.
  final asInt = int.tryParse(s);
  if (asInt != null && asInt > 0) return asInt;

  final uri = Uri.tryParse(s);
  if (uri == null) return null;

  // Parametr query (produkcyjny `spool`, plus warianty na zapas).
  for (final key in const ['spool', 'spool_id', 'spoolId', 'id']) {
    final v = uri.queryParameters[key];
    final n = v == null ? null : int.tryParse(v.trim());
    if (n != null && n > 0) return n;
  }

  // Ostatni liczbowy segment ścieżki (np. `/inventory/spools/24`).
  for (final seg in uri.pathSegments.reversed) {
    final n = int.tryParse(seg.trim());
    if (n != null && n > 0) return n;
  }
  return null;
}

/// Pełnoekranowy skaner kodów QR szpul. Po pierwszym poprawnym odczycie zamyka
/// się, zwracając przez [Navigator.pop] id szpuli (`int`). Anuluj/wstecz →
/// zwraca null. Sam zarządza kontrolerem aparatu (start/stop z cyklem życia,
/// dispose). Uprawnienie do aparatu obsługuje [MobileScanner] (prośba runtime +
/// `errorBuilder` dla odmowy).
class SpoolScannerScreen extends StatefulWidget {
  const SpoolScannerScreen({super.key});

  @override
  State<SpoolScannerScreen> createState() => _SpoolScannerScreenState();
}

class _SpoolScannerScreenState extends State<SpoolScannerScreen>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );

  /// Strażnik przed wielokrotnym pop — kamera potrafi wystrzelić kilka odczytów
  /// zanim ekran zdąży się zamknąć.
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  /// Wstrzymuje strumień aparatu, gdy aplikacja schodzi w tło, i wznawia po
  /// powrocie — bez tego CameraX trzyma uchwyt mimo niewidocznego ekranu.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _controller.start();
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _controller.stop();
    }
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
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(l10n.inventoryScanTitle),
        actions: [
          IconButton(
            onPressed: () => _controller.toggleTorch(),
            icon: ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (context, state, _) => Icon(
                state.torchState == TorchState.on
                    ? Icons.flash_on
                    : Icons.flash_off,
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
          // Ramka celownika + podpowiedź.
          IgnorePointer(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    l10n.inventoryScanHint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      shadows: [Shadow(blurRadius: 8, color: Colors.black)],
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

/// Komunikat zastępczy, gdy aparat jest niedostępny — najczęściej odmowa
/// uprawnienia. Pokazujemy czytelny powód i przycisk powrotu.
class _ScannerError extends StatelessWidget {
  const _ScannerError({required this.error, required this.l10n});

  final MobileScannerException error;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
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
              color: Colors.white70,
              size: 56,
            ),
            const SizedBox(height: 16),
            Text(
              denied
                  ? l10n.inventoryScanPermissionTitle
                  : l10n.inventoryScanTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            if (denied) ...[
              const SizedBox(height: 8),
              Text(
                l10n.inventoryScanPermissionBody,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text(MaterialLocalizations.of(context).closeButtonLabel),
            ),
          ],
        ),
      ),
    );
  }
}
