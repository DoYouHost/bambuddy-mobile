import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/diagnostics/log_tag.dart';
import '../../../core/api/action_outcome.dart';
import '../../../core/api/api_exceptions.dart';
import '../../../core/format/datetime_format.dart';
import '../../../core/format/duration_format.dart';
import '../../../core/models/inventory.dart';
import '../../../core/models/printer_capabilities.dart';
import '../../../core/models/printer_status.dart';
import '../../../core/models/smart_plug.dart';
import '../../../core/notifications/hms_actions.dart';
import '../../../core/notifications/hms_catalog.dart';
import '../../../core/settings/server_profile.dart';
import '../../../core/theme/dash_text.dart';
import '../../../data/inventory_source.dart';
import '../../../data/printer_commands_repository.dart';
import '../../../data/printers_repository.dart';
import '../../../data/smart_plugs_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/error_messages.dart';
import '../../../providers.dart';
import '../../camera/camera_view.dart';
import '../../common/api_failure_snack.dart';
import '../../common/camera_token_image_recovery.dart';
import '../../common/confirm_dialog.dart';
import '../../common/dash_input.dart';
import '../../common/dash_progress.dart';
import '../../common/dash_search_field.dart';
import '../../common/dash_sheet.dart';
import '../../common/dash_snack.dart';
import '../../common/dashed_line.dart';
import '../../common/plate_clear.dart';
import '../../files/printer_file_manager_screen.dart';
import 'print_meta_row.dart';
import '../../inventory/inventory_providers.dart';
import '../../inventory/inventory_screen.dart'
    show SpoolSwatch, assignmentSlotLabel, openSpoolInInventory;
import '../../inventory/spool_scanner_screen.dart';
import '../../maintenance/maintenance_providers.dart';
import '../controls_providers.dart';
import '../firmware_providers.dart';
import '../ws_providers.dart';
import '../skip_objects_screen.dart';
import '../smart_plugs_providers.dart';
import '../../../core/theme/dash_theme.dart';
import 'ams_slot_config_sheet.dart';
import 'ams_history_sheet.dart';
import 'heater_history_sheet.dart';
import 'temp_gauge.dart';

part 'printer_card_details.dart';
part 'printer_card_panels.dart';
part 'printer_card_controls.dart';
part 'printer_card_temps.dart';
part 'printer_card_movement.dart';

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

  /// Whether a frame saying the printer is reachable arrived within the last
  /// [_offlineGracePeriod]. Only a disconnect that follows such an observation
  /// gets the grace period — a flicker is by definition a dense run of frames,
  /// so it always qualifies.
  ///
  /// Without this the debounce fired on evidence the card no longer had: in the
  /// background the socket is closed and polling stopped, so the first frame
  /// after a resume is compared against a `connected:true` that can be hours
  /// old, and a printer switched off last night was granted a fresh 15 seconds
  /// of the full layout on every open.
  bool _connectedRecently = false;
  Timer? _connectedRecency;

  /// Filter HMS errors to displayable ones: omit internal/untranslatable entries.
  List<HmsError> _displayableHmsErrors(PrinterStatus? status) => [
    for (final e in status?.hmsErrors ?? const <HmsError>[])
      if (hmsIsDisplayable(e, description: HmsCatalog.instance.describe(e))) e,
  ];

  /// Grace period before collapsing the card when offline is sustained; fresh
  /// `connected:true` within this window resets the timer (debounce flashing).
  /// It doubles as the window in which a reachable frame still counts as an
  /// observation — see [_connectedRecently].
  static const _offlineGracePeriod = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    // Initial offline state (no grace period): card collapses immediately.
    _offline = !(widget.item.status?.connected ?? false);
    if (!_offline) _observedConnected();
  }

  @override
  void didUpdateWidget(PrinterCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final connected = widget.item.status?.connected ?? false;
    // Only a status that actually changed is an observation. Plain rebuilds —
    // the dashboard re-filtering, the app coming back to the front — re-render
    // the value the card already holds, and counting those would keep the
    // observation alive for as long as the card is on screen.
    final observed = widget.item.status != oldWidget.item.status;
    if (connected) {
      if (observed) _observedConnected();
      // Back/maintaining online: immediately expand and cancel timer.
      _offlineGrace?.cancel();
      _offlineGrace = null;
      if (_offline) setState(() => _offline = false);
    } else if (!_offline && _offlineGrace == null) {
      if (!_connectedRecently) {
        // Nothing recent to contradict this frame — it is not a flicker, it is
        // the answer to a question the card had stopped asking.
        setState(() => _offline = true);
      } else {
        // Freshly disconnected — count down instead of collapsing immediately (debounce).
        _offlineGrace = Timer(_offlineGracePeriod, () {
          _offlineGrace = null;
          if (mounted) setState(() => _offline = true);
        });
      }
    }
  }

  /// Record a reachable frame and let the record expire with the grace period
  /// it guards, so the two can never drift apart.
  void _observedConnected() {
    _connectedRecently = true;
    _connectedRecency?.cancel();
    _connectedRecency = Timer(
      _offlineGracePeriod,
      () => _connectedRecently = false,
    );
  }

  @override
  void dispose() {
    _offlineGrace?.cancel();
    _connectedRecency?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final status = widget.item.status;
    final connected = status?.connected ?? false;
    final printerId = widget.item.printer.id;
    final name = widget.item.printer.name;

    // Printer unavailable (no status or disconnected): card collapses to
    // header-only with an OFFLINE chip. Don't show stale temperatures/controls —
    // they'd mislead on an inactive machine. Expansion state is preserved and
    // returns when it wakes. Uses debounced [_offline] (see didUpdateWidget).
    if (_offline) {
      return _CardShell(
        tokens: t,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _IconSquare(tokens: t, offline: true),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _NameText(name: name, tokens: t),
                      _TotalPrintTimeLine(printerId: printerId),
                    ],
                  ),
                ),
                // Smart plug stays controllable even when OFFLINE — the only way to
                // remotely power the printer back on. Auto-hides if none assigned.
                _SmartPlugButton(printerId: printerId, printing: false),
                const SizedBox(width: 8),
                _StateChip(label: l10n.statusOffline, offline: true),
              ],
            ),
            // The one thing that survives the collapse besides the plug, and for
            // the same reason: releasing the plate-clear gate is the only way to
            // let the queue wake this printer for its next job, and it is
            // bambuddy's own flag rather than anything on the machine.
            if (status != null)
              _PlateClearBanner(printerId: printerId, status: status),
          ],
        ),
      );
    }

    final printing = status?.isPrinting ?? false;
    final readings = _buildReadings(
      status?.temperatures,
      status?.airductIsHeating,
    );
    final hasDetails = status?.hasDetails ?? false;
    final hasFans = status != null &&
        (status.coolingFanSpeed != null ||
            status.leftAuxFanSpeed != null ||
            status.bigFan1Speed != null ||
            status.chamberFanAvailable);
    // Manual movement (jog/home) is offered while idle — it must not run during
    // a print (raw G-code would corrupt it).
    final canMove = status != null && connected && !printing;
    // The "Details" toggle now governs fans, the speed selector, movement and
    // the AMS/spool/connectivity section — so it appears whenever any of those
    // has something to show (speed is only actionable while printing).
    final showDetailsToggle =
        status != null && (hasDetails || hasFans || printing || canMove);
    final hmsErrors = _displayableHmsErrors(status);

    return _CardShell(
      tokens: t,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: icon + name + firmware/hours (left), status pill + action
          // icons (right).
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _IconSquare(tokens: t, offline: !connected),
                        const SizedBox(width: 9),
                        Flexible(child: _NameText(name: name, tokens: t)),
                      ],
                    ),
                    _FirmwareLine(printerId: printerId),
                    _TotalPrintTimeLine(printerId: printerId),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _StateChip(
                    label: status == null
                        ? l10n.statusUnavailable
                        : (status.state ??
                            (connected ? l10n.online : l10n.offline)),
                    offline: !connected,
                  ),
                  if (connected) ...[
                    const SizedBox(height: 10),
                    _HeaderActions(
                      printerId: printerId,
                      printerName: name,
                      printing: printing,
                    ),
                  ],
                ],
              ),
            ],
          ),
          if (status != null)
            _PlateClearBanner(printerId: printerId, status: status),
          if (hmsErrors.isNotEmpty) ...[
            const SizedBox(height: 10),
            _HmsErrorsPanel(
              printerId: printerId,
              printerName: name,
              errors: hmsErrors,
            ),
          ],
          if (printing) ...[
            const SizedBox(height: 12),
            _PrintPanel(status: status!),
          ],
          if (readings.isNotEmpty) ...[
            const SizedBox(height: 14),
            _TempGrid(
              readings: readings,
              printerId: printerId,
              model: status?.model,
              activeExtruder: status?.activeExtruder,
              printing: printing,
            ),
          ],
          if (status != null) ...[
            // Primary lifecycle controls (pause/resume/stop) stay visible while
            // printing; speed lives under "Details".
            _ControlsActions(printerId: printerId, status: status),
            // Chamber-light switch row (design accent panel).
            _LightSwitchRow(printerId: printerId, status: status),
          ],
          if (showDetailsToggle) ...[
            _DetailsToggle(
              id: 'printer.details_toggle',
              expanded: _expanded,
              onTap: () => setState(() => _expanded = !_expanded),
            ),
            // Collapsible: speed selector, fans and AMS/spool/connectivity — all
            // governed by the toggle.
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (printing)
                          _SpeedControlTile(
                            printerId: printerId,
                            status: status,
                          ),
                        if (canMove) _MovementTile(printerId: printerId),
                        if (hasFans)
                          _FansGrid(status: status, printerId: printerId),
                        if (hasDetails) _DetailsPanel(status: status),
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ],
      ),
    );
  }
}

/// Outer card container in the modernized visual language: translucent gradient
/// fill, hairline border, generous radius. Holds the whole printer card.
class _CardShell extends StatelessWidget {
  const _CardShell({required this.tokens, required this.child});

  final DashTokens tokens;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Names the card as a whole. Anything inside it without a tag of its own is
    // still reported as "somewhere on a printer card", which beats a bare role.
    return logTag(
      'dashboard.printer_card',
      Container(
        margin: const EdgeInsets.fromLTRB(16, 7, 16, 7),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: tokens.cardGradient,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: tokens.cardBorder),
        ),
        child: child,
      ),
    );
  }
}

/// Rounded green-tinted square holding the printer glyph (design header icon).
class _IconSquare extends StatelessWidget {
  const _IconSquare({required this.tokens, this.offline = false});

  final DashTokens tokens;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final color = offline
        ? tokens.textTertiary
        : tokens.accentGreenInk;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: (offline ? tokens.textTertiary : tokens.accentGreen)
            .withValues(alpha: offline ? 0.10 : 0.14),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(Icons.print_outlined, size: 18, color: color),
    );
  }
}

/// Printer name in the header — bold, tight tracking, never wraps (a wrapping
/// name would collide with the firmware line below, per the design note).
class _NameText extends StatelessWidget {
  const _NameText({required this.name, required this.tokens});

  final String name;
  final DashTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Text(
      name,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: tokens.display.copyWith(letterSpacing: -0.3),
    );
  }
}

/// Header action icons (file manager, camera, smart plug) as compact ghost
/// buttons. File/camera hit the printer directly, so only shown when connected.
class _HeaderActions extends StatelessWidget {
  const _HeaderActions({
    required this.printerId,
    required this.printerName,
    required this.printing,
  });

  final int printerId;
  final String printerName;
  final bool printing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _HeaderIconButton(
          id: 'printer.files',
          tooltip: l10n.pfmTooltip,
          icon: Icons.folder_outlined,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PrinterFileManagerScreen(
                printerId: printerId,
                printerName: printerName,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _HeaderIconButton(
          id: 'printer.camera',
          tooltip: l10n.cameraTooltip,
          icon: Icons.videocam_outlined,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CameraView(
                printerId: printerId,
                printerName: printerName,
              ),
            ),
          ),
        ),
        // Skip objects only makes sense during an active print.
        if (printing) ...[
          const SizedBox(width: 8),
          _HeaderIconButton(
            id: 'printer.skip_objects',
            tooltip: l10n.skipObjectsTitle,
            icon: Icons.layers_clear_outlined,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SkipObjectsScreen(
                  printerId: printerId,
                  printerName: printerName,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(width: 8),
        _SmartPlugButton(printerId: printerId, printing: printing),
      ],
    );
  }
}
