import 'dart:async';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/nfc/nfc_reader.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/qr_scanner_screen.dart';
import 'spool_nfc_scan.dart';

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

/// The spool scanner: the camera reads a QR code, and on a phone with NFC a
/// switch under the title reads the spool's tag instead (#71). Both end the same
/// way, popping the id of the spool for the caller to open.
///
/// The side used last is the one it opens on, kept on the device. A phone with
/// no NFC gets the camera screen exactly as it was, with no switch.
class SpoolScannerScreen extends ConsumerStatefulWidget {
  const SpoolScannerScreen({super.key});

  @override
  ConsumerState<SpoolScannerScreen> createState() => _SpoolScannerScreenState();
}

class _SpoolScannerScreenState extends ConsumerState<SpoolScannerScreen>
    with WidgetsBindingObserver {
  /// The side the user last chose; shown only where NFC is.
  late bool _nfc = ref.read(settingsRepositoryProvider).loadSpoolScanNfc();

  /// Null until the phone has answered, which is a moment.
  NfcStatus? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_askStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// NFC is switched on in the system settings, which this screen sends the user
  /// to: coming back is the moment to look again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_askStatus());
  }

  Future<void> _askStatus() async {
    final status = await ref.read(nfcReaderProvider).status();
    if (mounted && status != _status) setState(() => _status = status);
  }

  void _choose(bool nfc) {
    setState(() => _nfc = nfc);
    unawaited(ref.read(settingsRepositoryProvider).saveSpoolScanNfc(nfc));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = _status;
    final hasNfc = status == NfcStatus.ready || status == NfcStatus.disabled;

    // Last time was NFC and the phone has not said yet whether it has any:
    // starting the camera for that moment would only be undone.
    if (status == null && _nfc) {
      return const Scaffold(backgroundColor: Colors.black);
    }
    final switcher = hasNfc ? _ModeSwitch(nfc: _nfc, onChanged: _choose) : null;
    if (switcher != null && _nfc) {
      return SpoolNfcScan(
        status: status!,
        header: switcher,
        onUnavailable: () => unawaited(_askStatus()),
      );
    }
    return QrScannerScreen<int>(
      title: hasNfc ? l10n.spoolScanTitle : l10n.inventoryScanTitle,
      hint: l10n.inventoryScanHint,
      extract: parseScannedSpoolId,
      header: switcher,
    );
  }
}

/// Camera | NFC, on the scanner's fixed dark ground whatever the app's theme.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.nfc, required this.onChanged});

  final bool nfc;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Theme(
      data: buildDashThemeData(Brightness.dark, brand: bambuddyBrand),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DashSpace.gutter,
          vertical: DashSpace.sm,
        ),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: false,
                label: Text(l10n.spoolScanModeCamera),
              ),
              ButtonSegment(value: true, label: Text(l10n.spoolScanModeNfc)),
            ],
            selected: {nfc},
            onSelectionChanged: (s) => onChanged(s.first),
          ).tagged('spool_scan.mode'),
        ),
      ),
    );
  }
}
