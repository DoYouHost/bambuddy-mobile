import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ams/slot_addressing.dart';
import '../../core/diagnostics/filament_material.dart';
import '../../core/models/printer_status.dart';
import '../../core/theme/dash_theme.dart';
import '../../data/printer_commands_repository.dart';
import '../../l10n/app_localizations.dart';
import '../dashboard/controls_providers.dart';
import '../dashboard/widgets/printer_card.dart';
import '../inventory/inventory_providers.dart';
import 'controller_controls.dart';
import 'controller_providers.dart';
import 'scale_to_fit.dart';

/// The fullest spool a card has to fit: 100 % of a kilogram, which is what the
/// widest usage line reads.
const _fullestSpoolGrams = '1000';

/// The Filament tab: the AMS units, one at a time, with their slots
/// ([docs/single-printer-controller.md] §2). A tap chooses a slot, and Load and
/// Unload under the slots act on it, through the printer card's own commands
/// (`runSlotCommand`), so the wording, the Filament Track Switch question and
/// the addressing are the card's. The pencil on a slot opens the card's slot
/// sheet for the spool and the configuration. One unit is on screen at a time,
/// so the tab never scrolls however many units there are.
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

  /// The chosen slot of the unit on screen; null until one is tapped, when the
  /// slot feeding the print (or else the first) stands in.
  int? _slot;

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
    final trays = entry.unit == null
        ? status.externalSpools
        : (entry.unit!.trays ?? const <AmsTray>[]);
    final active = trays.indexWhere(
      (tray) => identical(tray, status.activeTray),
    );
    final slot = trays.isEmpty
        ? null
        : (_slot ?? (active >= 0 ? active : 0)).clamp(0, trays.length - 1);
    void select(int i) => setState(() {
      _selected = i;
      _slot = null;
    });
    final pane = _Pane(
      printerId: widget.printerId,
      status: status,
      nozzleCount: item.printer.nozzleCount,
      serial: item.printer.serialNumber,
      unitIndex: entry.unitIndex,
      unit: entry.unit,
      trays: trays,
      slot: slot,
      dual: dual,
      onSlot: (i) => setState(() => _slot = i),
    );
    // On a page the units sit in a row above the pane, which then has the whole
    // width: a name and its humidity do not fit a 168 dp column.
    if (controllerPaged(context)) {
      return ControllerPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: _Rail._minHeight,
              child: _Rail(
                entries: entries,
                selected: entries.indexOf(entry),
                status: status,
                dual: dual,
                onSelect: select,
                horizontal: true,
              ),
            ),
            const SizedBox(height: DashSpace.sm),
            pane,
          ],
        ),
      );
    }
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
            onSelect: select,
          ),
        ),
        const SizedBox(width: DashSpace.md),
        Expanded(
          child: _Pane(
            printerId: widget.printerId,
            status: status,
            nozzleCount: item.printer.nozzleCount,
            serial: item.printer.serialNumber,
            unitIndex: entry.unitIndex,
            unit: entry.unit,
            trays: trays,
            slot: slot,
            dual: dual,
            onSlot: (i) => setState(() => _slot = i),
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
    this.horizontal = false,
  });

  final List<_Entry> entries;
  final int selected;
  final PrinterStatus status;
  final bool dual;
  final ValueChanged<int> onSelect;
  final bool horizontal;

  /// The width of a unit's button in the row.
  static const _tileWidth = 236.0;

  /// A rail button never grows past this, so a printer with one unit does not
  /// get one enormous button.
  static const _minHeight = 56.0;
  static const _maxHeight = 72.0;

  /// The printer's own mark for a side, said in words to a reader.
  static Widget _sideMark(DashTokens t, String mark, String words) => Padding(
    padding: const EdgeInsets.only(right: DashSpace.sm),
    child: Semantics(
      label: words,
      excludeSemantics: true,
      child: Text(mark, style: t.bodyStrong.copyWith(color: t.textTertiary)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final radius = BorderRadius.circular(DashSpace.md + DashSpace.xs);
    final rail = Flex(
      direction: horizontal ? Axis.horizontal : Axis.vertical,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        for (final (i, entry) in entries.indexed) ...[
          if (i > 0)
            horizontal
                ? const SizedBox(width: DashSpace.sm)
                : const SizedBox(height: DashSpace.sm),
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
                      ? t.accent.withValues(alpha: DashAlpha.faint)
                      : t.subCard,
                  shape: RoundedRectangleBorder(
                    borderRadius: radius,
                    side: BorderSide(
                      color: i == selected
                          ? t.accent.withValues(alpha: DashAlpha.scrim)
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
                      // The name, and on the same line the humidity, at a size
                      // that reads from a stand.
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.unit == null
                                  ? l10n.externalSpool
                                  : amsUnitName(
                                      entry.unit!.id ?? entry.unitIndex!,
                                    ),
                              style: t.titleSm.copyWith(
                                color: i == selected
                                    ? t.textPrimary
                                    : t.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // The row has no header to say which head the unit
                          // feeds, so the unit says it itself.
                          if (horizontal && dual && entry.unit != null)
                            switch (status.amsExtruderMap?[entry.unit!.id]) {
                              1 => _sideMark(
                                t,
                                l10n.extruderLeftShort,
                                l10n.extruderLeft,
                              ),
                              0 => _sideMark(
                                t,
                                l10n.extruderRightShort,
                                l10n.extruderRight,
                              ),
                              _ => const SizedBox.shrink(),
                            },
                          if (entry.unit?.humidity != null) ...[
                            const SizedBox(width: DashSpace.xs),
                            Icon(
                              Icons.water_drop_outlined,
                              size: controllerIconSize(context, DashSpace.lg),
                              color: t.accentBlue,
                            ),
                            const SizedBox(width: DashSpace.xs),
                            Text(
                              '${entry.unit!.humidity}%',
                              style: t.monoValue,
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
    if (!horizontal) return rail;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(width: entries.length * _tileWidth, child: rail),
    );
  }
}

/// The unit on screen: its readings, a card per slot, and the actions on the
/// chosen slot.
class _Pane extends ConsumerWidget {
  const _Pane({
    required this.printerId,
    required this.status,
    required this.nozzleCount,
    required this.serial,
    required this.unitIndex,
    required this.unit,
    required this.trays,
    required this.slot,
    required this.dual,
    required this.onSlot,
  });

  final int printerId;
  final PrinterStatus status;
  final int? nozzleCount;

  /// The printer's serial number: a spool without a tag is matched in
  /// Spoolman by a tag derived from it and the slot (`fallbackSpoolTag`).
  final String? serial;

  /// Null for the external holder, whose [trays] are its spools.
  final int? unitIndex;
  final AmsUnit? unit;
  final List<AmsTray> trays;
  final int? slot;
  final bool dual;
  final ValueChanged<int> onSlot;

  static const _headerHeight = controllerButtonHeight;
  static const _actionHeight = controllerButtonHeight;

  /// The spool a card on a page keeps above its text, as tall as this.
  static const _spoolHeight = 112.0;

  /// The row of spools takes the pane's height; on a page nothing hands it one,
  /// so it is the spool, the card's two text blocks at the lines the fullest
  /// card takes, and the card's padding. A card with less text gives the spare
  /// lines to its spool, as on a screen.
  static Widget _fill(
    BuildContext context,
    DashTokens t,
    bool page,
    Widget child,
  ) {
    if (!page) return Expanded(child: child);
    double line(TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: 'Ag', style: style),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final height = painter.height;
      painter.dispose();
      return height;
    }

    final lines = controllerLargeText(context) ? 2 : 1;
    return SizedBox(
      height:
          _spoolHeight +
          DashSpace.sm +
          lines * (line(t.titleMd) + line(t.monoValue)) +
          2 * DashSpace.sm,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final assigned = ref.watch(assignedSpoolsProvider(status.id));
    final refused = ref.watch(
      controlRefusedProvider(ControlPermission.control),
    );
    final busy = ref.watch(
      controlsProvider.select(
        (s) => s.pendingFor(printerId).isBusy(ControlAction.ams),
      ),
    );
    final large = controllerPaged(context);
    final unit = this.unit;
    final amsId = unit == null ? externalHolderUnit : (unit.id ?? unitIndex!);
    final active = status.activeTray;
    // The card's lock: on while printing, off while paused, which is when a
    // runout needs a reload ([docs/single-printer-controller.md] §2).
    final locked = status.isPrinting && !status.isPaused;
    final chosen = slot;
    // A slot with no global tray number (AMS-HT) cannot be loaded by one.
    final addressable =
        chosen != null &&
        amsLoadTrayId(
              amsId: amsId,
              trayId: unit == null
                  ? (externalSideOf(trays[chosen].id) ?? 0)
                  : chosen,
            ) !=
            null;
    final canDry =
        unit != null && (status.supportsDrying ?? false) && unit.canDry;
    final side = dual && unit != null
        ? (status.amsExtruderMap?[unit.id])
        : null;

    void command(bool load) => runSlotCommand(
      context,
      ref,
      load: load,
      status: status,
      nozzleCount: nozzleCount,
      unitIndex: unitIndex,
      index: chosen!,
    );

    final actions = <Widget>[
      if (!refused && addressable) ...[
        _ActionButton(
          id: 'controller.load',
          icon: Icons.login,
          label: l10n.amsLoad,
          tone: t.accent,
          ink: t.accentInk,
          locked: locked,
          onPressed: locked || busy ? null : () => command(true),
        ),
        _ActionButton(
          id: 'controller.unload',
          icon: Icons.logout,
          label: l10n.amsUnload,
          tone: t.accent,
          ink: t.accentInk,
          locked: locked,
          onPressed: locked || busy ? null : () => command(false),
        ),
      ],
      if (large && canDry && !refused)
        logTag(
          'controller.dry',
          FilledButton.icon(
            style: controllerButtonStyle(t, tone: t.accent, ink: t.accentInk),
            icon: const Icon(Icons.local_fire_department_outlined),
            label: Text(
              unit.isDrying ? l10n.ctrlDrying : l10n.ctrlDry,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
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
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // At a large text size the row of units above says all of this, and the
        // room goes to the spools; Drying moves in with the slot's buttons.
        if (!large) ...[
          // At least the button height, and taller when a large text size needs
          // it: a fixed height cut the Drying button.
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _headerHeight),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          unit == null
                              ? l10n.externalSpool
                              : amsUnitName(amsId),
                          style: t.titleLg,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (side == 1 || side == 0) ...[
                        const SizedBox(width: DashSpace.md),
                        DashPill(
                          label: side == 1
                              ? l10n.extruderLeft
                              : l10n.extruderRight,
                          accent: t.textSecondary,
                        ),
                      ],
                      if (unit?.humidity != null)
                        _Reading(
                          icon: Icons.water_drop_outlined,
                          color: t.accentBlue,
                          value: '${unit!.humidity}%',
                        ),
                      if (unit?.temp != null)
                        _Reading(
                          icon: Icons.thermostat_outlined,
                          color: t.accentOrange,
                          value: '${unit!.temp!.toStringAsFixed(0)}°C',
                        ),
                    ],
                  ),
                ),
                // Drying is the whole unit's, so it sits with the unit, not
                // with the slot actions.
                if (canDry && !refused)
                  logTag(
                    'controller.dry',
                    FilledButton.icon(
                      style: controllerButtonStyle(
                        t,
                        minimumSize: const Size(0, controllerButtonHeight),
                        tone: t.accent,
                        ink: t.accentInk,
                      ),
                      icon: const Icon(Icons.local_fire_department_outlined),
                      label: Text(
                        unit.isDrying ? l10n.ctrlDrying : l10n.ctrlDry,
                      ),
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
        ],
        _fill(
          context,
          t,
          large,
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, tray) in trays.indexed) ...[
                if (i > 0) const SizedBox(width: DashSpace.sm),
                Expanded(
                  child: _SlotCard(
                    number: unit == null ? null : i + 1,
                    caption: unit == null && dual
                        ? switch (status.extruderForExternal(tray.id)) {
                            1 => l10n.extruderLeft,
                            0 => l10n.extruderRight,
                            _ => null,
                          }
                        : null,
                    // The printer's own marks, like the unit names: short
                    // enough not to cover the spool.
                    captionMark: unit == null && dual
                        ? switch (status.extruderForExternal(tray.id)) {
                            1 => l10n.extruderLeftShort,
                            0 => l10n.extruderRightShort,
                            _ => null,
                          }
                        : null,
                    tray: tray,
                    active: identical(tray, active),
                    selected: i == chosen,
                    fill: assigned.fillOf(
                      tray,
                      amsId: amsId,
                      trayId: unit == null ? (externalSideOf(tray.id) ?? 0) : i,
                      serial: serial,
                    ),
                    onTap: () => onSlot(i),
                    onEdit: () => unit == null
                        ? showExternalSlotSheet(
                            context,
                            ref,
                            status: status,
                            nozzleCount: nozzleCount,
                            spoolIndex: i,
                          )
                        : showAmsSlotSheet(
                            context,
                            ref,
                            status: status,
                            nozzleCount: nozzleCount,
                            unitIndex: unitIndex!,
                            trayIndex: i,
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: DashSpace.md),
          // At least the button height, and taller when a large text size needs
          // it: a fixed height cut the label.
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _actionHeight),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, action) in actions.indexed) ...[
                    if (i > 0) const SizedBox(width: DashSpace.sm),
                    Expanded(child: action),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// One of a unit's readings in its header: an icon that says what it is, and
/// the value.
class _Reading extends StatelessWidget {
  const _Reading({
    required this.icon,
    required this.color,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: DashSpace.lg),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: controllerIconSize(context, DashSpace.xl),
            color: color,
          ),
          const SizedBox(width: DashSpace.xs),
          Text(value, style: t.monoTitle),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.id,
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.tone,
    this.locked = false,
    this.ink,
  });

  final String id;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// The printer is printing: a lock after the label says why the button is off.
  final bool locked;

  /// Its colour while it works ([controllerButtonStyle]).
  final Color tone;
  final Color? ink;

  @override
  Widget build(BuildContext context) {
    final button = logTag(
      id,
      FilledButton.icon(
        style: controllerButtonStyle(
          DashTokens.of(context),
          tone: tone,
          ink: ink,
        ),
        onPressed: onPressed,
        icon: Icon(icon),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (locked) ...[
              const SizedBox(width: DashSpace.sm),
              Icon(
                Icons.lock_outline,
                size: controllerIconSize(context, DashSpace.lg),
              ),
            ],
          ],
        ),
      ),
    );
    return locked
        ? Tooltip(
            message: AppLocalizations.of(context).amsActionsWhilePrinting,
            child: button,
          )
        : button;
  }
}

/// One slot: its number, the colour, the material, what is left, and a mark on
/// the one feeding the print. A tap chooses it; the pencil opens its sheet.
class _SlotCard extends StatelessWidget {
  const _SlotCard({
    required this.number,
    required this.tray,
    required this.active,
    required this.selected,
    required this.fill,
    required this.onTap,
    required this.onEdit,
    this.caption,
    this.captionMark,
  });

  final int? number;

  /// What the side is called, said to a screen reader.
  final String? caption;

  /// What is drawn for [caption].
  final String? captionMark;
  final AmsTray tray;
  final bool active;
  final bool selected;
  final TrayFill fill;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  static const _spoolAsset = 'assets/icons/filament_spool_wound.svg';

  /// The round chip the slot's number sits in.
  static const _chip = 32.0;

  /// What the edit pencil takes from the top row.
  static const _editWidth = 48.0;

  /// The corner mark: the slot's number in a round chip, or the external
  /// spool's name in a pill, on the accent when the slot feeds the print. A
  /// spool with no name that is active still gets a chip, with a tick in it;
  /// null where there is nothing to say.
  Widget? _labelChip(DashTokens t, AppLocalizations l10n) {
    final label = number?.toString() ?? captionMark ?? caption;
    final named = label != null && label.isNotEmpty;
    if (!named && !active) return null;
    final ink = active ? t.onAccent : t.textPrimary;
    final chip = Container(
      constraints: const BoxConstraints(minWidth: _chip, minHeight: _chip),
      padding: number == null && named && captionMark == null
          ? const EdgeInsets.symmetric(horizontal: DashSpace.md)
          : EdgeInsets.zero,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_chip / 2),
        color: active
            ? t.accent
            : t.textPrimary.withValues(alpha: DashAlpha.faint),
      ),
      // Not the Container's `alignment`: that stretches the chip across the
      // whole row the Positioned gives it, and a number becomes a long pill.
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: named
            ? Text(
                label,
                style: number == null
                    ? t.bodyStrong.copyWith(color: ink)
                    : t.monoValue.copyWith(color: ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : Icon(Icons.check, size: DashSpace.lg + DashSpace.xs, color: ink),
      ),
    );
    // The mark is a letter; the reader is told the side in words.
    final read = captionMark == null || caption == null
        ? chip
        : Semantics(label: caption, excludeSemantics: true, child: chip);
    return active ? Tooltip(message: l10n.ctrlNozzleActive, child: read) : read;
  }

  static bool _fits(
    BuildContext context,
    String text,
    TextStyle style,
    double width,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final fits = painter.width <= width;
    painter.dispose();
    return fits;
  }

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final large = controllerLargeText(context);
    final empty = tray.isEmpty;
    final color = empty ? null : parseTrayColor(tray.trayColor);
    final radius = BorderRadius.circular(DashSpace.md + DashSpace.xs);
    final percent = empty ? null : fill.percent;
    final grams = empty ? null : fill.grams;
    final card = Material(
      color: selected ? t.accent.withValues(alpha: DashAlpha.faint) : t.subCard,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: selected
              ? t.accent.withValues(alpha: DashAlpha.strong)
              : t.subCardBorder,
          width: selected ? 2 : 1,
        ),
      ),
      child: logTagMaterial(
        'controller.slot',
        tray.trayType,
        InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Stack(
            children: [
              // The slot's number, or the external spool's name, in the corner
              // the pencil is not in.
              Padding(
                padding: const EdgeInsets.all(DashSpace.sm),
                child: Column(
                  children: [
                    // The spool takes what the text under it leaves, the same
                    // on every card, so the cards fill up instead of sitting
                    // in a corner of themselves.
                    Expanded(
                      child: _Wiggle(
                        play: selected,
                        child: Opacity(
                          // An empty slot is the same spool, greyed out.
                          opacity: empty ? 0.4 : 1,
                          child: SvgPicture.asset(
                            _spoolAsset,
                            width: double.infinity,
                            height: double.infinity,
                            colorMapper: _SpoolColors(
                              empty ? t.textTertiary : color ?? t.textTertiary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: DashSpace.sm),
                    Text(
                      empty
                          ? l10n.traySlotEmpty
                          : (tray.materialLabel ?? l10n.traySlotEmpty),
                      style: t.titleMd.copyWith(
                        color: empty ? t.textTertiary : t.textPrimary,
                      ),
                      maxLines: large ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    LayoutBuilder(
                      builder: (context, box) {
                        final style = t.monoValue.copyWith(
                          color: percent != null && percent < _lowPercent
                              ? t.dangerInk
                              : t.textSecondary,
                        );
                        final weight = grams == null
                            ? null
                            : l10n.inventoryUsageWeight(
                                grams.toStringAsFixed(0),
                              );
                        final one = [
                          if (percent != null) '$percent%',
                          ?weight,
                        ].join(' · ');
                        // At a large text size the two facts take a line each
                        // only where the fullest spool, 100% and 1000 g, would
                        // not fit one; the same for every card of a row.
                        final twoLines =
                            large &&
                            !_fits(
                              context,
                              '100% · ${l10n.inventoryUsageWeight(_fullestSpoolGrams)}',
                              style,
                              box.maxWidth,
                            );
                        // A card with one fact has one line: the spool takes
                        // the line that is not there, so the card is filled to
                        // its bottom edge.
                        if (one.isEmpty) return const SizedBox.shrink();
                        final both = one.contains(' · ');
                        return Text(
                          twoLines && both
                              ? one.replaceFirst(' · ', '\n')
                              : one,
                          maxLines: twoLines && both ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: style,
                        );
                      },
                    ),
                  ],
                ),
              ),
              // The slot's mark, in the corner the pencil is not in, painted
              // over the spool, which reaches into that corner.
              Positioned(
                top: DashSpace.md,
                left: DashSpace.md,
                right: _editWidth,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _labelChip(t, l10n) ?? const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: Semantics(selected: selected, child: card),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: logTag(
            'controller.slot_edit',
            IconButton(
              tooltip: AppLocalizations.of(context).controllerEditSlot,
              icon: Icon(
                Icons.edit_outlined,
                size: controllerIconSize(context, DashSpace.lg + DashSpace.xs),
              ),
              color: t.textSecondary,
              onPressed: onEdit,
            ),
          ),
        ),
      ],
    );
  }

  /// A slot under this share of its spool reads as running out.
  static const _lowPercent = 20;
}

/// The colour of the spool drawing (`assets/icons/filament_spool_wound.svg`, made
/// by Recraft) that stands for the filament: its winding. Everything else in it,
/// the flanges and the outline, keeps its own.
class _SpoolColors extends ColorMapper {
  const _SpoolColors(this.filament);

  final Color filament;

  static const _winding = Color.fromARGB(255, 230, 71, 152);

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) {
    // The drawing's outline is near-black: a black filament is lifted a little
    // so it still reads as a winding inside it.
    final tint = filament.computeLuminance() < 0.02
        ? Color.lerp(filament, Colors.white, 0.2)!
        : filament;
    if (color == _winding) return tint;
    return color;
  }

  @override
  bool operator ==(Object other) =>
      other is _SpoolColors && other.filament == filament;

  @override
  int get hashCode => filament.hashCode;
}

/// Rocks [child] left and right, dying away, each time [play] turns true: the
/// answer to a tap that only moves the outline, since choosing a slot changes
/// nothing on the printer until Load or Unload is pressed. Not on first build,
/// and the controller's own animation behaviour cuts it short for a person who
/// turned animations off.
class _Wiggle extends StatefulWidget {
  const _Wiggle({required this.play, required this.child});

  final bool play;
  final Widget child;

  @override
  State<_Wiggle> createState() => _WiggleState();
}

class _WiggleState extends State<_Wiggle> with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 500);

  /// The widest swing, in radians (about 5 degrees), and how many swings.
  static const _swing = 0.09;
  static const _swings = 3;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
  );

  @override
  void didUpdateWidget(_Wiggle old) {
    super.didUpdateWidget(old);
    if (widget.play && !old.play) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      final t = _controller.value;
      return Transform.rotate(
        angle: math.sin(t * 2 * math.pi * _swings) * _swing * (1 - t),
        child: child,
      );
    },
  );
}
