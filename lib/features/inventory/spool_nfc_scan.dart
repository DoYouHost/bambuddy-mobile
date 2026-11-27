import 'dart:async';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/inventory.dart';
import '../../core/nfc/nfc_reader.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../common/qr_scanner_screen.dart' show kScanTokens;
import 'inventory_providers.dart';

/// The NFC side of the spool scanner (#71): waits for a tag held to the back of
/// the phone and pops the id of the spool it is linked to, as the camera side
/// does for a QR code.
///
/// Matching is [InventoryState.spoolForTag], the server's own order. A tag no
/// spool carries keeps the screen waiting and says which tag it was, so it can
/// be linked in SpoolBuddy: this app does not write or link tags.
class SpoolNfcScan extends ConsumerStatefulWidget {
  const SpoolNfcScan({
    super.key,
    required this.status,
    required this.header,
    required this.onUnavailable,
  });

  /// [NfcStatus.ready] reads tags; [NfcStatus.disabled] says NFC is off.
  final NfcStatus status;

  /// The switch to the camera, under the app bar.
  final Widget header;

  /// NFC went off while reading: the owner asks for the status again.
  final VoidCallback onUnavailable;

  @override
  ConsumerState<SpoolNfcScan> createState() => _SpoolNfcScanState();
}

class _SpoolNfcScanState extends ConsumerState<SpoolNfcScan> {
  StreamSubscription<String>? _tags;

  /// The tag no spool was found for, until another is read.
  String? _unknownTag;

  /// Why the shelf could not be read, when that is why nothing matched.
  String? _loadError;

  /// A tag is being matched, which may include a reload of the shelf: one read
  /// meanwhile is ignored, and held to the phone again it is read as any other.
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    _syncReading();
  }

  @override
  void didUpdateWidget(SpoolNfcScan old) {
    super.didUpdateWidget(old);
    if (old.status != widget.status) _syncReading();
  }

  @override
  void dispose() {
    unawaited(_tags?.cancel());
    super.dispose();
  }

  /// Reads while NFC is on, and stops reading when it is not.
  void _syncReading() {
    if (widget.status == NfcStatus.ready) {
      _tags ??= ref
          .read(nfcReaderProvider)
          .tags()
          .listen(_onTag, onError: _onError);
    } else {
      unawaited(_tags?.cancel());
      _tags = null;
    }
  }

  void _onError(Object error, StackTrace stack) {
    if (error is PlatformException && error.code == 'nfc_unavailable') {
      widget.onUnavailable();
      return;
    }
    // Anything else is a bug in the app, and belongs in the report: the
    // framework's error hook is where the recorder listens.
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'spool NFC scan',
      ),
    );
  }

  Spool? _find(String uid) =>
      ref.read(inventoryProvider).value?.spoolForTag(tagUid: uid);

  Future<void> _onTag(String uid) async {
    if (_resolving) return;
    _resolving = true;
    try {
      var spool = _find(uid);
      if (spool == null) {
        // A tag linked in SpoolBuddy a moment ago is the normal case for an
        // unknown one, so the shelf is read again once before saying so. One
        // already loading is that read: it is waited for, not repeated.
        if (ref.read(inventoryProvider).isLoading) {
          await ref
              .read(inventoryProvider.future)
              .then<void>((_) {}, onError: (Object _) {});
        } else {
          await ref.read(inventoryProvider.notifier).refresh();
        }
        // Backed out meanwhile: the route is leaving but this state still is,
        // and a pop now would take the screen underneath with it.
        if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
        spool = _find(uid);
      }
      if (spool != null) {
        // Closing: a tag read during the exit transition is not for this screen.
        unawaited(_tags?.cancel());
        _tags = null;
        ScaffoldMessenger.of(context).snack(
          AppLocalizations.of(context).spoolScanOpening(spool.displayName),
        );
        Navigator.of(context).pop(spool.id);
        return;
      }
      final failure = ref.read(inventoryProvider).error;
      final l10n = AppLocalizations.of(context);
      if (failure != null && failure is! AppApiException) {
        // Not a refusal of the server but a bug, and nothing here to say about it.
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: failure,
            stack: ref.read(inventoryProvider).stackTrace,
            library: 'spool NFC scan',
          ),
        );
        return;
      }
      setState(() {
        _unknownTag = failure == null ? uid : null;
        _loadError = failure is AppApiException
            ? failure.localized(l10n)
            : null;
      });
    } finally {
      _resolving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = kScanTokens;
    // Held for as long as the screen is open, so the first tag finds the shelf
    // already loaded.
    ref.watch(inventoryProvider);

    final off = widget.status == NfcStatus.disabled;
    final unknown = _unknownTag;
    final (icon, title, help) = switch ((off, unknown, _loadError)) {
      (true, _, _) => (
        Icons.nfc,
        l10n.spoolScanNfcOff,
        l10n.spoolScanNfcOffHelp,
      ),
      (_, final tag?, _) => (
        Icons.nfc,
        l10n.spoolScanTagUnknown,
        l10n.spoolScanTagUnknownHelp(tag),
      ),
      (_, _, final error?) => (Icons.error_outline, error, null),
      _ => (Icons.nfc, l10n.spoolScanNfcHint, l10n.spoolScanNfcHelp),
    };
    final warn = off || unknown != null || _loadError != null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: loggedAppBar(
        AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: t.textPrimary,
          elevation: 0,
          title: Text(
            l10n.spoolScanTitle,
            style: t.display.copyWith(letterSpacing: DashTracking.tight),
          ),
        ),
      ),
      body: Column(
        children: [
          widget.header,
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(DashSpace.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: DashIcon.xxl,
                      color: warn ? t.accentOrange : t.accentGreen,
                    ),
                    const SizedBox(height: DashSpace.lg),
                    Text(title, textAlign: TextAlign.center, style: t.titleLg),
                    if (help != null) ...[
                      const SizedBox(height: DashSpace.sm),
                      Text(
                        help,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: DashTokens.fontUi,
                          color: t.textSecondary,
                        ),
                      ),
                    ],
                    if (off) ...[
                      const SizedBox(height: DashSpace.xl),
                      FilledButton(
                        style: dashPrimaryButtonStyle(t),
                        onPressed: () => unawaited(
                          ref.read(nfcReaderProvider).openSettings(),
                        ),
                        child: Text(l10n.spoolScanNfcOpenSettings),
                      ).tagged('spool_scan.nfc_settings'),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
