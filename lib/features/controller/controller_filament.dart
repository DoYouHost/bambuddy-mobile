import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ams/slot_addressing.dart';
import '../../core/diagnostics/filament_material.dart';
import '../../core/models/printer_status.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../dashboard/controls_providers.dart';
import '../dashboard/widgets/printer_card.dart';
import '../inventory/inventory_providers.dart';
import 'controller_providers.dart';
import 'scale_to_fit.dart';

/// The Filament tab: the AMS units, one at a time, with their slots
/// ([docs/single-printer-controller.md] §2). A tap on a slot opens the printer
/// card's own slot sheet — assign a spool, load or unload, re-read the tag,
/// configure — so every action keeps the card's locks (load and unload are off
/// while the printer is printing). One unit is on screen at a time, so the tab
/// never scrolls however many units there are.
class ControllerFilament extends ConsumerStatefulWidget {
  const ControllerFilament({super.key, required this.printerId});

  final int printerId;

  @override
  ConsumerState<ControllerFilament> createState() => _ControllerFilamentState();
}

/// What the rail lists: a unit of [PrinterStatus.ams], or the external holder.
typedef _Entry = ({int? unitIndex, AmsUnit? unit});

class _ControllerFilamentState extends ConsumerState<ControllerFilament> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final item = ref.watch(controllerPrinterProvider(widget.printerId)).item;
    final status = item?.status;
    if (item == null || status == null) return const SizedBox.shrink();
    final units = status.ams ?? const <AmsUnit>[];
    final entries = <_Entry>[
      for (final (i, unit) in units.indexed) (unitIndex: i, unit: unit),
      if (status.externalSpools.isNotEmpty) (unitIndex: null, unit: null),
    ];
    if (entries.isEmpty) {
      return Center(child: Text('—', style: DashTokens.of(context).bodySoft));
    }
    // A unit can vanish between frames; the choice follows what is there.
    final entry = entries[_selected.clamp(0, entries.length - 1)];
    final dual = status.isDualNozzle(item.printer.nozzleCount);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _railWidth,
          child: _Rail(
            entries: entries,
            selected: entries.indexOf(entry),
            status: status,
            dual: dual,
            onSelect: (i) => setState(() => _selected = i),
          ),
        ),
        const SizedBox(width: DashSpace.md),
        Expanded(
          child: entry.unit == null
              ? _External(
                  printerId: widget.printerId,
                  status: status,
                  nozzleCount: item.printer.nozzleCount,
                  dual: dual,
                )
              : _Unit(
                  printerId: widget.printerId,
                  status: status,
                  nozzleCount: item.printer.nozzleCount,
                  unitIndex: entry.unitIndex!,
                  unit: entry.unit!,
                  dual: dual,
                ),
        ),
      ],
    );
  }

  static const _railWidth = 168.0;
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.entries,
    required this.selected,
    required this.status,
    required this.dual,
    required this.onSelect,
  });

  final List<_Entry> entries;
  final int selected;
  final PrinterStatus status;
  final bool dual;
  final ValueChanged<int> onSelect;

  /// A rail button never grows past this, so a printer with one unit does not
  /// get one enormous button.
  static const _minHeight = 56.0;
  static const _maxHeight = 72.0;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final radius = BorderRadius.circular(DashSpace.md + DashSpace.xs);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        for (final (i, entry) in entries.indexed) ...[
          if (i > 0) const SizedBox(height: DashSpace.sm),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: _minHeight,
                maxHeight: _maxHeight,
              ),
              child: logTag(
                'controller.filament_unit',
                Material(
                  color: i == selected
                      ? t.accent.withValues(alpha: 0.10)
                      : t.subCard,
                  shape: RoundedRectangleBorder(
                    borderRadius: radius,
                    side: BorderSide(
                      color: i == selected
                          ? t.accent.withValues(alpha: 0.55)
                          : t.subCardBorder,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: radius,
                    onTap: () => onSelect(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DashSpace.md,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.unit == null
                                  ? l10n.externalSpool
                                  : amsUnitName(
                                      entry.unit!.id ?? entry.unitIndex!,
                                    ),
                              style: t.bodyBold.copyWith(
                                color: i == selected
                                    ? t.textPrimary
                                    : t.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (entry.unit?.humidity != null) ...[
                            const SizedBox(width: DashSpace.xs),
                            Icon(
                              Icons.water_drop_outlined,
                              size: DashSpace.md,
                              color: t.accentBlue,
                            ),
                            Text(
                              '${entry.unit!.humidity}%',
                              style: t.monoLabel,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                selected: i == selected,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// One AMS unit: its readings and drying, and a card per slot.
class _Unit extends ConsumerWidget {
  const _Unit({
    required this.printerId,
    required this.status,
    required this.nozzleCount,
    required this.unitIndex,
    required this.unit,
    required this.dual,
  });

  final int printerId;
  final PrinterStatus status;
  final int? nozzleCount;
  final int unitIndex;
  final AmsUnit unit;
  final bool dual;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final amsId = unit.id ?? unitIndex;
    final trays = unit.trays ?? const <AmsTray>[];
    final assigned = ref.watch(assignedSpoolsProvider(status.id));
    final refused = ref.watch(
      controlRefusedProvider(ControlPermission.control),
    );
    final active = status.activeTray;
    final side = dual ? (status.amsExtruderMap?[unit.id]) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _headerHeight,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  [
                    amsUnitName(amsId),
                    ?switch (side) {
                      1 => l10n.extruderLeftShort,
                      0 => l10n.extruderRightShort,
                      _ => null,
                    },
                    if (unit.humidity != null) '${unit.humidity}%',
                    if (unit.temp != null) '${unit.temp!.toStringAsFixed(0)}°',
                  ].join(' · '),
                  style: t.monoValue.copyWith(fontSize: _headerFont),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if ((status.supportsDrying ?? false) && unit.canDry && !refused)
                logTag(
                  'controller.dry',
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, _headerHeight),
                    ),
                    icon: const Icon(Icons.local_fire_department_outlined),
                    label: Text(unit.isDrying ? l10n.ctrlDrying : l10n.ctrlDry),
                    onPressed: () => showAmsDryingSheet(
                      context,
                      ref,
                      printerId: printerId,
                      amsId: amsId,
                      amsLabel: amsUnitName(amsId),
                      unit: unit,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: DashSpace.sm),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, tray) in trays.indexed) ...[
                if (i > 0) const SizedBox(width: DashSpace.sm),
                Expanded(
                  child: _SlotCard(
                    number: i + 1,
                    tray: tray,
                    active: identical(tray, active),
                    fill: assigned.fillOf(
                      tray,
                      amsId: amsId,
                      trayId: i,
                      serial: null,
                    ),
                    onTap: () => showAmsSlotSheet(
                      context,
                      ref,
                      status: status,
                      nozzleCount: nozzleCount,
                      unitIndex: unitIndex,
                      trayIndex: i,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static const _headerHeight = 44.0;
  static const _headerFont = 16.0;
}

/// The external spool holder: one card, or one per nozzle on two heads.
class _External extends ConsumerWidget {
  const _External({
    required this.printerId,
    required this.status,
    required this.nozzleCount,
    required this.dual,
  });

  final int printerId;
  final PrinterStatus status;
  final int? nozzleCount;
  final bool dual;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final spools = status.externalSpools;
    final assigned = ref.watch(assignedSpoolsProvider(status.id));
    final active = status.activeTray;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _Unit._headerHeight,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.externalSpool,
              style: t.monoValue.copyWith(fontSize: _Unit._headerFont),
            ),
          ),
        ),
        const SizedBox(height: DashSpace.sm),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, spool) in spools.indexed) ...[
                if (i > 0) const SizedBox(width: DashSpace.sm),
                Expanded(
                  child: _SlotCard(
                    number: null,
                    caption: dual
                        ? switch (status.extruderForExternal(spool.id)) {
                            1 => l10n.extruderLeft,
                            0 => l10n.extruderRight,
                            _ => null,
                          }
                        : null,
                    tray: spool,
                    active: identical(spool, active),
                    fill: assigned.fillOf(
                      spool,
                      amsId: externalHolderUnit,
                      trayId: externalSideOf(spool.id) ?? 0,
                      serial: null,
                    ),
                    onTap: () => showExternalSlotSheet(
                      context,
                      ref,
                      status: status,
                      nozzleCount: nozzleCount,
                      spoolIndex: i,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One slot: its number, the colour, the material, what is left, and a mark on
/// the one feeding the print. Tapping opens the slot sheet.
class _SlotCard extends StatelessWidget {
  const _SlotCard({
    required this.number,
    required this.tray,
    required this.active,
    required this.fill,
    required this.onTap,
    this.caption,
  });

  final int? number;
  final String? caption;
  final AmsTray tray;
  final bool active;
  final TrayFill fill;
  final VoidCallback onTap;

  static const _disc = 56.0;
  static const _discStroke = 4.0;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final empty = tray.isEmpty;
    final color = empty ? null : parseTrayColor(tray.trayColor);
    final radius = BorderRadius.circular(DashSpace.md + DashSpace.xs);
    final percent = empty ? null : fill.percent;
    final grams = empty ? null : fill.grams;
    return Material(
      color: active ? t.accent.withValues(alpha: 0.10) : t.subCard,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: active ? t.accent.withValues(alpha: 0.55) : t.subCardBorder,
        ),
      ),
      child: logTagMaterial(
        'controller.slot',
        tray.trayType,
        InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(DashSpace.sm),
            child: ScaleToFit(
              designSize: const Size(120, 160),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (number != null)
                    Text('$number', style: t.monoLabel)
                  else if (caption != null)
                    Text(caption!, style: t.labelSoft),
                  const SizedBox(height: DashSpace.xs),
                  Container(
                    width: _disc,
                    height: _disc,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: empty ? t.textTertiary : t.cardBorder,
                        width: empty ? 2 : _discStroke,
                      ),
                    ),
                  ),
                  const SizedBox(height: DashSpace.sm),
                  Text(
                    empty
                        ? l10n.traySlotEmpty
                        : (tray.materialLabel ?? l10n.traySlotEmpty),
                    style: t.bodyBold.copyWith(
                      color: empty ? t.textTertiary : t.textPrimary,
                    ),
                    maxLines: 1,
                  ),
                  if (percent != null || grams != null)
                    Text(
                      [
                        if (percent != null) '$percent%',
                        if (grams != null)
                          l10n.inventoryUsageWeight(grams.toStringAsFixed(0)),
                      ].join(' · '),
                      style: t.monoLabel.copyWith(
                        color: percent != null && percent < _lowPercent
                            ? t.dangerInk
                            : t.textSecondary,
                      ),
                    ),
                  if (active) ...[
                    const SizedBox(height: DashSpace.xs),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: DashSpace.md,
                          color: t.accentInk,
                        ),
                        const SizedBox(width: DashSpace.xs),
                        Text(
                          l10n.ctrlNozzleActive,
                          style: t.label.copyWith(color: t.accentInk),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A slot under this share of its spool reads as running out.
  static const _lowPercent = 20;
}
