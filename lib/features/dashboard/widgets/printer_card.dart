import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_exceptions.dart';
import '../../../core/models/inventory.dart';
import '../../../core/models/printer_status.dart';
import '../../../core/models/smart_plug.dart';
import '../../../core/notifications/hms_catalog.dart';
import '../../../data/printers_repository.dart';
import '../../../data/smart_plugs_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/error_messages.dart';
import '../../../providers.dart';
import '../../camera/camera_view.dart';
import '../../inventory/inventory_providers.dart';
import '../../inventory/inventory_screen.dart'
    show SpoolSwatch, assignmentSlotLabel;
import '../../maintenance/maintenance_providers.dart';
import '../controls_providers.dart';
import '../firmware_providers.dart';
import '../smart_plugs_providers.dart';
import 'ams_history_sheet.dart';

part 'printer_card_details.dart';
part 'printer_card_panels.dart';
part 'printer_card_controls.dart';
part 'printer_card_temps.dart';

class PrinterCard extends StatefulWidget {
  const PrinterCard({super.key, required this.item});

  final PrinterWithStatus item;

  @override
  State<PrinterCard> createState() => _PrinterCardState();
}

class _PrinterCardState extends State<PrinterCard> {
  /// Details section expansion state (AMS, spool, connectivity) — kept locally
  /// to survive polling/WS refreshes (card is keyed by printer id).
  bool _expanded = false;

  /// Whether the card displays as OFFLINE. This is debounced via [_offlineGrace]
  /// to prevent flashing when `connected` flickers (e.g., REST still reports online
  /// while WS doesn't—typical right after power-switching). Immediate return to online.
  late bool _offline;
  Timer? _offlineGrace;

  /// Filter HMS errors to displayable ones: omit internal/untranslatable entries.
  List<HmsError> _displayableHmsErrors(PrinterStatus? status) => [
    for (final e in status?.hmsErrors ?? const <HmsError>[])
      if (hmsIsDisplayable(e, description: HmsCatalog.instance.describe(e))) e,
  ];

  /// Grace period before collapsing the card when offline is sustained; fresh
  /// `connected:true` within this window resets the timer (debounce flashing).
  static const _offlineGracePeriod = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    // Initial offline state (no grace period): card collapses immediately.
    _offline = !(widget.item.status?.connected ?? false);
  }

  @override
  void didUpdateWidget(PrinterCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final connected = widget.item.status?.connected ?? false;
    if (connected) {
      // Back/maintaining online: immediately expand and cancel timer.
      _offlineGrace?.cancel();
      _offlineGrace = null;
      if (_offline) setState(() => _offline = false);
    } else if (!_offline && _offlineGrace == null) {
      // Freshly disconnected — count down instead of collapsing immediately (debounce).
      _offlineGrace = Timer(_offlineGracePeriod, () {
        _offlineGrace = null;
        if (mounted) setState(() => _offline = true);
      });
    }
  }

  @override
  void dispose() {
    _offlineGrace?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final status = widget.item.status;
    final connected = status?.connected ?? false;

    // Printer unavailable (no status or disconnected): card collapses to header-only
    // with OFFLINE label. Don't show stale temperatures, controls, or details—they'd
    // be misleading on an inactive machine. Expansion state is preserved and returns
    // when the printer wakes. Use debounced [_offline], not raw `connected`, to avoid
    // flashing when the server momentarily flickers (see didUpdateWidget).
    if (_offline) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.print, color: theme.disabledColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.item.printer.name,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Smart plug remains controllable even when OFFLINE—the only way to
                  // remotely power on and wake the printer. Auto-hides if none assigned.
                  _SmartPlugButton(
                    printerId: widget.item.printer.id,
                    printing: false,
                  ),
                  const SizedBox(width: 4),
                  _StateChip(
                    label: l10n.statusOffline,
                    connected: false,
                    offline: true,
                  ),
                ],
              ),
              // Total print time is from the server (maintenance), so we know it
              // even when the card is collapsed—show it instead of blank space.
              _TotalPrintTimeLine(printerId: widget.item.printer.id),
              // No plate-clear here: the server's clear-plate endpoint rejects
              // an offline printer (400 "Printer not connected"), so the ack can
              // only be sent once it's back online.
            ],
          ),
        ),
      );
    }

    final printing = status?.isPrinting ?? false;
    final readings = _buildReadings(
      status?.temperatures,
      status?.airductIsHeating,
    );
    final hasDetails = status?.hasDetails ?? false;
    final hmsErrors = _displayableHmsErrors(status);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.print,
                  color: connected
                      ? theme.colorScheme.primary
                      : theme.disabledColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.item.printer.name,
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                      _FirmwareLine(printerId: widget.item.printer.id),
                      _TotalPrintTimeLine(printerId: widget.item.printer.id),
                    ],
                  ),
                ),
                // Camera view only when connected (offline won't stream anyway).
                if (connected)
                  IconButton(
                    tooltip: l10n.cameraTooltip,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.videocam_outlined),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CameraView(
                          printerId: widget.item.printer.id,
                          printerName: widget.item.printer.name,
                        ),
                      ),
                    ),
                  ),
                _SmartPlugButton(
                  printerId: widget.item.printer.id,
                  printing: printing,
                ),
                const SizedBox(width: 4),
                _StateChip(
                  label: status == null
                      ? l10n.statusUnavailable
                      : (status.state ??
                            (connected ? l10n.online : l10n.offline)),
                  connected: connected,
                  active: printing,
                ),
              ],
            ),
            if (status != null)
              _PlateClearBanner(
                printerId: widget.item.printer.id,
                status: status,
              ),
            if (hmsErrors.isNotEmpty) ...[
              const SizedBox(height: 10),
              _HmsErrorsPanel(errors: hmsErrors),
            ],
            if (printing) ...[
              const SizedBox(height: 10),
              _PrintPanel(status: status!),
            ],
            if (readings.isNotEmpty) ...[
              const SizedBox(height: 10),
              _TempGrid(readings: readings),
            ],
            if (status != null) ...[
              _ControlsActions(
                printerId: widget.item.printer.id,
                status: status,
              ),
              _ControlsRow(status: status),
            ],
            if (hasDetails) ...[
              const SizedBox(height: 10),
              _DetailsToggle(
                expanded: _expanded,
                onTap: () => setState(() => _expanded = !_expanded),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: _expanded
                    ? _DetailsPanel(status: status!)
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
