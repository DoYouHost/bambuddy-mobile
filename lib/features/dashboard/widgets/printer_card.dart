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
          if (hmsIsDisplayable(e, description: HmsCatalog.instance.describe(e)))
            e,
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
            ],
          ),
        ),
      );
    }

    final printing = status?.isPrinting ?? false;
    final readings =
        _buildReadings(status?.temperatures, status?.airductIsHeating);
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

/// Active HMS errors panel: red border, each error with readable description
/// (from Bambu catalog or fallback "level · module"), canonical code, and—
/// when the full code can be composed—link to Bambu wiki.
class _HmsErrorsPanel extends StatelessWidget {
  const _HmsErrorsPanel({required this.errors});

  final List<HmsError> errors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.error.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 18, color: scheme.error),
              const SizedBox(width: 6),
              Text(
                l10n.hmsErrorsHeader,
                style: theme.textTheme.labelLarge?.copyWith(color: scheme.error),
              ),
            ],
          ),
          for (final e in errors) _HmsErrorRow(error: e),
        ],
      ),
    );
  }
}

class _HmsErrorRow extends StatelessWidget {
  const _HmsErrorRow({required this.error});

  final HmsError error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final label = hmsLabel(
      error,
      description: HmsCatalog.instance.describe(error),
      l10n: l10n,
    );
    final url = hmsWikiUrl(error);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Text(label, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 2),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  error.displayCode,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor),
                ),
              ),
              if (url != null)
                InkWell(
                  onTap: () => unawaited(launchUrl(
                    Uri.parse(url),
                    mode: LaunchMode.externalApplication,
                  )),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.hmsViewInWiki,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.primary),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.open_in_new,
                          size: 14, color: theme.colorScheme.primary),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Clickable "Details ▾" bar expanding AMS/connectivity section.
class _DetailsToggle extends StatelessWidget {
  const _DetailsToggle({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final scheme = theme.colorScheme;
    final color = scheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Ink(
        decoration: BoxDecoration(
          // Subtle contrast from card background — same tone as chips/tiles.
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              expanded ? l10n.detailsHide : l10n.detailsShow,
              style: theme.textTheme.labelLarge?.copyWith(color: color),
            ),
            const SizedBox(width: 4),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(Icons.expand_more, size: 20, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Expanded details section: AMS units with colored slots,
/// external spool, and connectivity metadata (model, Wi-Fi, door state).
class _DetailsPanel extends ConsumerWidget {
  const _DetailsPanel({required this.status});

  final PrinterStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final ams = status.ams ?? const [];
    final spools = status.externalSpools;
    // Actually loaded filament (on the active extruder)—highlight this one
    // regardless of list order.
    final active = status.activeTray;
    final dual = status.isDualExtruder;
    final activeExtruder = status.activeExtruder;
    // Spools from inventory assigned to this printer's slots—to show exact
    // remaining weight (printer only reports %, external spools report nothing).
    final assigned = ref.watch(assignedSpoolsProvider(status.id));

    final printerId = status.id;
    final printerName = status.name;

    final sections = <Widget>[
      for (var i = 0; i < ams.length; i++)
        _AmsUnitView(
          unit: ams[i],
          unitIndex: i,
          active: active,
          // On dual extruder, show which extruder feeds this unit.
          extruder: dual ? (status.amsExtruderMap?[ams[i].id]) : null,
          activeExtruder: activeExtruder,
          assigned: assigned,
          printerId: printerId,
          printerName: printerName,
        ),
      if (spools.isNotEmpty)
        _TraySection(
          title: l10n.externalSpool,
          trays: spools,
          active: active,
          // Spool→extruder mapping from id (inverse order: 254→left).
          extruderOf:
              dual ? (i) => status.extruderForExternal(spools[i].id) : (_) => null,
          activeExtruder: activeExtruder,
          // External spool feeding a given extruder (dual); on single extruder
          // treat as "left" (extruder 1)—see resolver.
          assignedOf: (i) =>
              assigned.forExtruder(dual ? status.extruderForExternal(spools[i].id) : 1),
          // tray_id for external assignment: extruder 1 (left)→0, 0 (right)→1;
          // single extruder→0. amsId=255 (inventory convention).
          trayIdOf: (i) {
            if (!dual) return 0;
            return status.extruderForExternal(spools[i].id) == 1 ? 0 : 1;
          },
          printerId: printerId,
          printerName: printerName,
        ),
    ];

    final info = _InfoRow(status: status);

    // Uniform 10px spacing above first section (from "Details" bar) and between
    // sections—consistent rhythm with the rest of the card.
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            sections[i],
          ],
          const SizedBox(height: 10),
          info,
        ],
      ),
    );
  }
}

/// One AMS unit: header (number + extruder + humidity + temperature) and slots.
/// [active] is the actually loaded tray instance (from model)—compared by identity,
/// so exactly one is highlighted.
class _AmsUnitView extends StatelessWidget {
  const _AmsUnitView({
    required this.unit,
    required this.unitIndex,
    required this.active,
    required this.extruder,
    required this.activeExtruder,
    required this.assigned,
    required this.printerId,
    required this.printerName,
  });

  final AmsUnit unit;
  final int unitIndex;
  final AmsTray? active;
  final int? extruder;
  final int? activeExtruder;
  final AssignedSpools assigned;
  final int printerId;
  final String? printerName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final scheme = theme.colorScheme;
    final color = scheme.onSurfaceVariant;
    final trays = unit.trays ?? const [];

    // Distinguish the AMS unit as a separate "card": darker background than slot
    // chips (surfaceContainerHigh), so slots visually pop above the unit block,
    // and the AMS reads as a cohesive group distinct from external spools.
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.dns_outlined, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                l10n.amsUnit(unitIndex + 1),
                style: theme.textTheme.labelLarge,
              ),
              if (extruder != null) ...[
                const SizedBox(width: 6),
                _ExtruderBadge(
                  extruder: extruder!,
                  active: extruder == activeExtruder,
                ),
              ],
              const Spacer(),
              if (unit.humidity != null)
                _MetaItem(
                  icon: Icons.water_drop_outlined,
                  text: '${unit.humidity}%',
                ),
              if (unit.humidity != null && unit.temp != null)
                const SizedBox(width: 12),
              if (unit.temp != null)
                _MetaItem(
                  icon: Icons.thermostat,
                  text: '${unit.temp!.toStringAsFixed(0)}°',
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in trays)
                _TrayChip(
                  tray: t,
                  active: identical(t, active),
                  assignedSpool:
                      assigned.forAmsSlot(unit.id ?? unitIndex, t.id ?? 0),
                  slot: _SlotRef(
                    printerId: printerId,
                    printerName: printerName,
                    amsId: unit.id ?? unitIndex,
                    trayId: t.id ?? 0,
                    label:
                        '${l10n.amsUnit(unitIndex + 1)} · ${(t.id ?? 0) + 1}',
                  ),
                ),
            ],
          ),
          if (trays.isEmpty)
            Text('—',
                style: theme.textTheme.bodySmall?.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// Tray section with title (e.g., external spool). [extruderOf] maps index to
/// extruder (on dual), [active] is the actually loaded tray.
class _TraySection extends StatelessWidget {
  const _TraySection({
    required this.title,
    required this.trays,
    required this.active,
    required this.extruderOf,
    required this.activeExtruder,
    required this.assignedOf,
    required this.trayIdOf,
    required this.printerId,
    required this.printerName,
  });

  final String title;
  final List<AmsTray> trays;
  final AmsTray? active;
  final int? Function(int index) extruderOf;
  final int? activeExtruder;
  final Spool? Function(int index) assignedOf;
  final int Function(int index) trayIdOf;
  final int printerId;
  final String? printerName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < trays.length; i++)
              _TrayChip(
                tray: trays[i],
                active: identical(trays[i], active),
                extruder: extruderOf(i),
                activeExtruder: activeExtruder,
                // External spool: printer doesn't measure fill (no RFID like genuine
                // Bambu filament in AMS)—don't show %.
                allowRemain: false,
                assignedSpool: assignedOf(i),
                slot: _SlotRef(
                  printerId: printerId,
                  printerName: printerName,
                  amsId: 255,
                  trayId: trayIdOf(i),
                  label: switch (extruderOf(i)) {
                    1 => l10n.extruderLeft,
                    0 => l10n.extruderRight,
                    _ => title,
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Single slot chip: optional extruder badge + color dot + material + qty.
/// Active (loaded) tray gets a border.
class _TrayChip extends StatelessWidget {
  const _TrayChip({
    required this.tray,
    required this.active,
    this.extruder,
    this.activeExtruder,
    this.allowRemain = true,
    this.assignedSpool,
    this.slot,
  });

  final AmsTray tray;
  final bool active;
  final int? extruder;
  final int? activeExtruder;

  /// Whether to show fill % at all (AMS only—external spool has no reliable measurement).
  final bool allowRemain;

  /// Spool from inventory assigned to this slot—gives exact remaining weight in grams
  /// (supplements/replaces the printer's rough %). Null = none assigned.
  final Spool? assignedSpool;

  /// Slot identification (printer/AMS/tray)—when provided, tapping the chip opens
  /// the assignment sheet for THIS slot. Null → chip not tappable.
  final _SlotRef? slot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final empty = tray.isEmpty;
    final dotColor = empty ? null : _parseTrayColor(tray.trayColor);

    final label = empty
        ? l10n.traySlotEmpty
        : (tray.materialLabel ?? l10n.traySlotEmpty);
    final remain = tray.remain;
    final showRemain = allowRemain && !empty && remain != null && remain >= 0;
    // Exact grams from assigned spool (only for occupied slots).
    final spool = empty ? null : assignedSpool;
    final grams = spool == null
        ? null
        : l10n.inventoryUsageWeight(spool.remainingWeight.toStringAsFixed(0));

    final text = [
      label,
      if (showRemain) '$remain%',
      ?grams,
    ].join(' · ');

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: active
            ? Border.all(color: scheme.primary, width: 1.5)
            : Border.all(color: Colors.transparent, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (extruder != null) ...[
            _ExtruderBadge(
              extruder: extruder!,
              active: extruder == activeExtruder,
            ),
            const SizedBox(width: 6),
          ],
          _ColorDot(color: dotColor),
          const SizedBox(width: 6),
          Text(
            text,
            style: theme.textTheme.labelMedium?.copyWith(
              color: empty ? scheme.onSurfaceVariant : scheme.onSurface,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );

    final slot = this.slot;
    final tappable = slot == null
        ? chip
        : InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => _AssignSlotSheet(slot: slot),
            ),
            child: chip,
          );

    // Assigned spool name in tooltip (chip shows material + grams only).
    return spool == null
        ? tappable
        : Tooltip(message: spool.displayName, child: tappable);
  }
}

/// Physical slot identification for spool assignment from chip.
class _SlotRef {
  const _SlotRef({
    required this.printerId,
    required this.printerName,
    required this.amsId,
    required this.trayId,
    required this.label,
  });

  final int printerId;
  final String? printerName;
  final int amsId;
  final int trayId;

  /// Readable slot label (e.g., "AMS 1 · 2" or "Left extruder").
  final String label;
}

/// "Assign spool to this slot" sheet opened from AMS/spool chip. Slot is known
/// from chip context, so user picks ONLY the spool. Shows current assignment
/// (with unassign option) and list of active spools from inventory.
class _AssignSlotSheet extends ConsumerWidget {
  const _AssignSlotSheet({required this.slot});

  final _SlotRef slot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final inv = ref.watch(inventoryProvider).valueOrNull;
    final spools = inv?.spools ?? const <Spool>[];

    // Spool currently assigned to exactly this slot (if any).
    Spool? current;
    for (final s in spools) {
      final a = inv?.assignmentFor(s.id);
      if (a != null &&
          a.printerId == slot.printerId &&
          a.amsId == slot.amsId &&
          a.trayId == slot.trayId) {
        current = s;
        break;
      }
    }

    // Available: active spools (no archived), excluding current assignment.
    // Sort: unassigned spools first, then by remaining qty (use up scraps first).
    bool assignedElsewhere(Spool s) => inv?.assignmentFor(s.id) != null;
    final options = [
      for (final s in spools)
        if (!s.isArchived && s.id != current?.id) s,
    ]..sort((a, b) {
        final ga = assignedElsewhere(a) ? 1 : 0;
        final gb = assignedElsewhere(b) ? 1 : 0;
        if (ga != gb) return ga - gb;
        return a.remainingWeight.compareTo(b.remainingWeight);
      });

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(l10n.inventoryAssignTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            [?slot.printerName, slot.label].join(' · '),
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),

          if (current != null) ...[
            Text(l10n.inventoryAssignCurrent, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: SpoolSwatch(rgba: current.rgba),
              title: Text(current.displayName),
              subtitle: current.remainingFraction != null
                  ? Text(l10n.inventoryRemaining(
                      current.remainingWeight.toStringAsFixed(0)))
                  : null,
              trailing: TextButton.icon(
                onPressed: () => _unassign(context, ref, l10n),
                icon: const Icon(Icons.link_off, size: 18),
                label: Text(l10n.inventoryUnassign),
              ),
            ),
            const Divider(height: 24),
          ],

          Text(l10n.inventoryAssignPick, style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          if (options.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(l10n.inventoryEmpty,
                  style: theme.textTheme.bodyMedium),
            )
          else
            for (final s in options)
              Builder(builder: (context) {
                // Where spool currently sits (if in another slot)—will be moved
                // from there upon selection (after confirmation).
                final from = inv?.assignmentFor(s.id);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: SpoolSwatch(rgba: s.rgba),
                  title: Text(s.displayName),
                  subtitle: Text([
                    if (s.remainingFraction != null)
                      l10n.inventoryRemaining(
                          s.remainingWeight.toStringAsFixed(0)),
                    '#${s.id}',
                    if (from != null)
                      [?from.printerName, assignmentSlotLabel(l10n, from)]
                          .join(' '),
                  ].join(' · ')),
                  trailing: from != null
                      ? const Icon(Icons.swap_horiz, size: 20)
                      : null,
                  onTap: () => _assign(context, ref, l10n, s, from: from),
                );
              }),
        ],
      ),
    );
  }

  Future<void> _assign(BuildContext context, WidgetRef ref,
      AppLocalizations l10n, Spool spool,
      {SpoolAssignment? from}) async {
    final messenger = ScaffoldMessenger.of(context);

    // Spool already in another slot → confirm move (unassign from there).
    if (from != null) {
      final fromLabel =
          [?from.printerName, assignmentSlotLabel(l10n, from)].join(' · ');
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.inventoryReassignTitle),
          content: Text(l10n.inventoryReassignMessage(fromLabel)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.inventoryReassignAction),
            ),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
    }

    Navigator.of(context).pop();
    try {
      await ref.read(inventoryProvider.notifier).assignSpool(
            SpoolAssignmentDraft(
              spoolId: spool.id,
              printerId: slot.printerId,
              amsId: slot.amsId,
              trayId: slot.trayId,
            ),
            from: from,
          );
      messenger
          .showSnackBar(SnackBar(content: Text(l10n.inventorySpoolAssigned)));
    } on AppApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.localized(l10n))));
    } on Object {
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.inventoryActionFailed)));
    }
  }

  Future<void> _unassign(
      BuildContext context, WidgetRef ref, AppLocalizations l10n) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    try {
      await ref
          .read(inventoryProvider.notifier)
          .unassignSpool(slot.printerId, slot.amsId, slot.trayId);
      messenger
          .showSnackBar(SnackBar(content: Text(l10n.inventorySpoolUnassigned)));
    } on AppApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.localized(l10n))));
    } on Object {
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.inventoryActionFailed)));
    }
  }
}

/// Small extruder badge for dual-extruder machines: icon + side (L/R—left/right).
/// Mapping per contract: extruder 1 = left, 0 = right (verified live: AMS →
/// extruder 1 = left). Active extruder in accent color, others dimmed.
class _ExtruderBadge extends StatelessWidget {
  const _ExtruderBadge({required this.extruder, required this.active});

  final int extruder;
  final bool active;

  bool get _isLeft => extruder == 1;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final color = active ? scheme.primary : scheme.onSurfaceVariant;
    final short = _isLeft ? l10n.extruderLeftShort : l10n.extruderRightShort;
    return Tooltip(
      message: _isLeft ? l10n.extruderLeft : l10n.extruderRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.print_outlined, size: 13, color: color),
          const SizedBox(width: 2),
          Text(
            short,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Circle in filament color; empty/unknown slot → crossed-out outline.
class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (color == null) {
      return Icon(Icons.circle_outlined, size: 14, color: scheme.outline);
    }
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.outlineVariant, width: 0.5),
      ),
    );
  }
}

/// Connectivity metadata row: Wi-Fi signal, door state. Printer model intentionally
/// omitted—printer name in header suffices for identification.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.status});

  final PrinterStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final dbm = status.wifiSignal;
    final doorOpen = status.doorOpen;

    final items = <Widget>[
      if (dbm != null)
        _InfoChip(
          icon: _wifiIcon(dbm),
          text: '$dbm dBm',
          color: _wifiColor(scheme, dbm),
        ),
      if (doorOpen != null)
        _InfoChip(
          icon: doorOpen ? Icons.meeting_room : Icons.meeting_room_outlined,
          text: doorOpen ? l10n.doorOpen : l10n.doorClosed,
          // Open door highlighted in warning color; closed shown neutrally.
          color: doorOpen ? const Color(0xFFFFB300) : scheme.onSurfaceVariant,
        ),
    ];
    if (items.isEmpty) return const SizedBox.shrink();

    // Distributed across full width (like fan chips)—clear, readable fields instead of tiny gray text.
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: items[i]),
        ],
      ],
    );
  }

  /// Wi-Fi icon based on signal strength (dBm): closer to 0 is better.
  IconData _wifiIcon(int dbm) {
    if (dbm >= -55) return Icons.network_wifi;
    if (dbm >= -65) return Icons.network_wifi_3_bar;
    if (dbm >= -75) return Icons.network_wifi_2_bar;
    return Icons.network_wifi_1_bar;
  }

  /// Color based on signal quality: good → green, fair → amber, weak → error.
  Color _wifiColor(ColorScheme scheme, int dbm) {
    if (dbm >= -60) return const Color(0xFF66BB6A);
    if (dbm >= -72) return const Color(0xFFFFB300);
    return scheme.error;
  }
}

/// Readable metadata "pill": colored icon + text on container background,
/// stretched to equal width share within a row.
class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = color ?? scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Firmware version under printer name (visible without expanding details,
/// only when online). When update available—highlighted in tertiary color, bold,
/// with update icon and target version (`current → latest`); when current—neutral.
/// Tooltip explains state and carries release notes if server provides them.
/// Auto-hides when no firmware data. Update action will come in future (repo ready).
class _FirmwareLine extends ConsumerWidget {
  const _FirmwareLine({required this.printerId});

  final int printerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(printerFirmwareProvider(printerId));
    if (info == null || !info.hasVersion) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final update =
        info.updateAvailable && (info.latestVersion?.isNotEmpty ?? false);
    final color = update ? scheme.tertiary : scheme.onSurfaceVariant;
    final text = update
        ? '${info.currentVersion} → ${info.latestVersion}'
        : info.currentVersion!;
    final tooltip = update
        ? l10n.firmwareUpdateAvailable(info.latestVersion!)
        : l10n.firmwareUpToDate;
    final notes = info.releaseNotes?.trim();

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Tooltip(
        message: update && notes != null && notes.isNotEmpty
            ? '$tooltip\n\n$notes'
            : tooltip,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(update ? Icons.system_update : Icons.memory,
                size: 13, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: update ? FontWeight.w600 : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Total print time (hours, from maintenance review) under printer name.
/// Data is historical and independent of WS, so we show it even when offline.
/// Auto-hides when server provides no maintenance data.
class _TotalPrintTimeLine extends ConsumerWidget {
  const _TotalPrintTimeLine({required this.printerId});

  final int printerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hours = ref.watch(printerTotalPrintHoursProvider(printerId));
    if (hours == null || hours <= 0) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: 13, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              l10n.maintenanceTotalHours(hours.round()),
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Parses filament color from hex RRGGBBAA to [Color]; null if invalid.
Color? _parseTrayColor(String? hex) {
  if (hex == null || hex.length != 8) return null;
  final rgb = int.tryParse(hex.substring(0, 6), radix: 16);
  final a = int.tryParse(hex.substring(6, 8), radix: 16);
  if (rgb == null || a == null) return null;
  return Color((a << 24) | rgb);
}

/// Active print panel: name, progress bar with %, ETA, and layer count.
class _PrintPanel extends StatelessWidget {
  const _PrintPanel({required this.status});

  final PrinterStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final progress = status.progress;
    final name = status.currentPrint ?? status.gcodeFile;

    final remaining = status.remainingTime;
    final meta = <Widget>[
      if (remaining != null && remaining > 0)
        _MetaItem(
          icon: Icons.schedule,
          text: l10n.remaining(_durationText(l10n, remaining)),
        ),
      if (remaining != null && remaining > 0)
        _MetaItem(
          icon: Icons.flag_outlined,
          text: l10n.eta(_etaTime(remaining)),
        ),
      if (status.layerNum != null && status.totalLayers != null)
        _MetaItem(
          icon: Icons.layers_outlined,
          text: '${status.layerNum}/${status.totalLayers}',
        ),
    ];

    // Prep phase (heating, auto bed leveling): show stage name
    // and indeterminate bar instead of confusing 0%.
    final stage = status.stgCurName?.trim();
    final showStage = status.isPreparing && stage != null && stage.isNotEmpty;

    // Row 1: file name + (when preparing) stage name.
    final nameBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (name != null)
          Text(
            name,
            style: theme.textTheme.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        if (showStage) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.autorenew, size: 14, color: scheme.primary),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  stage,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.primary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ],
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: thumbnail + file name.
          Row(
            children: [
              // Thumbnail always during print; without cover (or in calibration
              // which has no cover)—placeholder instead of blank space.
              _CoverThumbnail(
                coverUrl: status.isCalibration ? null : status.coverUrl,
              ),
              const SizedBox(width: 12),
              Expanded(child: nameBlock),
            ],
          ),
          const SizedBox(height: 10),
          // Row 2: progress bar + rest—full width, from left edge.
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    // Prep phase → indeterminate bar (no 0%).
                    value: showStage
                        ? null
                        : (progress == null
                            ? null
                            : (progress / 100).clamp(0.0, 1.0)),
                    minHeight: 6,
                  ),
                ),
              ),
              if (progress != null && !showStage) ...[
                const SizedBox(width: 10),
                Text(
                  '${progress.toStringAsFixed(0)}%',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 14, runSpacing: 4, children: meta),
          ],
        ],
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(text, style: theme.textTheme.bodySmall?.copyWith(color: color)),
      ],
    );
  }
}

/// Cover thumbnail for current print. Fetches image from `cover_url`
/// with camera stream token (`?token=`). Placeholder instead of
/// error—never crashes the card.
///
/// M2: proactive token refresh and reactive invalidation on 401
/// (`ref.invalidate(cameraTokenProvider)`) will arrive with camera preview.
class _CoverThumbnail extends ConsumerWidget {
  const _CoverThumbnail({required this.coverUrl});

  /// `null`/empty → immediate placeholder (e.g., calibration with no cover).
  final String? coverUrl;

  static const _size = 64.0;

  /// Placeholder graphic (nozzle over table, rounded transparent corners)—
  /// shown instead of cover when preview missing or calibration running.
  static const _placeholderAsset = 'assets/icons/cover_placeholder.png';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget placeholder() => Image.asset(
          _placeholderAsset,
          key: const ValueKey('cover_placeholder'),
          width: _size,
          height: _size,
          fit: BoxFit.cover,
        );

    final url = coverUrl;
    if (url == null || url.isEmpty) return placeholder();

    final baseUrl = ref.watch(serverProfileProvider)?.baseUrl;
    if (baseUrl == null) return placeholder();

    return ref.watch(cameraTokenProvider).when(
          loading: placeholder,
          error: (_, _) => placeholder(),
          data: (token) => ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              '$baseUrl$url?token=$token',
              key: const ValueKey('cover_network'),
              width: _size,
              height: _size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => placeholder(),
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : placeholder(),
            ),
          ),
        );
  }
}

/// Grid of temperature tiles (2 per row), each with icon and pair
/// current value / target value.
class _TempGrid extends StatelessWidget {
  const _TempGrid({required this.readings});

  final List<_TempReading> readings;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        final tileWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final r in readings)
              SizedBox(width: tileWidth, child: _TempTile(reading: r)),
          ],
        );
      },
    );
  }
}

/// Interactive control bar (M4): pause/resume/stop (stop always behind confirmation),
/// chamber light, speed. Optimistic state + rollback held by [controlsProvider];
/// here: render, send action, show result snackbar. Hides when disconnected.
class _ControlsActions extends ConsumerWidget {
  const _ControlsActions({required this.printerId, required this.status});

  final int printerId;
  final PrinterStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final connected = status.connected ?? false;
    if (!connected) return const SizedBox.shrink();

    final forbidden = ref.watch(controlsProvider.select((s) => s.forbidden));
    if (forbidden) {
      // API key lacks `can_control_printer`—show clear reason instead of dead buttons.
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: [
            Icon(Icons.lock_outline,
                size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                l10n.ctrlForbidden,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }

    final pending =
        ref.watch(controlsProvider.select((s) => s.pendingFor(printerId)));
    final light = pending.light ?? status.chamberLight ?? false;
    final speedLevel = pending.speedLevel ?? status.speedLevel;

    final printing = status.isPrinting;
    final paused = status.isPaused;
    final activePrint = printing && !paused;

    final buttons = <Widget>[
      if (activePrint)
        _LifecycleButton(
          icon: Icons.pause,
          label: l10n.ctrlPause,
          busy: pending.isBusy(ControlAction.pause),
          onPressed: () => _run(context, ref, ControlAction.pause),
        ),
      if (paused)
        _LifecycleButton(
          icon: Icons.play_arrow,
          label: l10n.ctrlResume,
          busy: pending.isBusy(ControlAction.resume),
          onPressed: () => _run(context, ref, ControlAction.resume),
        ),
      if (printing)
        _LifecycleButton(
          icon: Icons.stop,
          label: l10n.ctrlStop,
          danger: true,
          busy: pending.isBusy(ControlAction.stop),
          onPressed: () => _confirmStop(context, ref),
        ),
      _LightToggle(
        on: light,
        busy: pending.isBusy(ControlAction.light),
        onPressed: () => _toggleLight(context, ref, on: !light),
      ),
      if (printing)
        _SpeedControl(
          level: speedLevel,
          busy: pending.isBusy(ControlAction.speed),
          onSelected: (mode) => _setSpeed(context, ref, mode),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: _ControlsGrid(buttons: buttons),
    );
  }

  Future<void> _run(
      BuildContext context, WidgetRef ref, ControlAction action) async {
    final notifier = ref.read(controlsProvider.notifier);
    final result = switch (action) {
      ControlAction.pause => await notifier.pause(printerId),
      ControlAction.resume => await notifier.resume(printerId),
      ControlAction.stop => await notifier.stop(printerId),
      _ => ControlResult.ok,
    };
    if (context.mounted) _showResult(context, result);
  }

  Future<void> _toggleLight(BuildContext context, WidgetRef ref,
      {required bool on}) async {
    final result =
        await ref.read(controlsProvider.notifier).setLight(printerId, on: on);
    if (context.mounted) _showResult(context, result);
  }

  Future<void> _setSpeed(
      BuildContext context, WidgetRef ref, int mode) async {
    final result =
        await ref.read(controlsProvider.notifier).setSpeed(printerId, mode);
    if (context.mounted) _showResult(context, result);
  }

  /// Stop always behind confirmation—deliverable requirement, not polish: easy to kill
  /// a multi-hour print with one tap.
  Future<void> _confirmStop(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.ctrlStopConfirmTitle),
        content: Text(l10n.ctrlStopConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.ctrlStop),
          ),
        ],
      ),
    );
    if ((confirmed ?? false) && context.mounted) {
      await _run(context, ref, ControlAction.stop);
    }
  }

  void _showResult(BuildContext context, ControlResult result) {
    final l10n = AppLocalizations.of(context);
    final msg = switch (result) {
      ControlResult.ok => null,
      ControlResult.forbidden => l10n.ctrlForbidden,
      ControlResult.error => l10n.ctrlFailed,
    };
    if (msg == null) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// Smart plug control for printer (M7)—square icon button in card header, inline
/// with printer name. Plug symbol shows state: `power` = on, `power_off` (crossed)
/// = off; power draw and state in tooltip. Tap toggles. Auto-hides if none assigned.
/// Key rules: **button grayed out during print** (no power changes to active machine)
/// and **every change (ON/OFF) needs confirmation** dialog. Optimistic state + rollback
/// held by [smartPlugsProvider].
class _SmartPlugButton extends ConsumerWidget {
  const _SmartPlugButton({required this.printerId, required this.printing});

  final int printerId;
  final bool printing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plug = ref.watch(
      smartPlugsProvider.select((s) => s.plugForPrinterCard(printerId)),
    );
    if (plug == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    final state = ref.watch(smartPlugsProvider);
    final status = state.statusFor(plug.id);
    final on = state.effectiveOn(plug) ?? false;
    final busy = state.isBusy(plug.id);
    final forbidden = state.forbidden;
    final reachable = status?.isReachable ?? true;
    final power = status?.powerW;

    // During print button is fully grayed out—don't change power on active machine.
    final canControl = !busy && !forbidden && reachable && !printing;

    // Tooltip carries state + power draw (button is just icon): unreachable→
    // "Unreachable"; on with measurement→"X W"; otherwise raw state On/Off.
    final tip = printing
        ? l10n.smartPlugCantPowerOff
        : !reachable
            ? l10n.smartPlugUnreachable
            : (on && power != null
                ? l10n.powerWatts(power.round())
                : (on ? l10n.smartPlugOn : l10n.smartPlugOff));

    final fg = !reachable
        ? scheme.error
        : (on ? scheme.primary : scheme.onSurfaceVariant);

    return IconButton(
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      onPressed: canControl ? () => _onToggle(context, ref, plug, !on) : null,
      icon: Icon(on ? Icons.power : Icons.power_off),
      style: IconButton.styleFrom(
        foregroundColor: fg,
        // Square (slightly rounded) with border—distinguishes power toggle from
        // round camera button next to it.
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(
          color: on ? scheme.primary : scheme.outlineVariant,
        ),
      ),
    );
  }

  Future<void> _onToggle(
    BuildContext context,
    WidgetRef ref,
    SmartPlug plug,
    bool want,
  ) async {
    final l10n = AppLocalizations.of(context);

    // Every power change needs confirmation—easy to kill the machine with one tap.
    // OFF (power cut) highlighted in error color; ON is neutral.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            want ? l10n.smartPlugOnConfirmTitle : l10n.smartPlugOffConfirmTitle),
        content: Text(
            want ? l10n.smartPlugOnConfirmBody : l10n.smartPlugOffConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: want
                ? null
                : FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                  ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(want ? l10n.smartPlugTurnOn : l10n.smartPlugTurnOff),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !context.mounted) return;

    final result = await ref
        .read(smartPlugsProvider.notifier)
        .control(plug.id, want ? SmartPlugAction.on : SmartPlugAction.off);
    if (!context.mounted) return;
    final msg = switch (result) {
      ControlResult.ok => null,
      ControlResult.forbidden => l10n.ctrlForbidden,
      ControlResult.error => l10n.ctrlFailed,
    };
    if (msg != null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}

const _btnSpinner = SizedBox(
  width: 16,
  height: 16,
  child: CircularProgressIndicator(strokeWidth: 2),
);

/// Arranges control buttons in 2-column grid, in [buttons] order (pause/resume,
/// stop, light, speed). Each cell stretches to equal width; solo button (e.g.,
/// light only when idle) takes full row width.
class _ControlsGrid extends StatelessWidget {
  const _ControlsGrid({required this.buttons});

  final List<Widget> buttons;

  @override
  Widget build(BuildContext context) {
    const gap = 8.0;
    final rows = <Widget>[];
    for (var i = 0; i < buttons.length; i += 2) {
      final end = i + 2 > buttons.length ? buttons.length : i + 2;
      final pair = buttons.sublist(i, end);
      rows.add(Row(
        children: [
          for (var j = 0; j < pair.length; j++) ...[
            if (j > 0) const SizedBox(width: gap),
            Expanded(child: pair[j]),
          ],
        ],
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: gap),
          rows[i],
        ],
      ],
    );
  }
}

/// Print lifecycle action button (pause/resume/stop). Shows spinner and locks when
/// busy; `danger` colors stop red.
class _LifecycleButton extends StatelessWidget {
  const _LifecycleButton({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = danger ? scheme.error : null;
    return OutlinedButton.icon(
      onPressed: busy ? null : onPressed,
      icon: busy ? _btnSpinner : Icon(icon, size: 18, color: fg),
      label: Text(label, style: fg == null ? null : TextStyle(color: fg)),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        side: danger
            ? BorderSide(color: scheme.error.withValues(alpha: 0.5))
            : null,
      ),
    );
  }
}

/// Chamber light toggle. Shows current (optimistic) state; yellow bulb = on.
class _LightToggle extends StatelessWidget {
  const _LightToggle({
    required this.on,
    required this.busy,
    required this.onPressed,
  });

  final bool on;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const amber = Color(0xFFFFC107);
    return OutlinedButton.icon(
      onPressed: busy ? null : onPressed,
      icon: busy
          ? _btnSpinner
          : Icon(on ? Icons.lightbulb : Icons.lightbulb_outline,
              size: 18, color: on ? amber : null),
      label: Text(on ? l10n.ctrlLightOn : l10n.ctrlLightOff),
      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
    );
  }
}

/// Print speed picker (1–4). Tap opens menu with four levels; current is checked.
/// Locked with spinner when busy.
class _SpeedControl extends StatelessWidget {
  const _SpeedControl({
    required this.level,
    required this.busy,
    required this.onSelected,
  });

  final int? level;
  final bool busy;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final label = _speedName(l10n, level) ?? l10n.ctrlSpeed;

    return PopupMenuButton<int>(
      enabled: !busy,
      tooltip: l10n.ctrlSpeed,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (var m = 1; m <= 4; m++)
          CheckedPopupMenuItem<int>(
            value: m,
            checked: level == m,
            child: Text(_speedName(l10n, m)!),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: scheme.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            busy
                ? _btnSpinner
                : Icon(Icons.speed, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(label, style: theme.textTheme.labelLarge),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down,
                size: 18, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

String? _speedName(AppLocalizations l10n, int? level) => switch (level) {
      1 => l10n.speedSilent,
      2 => l10n.speedStandard,
      3 => l10n.speedSport,
      4 => l10n.speedLudicrous,
      _ => null,
    };

/// Read-only chip bar for sensor state (fans, chamber air duct). Controllable
/// values (light, speed) in [_ControlsActions]. Renders only if server provides any value.
class _ControlsRow extends StatelessWidget {
  const _ControlsRow({required this.status});

  final PrinterStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fanColor = _fanColor(context);

    // `valueAlternatives` reserves width for widest possible value so chip
    // size doesn't change during polling (e.g., 53% → 100%).
    // Fans 0–100%, speed up to 166% (Ludicrous)→3 digits.
    final chips = <Widget>[
      if (status.coolingFanSpeed != null)
        _ControlChip(
          icon: Icons.air,
          label: l10n.ctrlFanPart,
          caption: l10n.ctrlFanPartShort,
          value: '${status.coolingFanSpeed}%',
          valueAlternatives: const ['100%'],
          color: fanColor(status.coolingFanSpeed!),
        ),
      if (status.bigFan1Speed != null)
        _ControlChip(
          icon: Icons.air,
          label: l10n.ctrlFanAux,
          caption: l10n.ctrlFanAuxShort,
          value: '${status.bigFan1Speed}%',
          valueAlternatives: const ['100%'],
          color: fanColor(status.bigFan1Speed!),
        ),
      if (status.bigFan2Speed != null)
        _ControlChip(
          icon: Icons.air,
          label: l10n.ctrlFanChamber,
          caption: l10n.ctrlFanChamberShort,
          value: '${status.bigFan2Speed}%',
          valueAlternatives: const ['100%'],
          color: fanColor(status.bigFan2Speed!),
        ),
      // Chamber air duct (heating/cooling) moved to chamber temp tile—
      // see _AirductBadge in _TempTile.
    ];

    if (chips.isEmpty) return const SizedBox.shrink();

    // Chips evenly distributed across card width—each in `Expanded`, so they
    // divide the row equally regardless of count.
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: chips[i]),
          ],
        ],
      ),
    );
  }

  // Fan: idle (0%)→dimmed, spinning→cool accent.
  Color Function(int) _fanColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return (speed) =>
        speed > 0 ? const Color(0xFF4FC3F7) : scheme.onSurfaceVariant;
  }
}

/// Single control chip: icon + short caption + value. [label] is full name in
/// tooltip; [caption] is visible shorthand (e.g., "Chamber") so icon alone needn't
/// explain which fan the reading is for.
class _ControlChip extends StatelessWidget {
  const _ControlChip({
    required this.icon,
    required this.label,
    required this.value,
    this.caption,
    this.valueAlternatives = const [],
    this.color,
  });

  final IconData icon;
  final String label;

  /// Visible shorthand next to icon (optional). When null—chip shows icon and
  /// value only (legacy behavior).
  final String? caption;

  final String value;

  /// All possible values this chip can display. Value slot reserves width for
  /// widest, so chip maintains constant size regardless of current value
  /// (e.g., "53%" vs "100%").
  final List<String> valueAlternatives;

  /// Icon/value accent color; null = neutral theme color.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = color ?? scheme.onSurfaceVariant;
    // Tabular figures: all digits same width—no jitter when swapping same-length
    // digits (e.g., 53% → 67%).
    final valueStyle = (theme.textTheme.labelMedium ?? const TextStyle())
        .copyWith(
      color: accent,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    // Slot width = widest possible value (measured, not guessed)→chip stays
    // constant size despite polling changes. Measurement respects text scaling.
    final scaler = MediaQuery.textScalerOf(context);
    final dir = Directionality.of(context);
    var slotWidth = 0.0;
    for (final v in [value, ...valueAlternatives]) {
      final tp = TextPainter(
        text: TextSpan(text: v, style: valueStyle),
        textDirection: dir,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      if (tp.width > slotWidth) slotWidth = tp.width;
    }

    return Tooltip(
      message: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: 6),
            if (caption != null) ...[
              Flexible(
                child: Text(
                  caption!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 6),
            ],
            SizedBox(
              width: slotWidth.ceilToDouble(),
              child: Text(value, style: valueStyle, maxLines: 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _TempTile extends StatelessWidget {
  const _TempTile({required this.reading});

  final _TempReading reading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final actual = reading.actual;
    final target = reading.target;

    final iconColor = _tempIconColor(scheme, actual, target);
    // Show target only if set (>0); 0 = heating off.
    final hasTarget = target != null && target > 0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Icon top-left + sensor label; for chamber, air duct indicator (heating/
          // cooling) on right instead of separate chip.
          Row(
            children: [
              Icon(reading.icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  reading.label(l10n),
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (reading.airductIsHeating != null)
                _AirductBadge(heating: reading.airductIsHeating!),
            ],
          ),
          const SizedBox(height: 8),
          // Current: large, vivid color, left-aligned. Target: smaller, semi-
          // transparent, right-aligned.
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                actual == null ? '—' : '${actual.toStringAsFixed(0)}°',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: iconColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (hasTarget) ...[
                const Spacer(),
                Text(
                  '${target.toStringAsFixed(0)}°',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: iconColor.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Chamber air duct indicator pinned to chamber temp tile: icon +
/// "Heating"/"Cooling". Replaces former separate chip to keep chamber info unified.
class _AirductBadge extends StatelessWidget {
  const _AirductBadge({required this.heating});

  final bool heating;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color =
        heating ? const Color(0xFFFF8A50) : const Color(0xFF4FC3F7);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          heating ? Icons.local_fire_department : Icons.ac_unit,
          size: 13,
          color: color,
        ),
        const SizedBox(width: 3),
        Text(
          heating ? l10n.ctrlAirductHeating : l10n.ctrlAirductCooling,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

/// Icon color for temperature tile depends on sensor state: white when target
/// unset, blue when cooling (actual above target), orange when heating/holding high temp.
Color _tempIconColor(ColorScheme scheme, double? actual, double? target) {
  // Target unset (null or 0 = heating off)→neutral white.
  if (target == null || target <= 0) return scheme.onSurface;
  // Tolerance: minor fluctuations at target shouldn't flicker the color.
  const tolerance = 2.0;
  if (actual != null && actual > target + tolerance) {
    return const Color(0xFF4FC3F7); // cooling—blue
  }
  return const Color(0xFFFF8A50); // heating/high temp—orange
}

class _StateChip extends StatelessWidget {
  const _StateChip({
    required this.label,
    required this.connected,
    this.active = false,
    this.offline = false,
  });

  final String label;
  final bool connected;
  final bool active;

  /// OFFLINE variant: light red background + vivid red border so disconnected
  /// printer stands out even in collapsed card.
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor: offline
          ? scheme.error.withValues(alpha: 0.12)
          : (active
              ? scheme.primaryContainer
              : (connected
                  ? scheme.secondaryContainer
                  : scheme.surfaceContainerHighest)),
      side: offline
          ? BorderSide(color: scheme.error, width: 1.5)
          : BorderSide.none,
      label: Text(
        label,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: offline ? scheme.error : null),
      ),
    );
  }
}

enum _TempKind { nozzle, bed, chamber, unknown }

/// Pair of readings (current + target) for one sensor. Label is translated
/// at render time (with [BuildContext]).
class _TempReading {
  const _TempReading({
    required this.kind,
    required this.raw,
    required this.actual,
    required this.target,
    this.index,
    this.airductIsHeating,
  });

  final _TempKind kind;
  final String raw; // raw key—shown for unknown sensor
  final int? index; // nozzle number (e.g., 2) or null
  final double? actual;
  final double? target;

  /// Chamber air duct mode (heating/cooling); set ONLY for chamber tile where we
  /// show it instead of separate chip. null = unknown/n.a.
  final bool? airductIsHeating;

  String label(AppLocalizations l10n) => switch (kind) {
        _TempKind.nozzle =>
          index == null ? l10n.tempNozzle : l10n.tempNozzleNumbered('$index'),
        _TempKind.bed => l10n.tempBed,
        _TempKind.chamber => l10n.tempChamber,
        _TempKind.unknown => raw,
      };

  IconData get icon => switch (kind) {
        _TempKind.nozzle => Icons.local_fire_department,
        _TempKind.bed => Icons.wb_iridescent,
        _TempKind.chamber => Icons.thermostat,
        _TempKind.unknown => Icons.device_thermostat,
      };
}

/// Group raw temperature keys into current/target pairs and order known sensors
/// (nozzle, bed, chamber) before unknown ones.
List<_TempReading> _buildReadings(
  Map<String, double>? temps,
  bool? airductIsHeating,
) {
  if (temps == null || temps.isEmpty) return const [];

  final actuals = <String, double>{};
  final targets = <String, double>{};
  for (final entry in temps.entries) {
    var base = entry.key;
    final isTarget = base.endsWith('_target');
    if (isTarget) base = base.substring(0, base.length - '_target'.length);
    if (base.endsWith('_temper')) {
      base = base.substring(0, base.length - '_temper'.length);
    }
    (isTarget ? targets : actuals)[base] = entry.value;
  }

  const orderHint = ['nozzle', 'bed', 'chamber'];
  int rank(String base) {
    final stem = RegExp(r'^([a-z]+)').firstMatch(base)?.group(1) ?? base;
    final i = orderHint.indexOf(stem);
    return i == -1 ? orderHint.length : i;
  }

  final bases = {...actuals.keys, ...targets.keys}.toList()
    ..sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.compareTo(b);
    });

  return [
    for (final base in bases)
      _readingFor(base, actuals[base], targets[base], airductIsHeating),
  ];
}

_TempReading _readingFor(
  String base,
  double? actual,
  double? target,
  bool? airductIsHeating,
) {
  final numbered = RegExp(r'^([a-z]+)_(\d+)$').firstMatch(base);
  final stem = numbered?.group(1) ?? base;
  final index = numbered == null ? null : int.tryParse(numbered.group(2)!);

  final kind = switch (stem) {
    'nozzle' => _TempKind.nozzle,
    'bed' => _TempKind.bed,
    'chamber' => _TempKind.chamber,
    _ => _TempKind.unknown,
  };

  return _TempReading(
    kind: kind,
    raw: base,
    index: kind == _TempKind.nozzle ? index : null,
    actual: actual,
    target: target,
    // Air duct applies to chamber only.
    airductIsHeating: kind == _TempKind.chamber ? airductIsHeating : null,
  );
}

String _durationText(AppLocalizations l10n, int minutes) => minutes < 60
    ? l10n.durationMinutes(minutes)
    : l10n.durationHoursMinutes(minutes ~/ 60, minutes % 60);

/// ETA as HH:mm = now + remaining minutes.
String _etaTime(int remainingMinutes) {
  final eta = DateTime.now().add(Duration(minutes: remainingMinutes));
  final hh = eta.hour.toString().padLeft(2, '0');
  final mm = eta.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}
