import 'package:flutter/material.dart';

import '../../core/ams/slot_addressing.dart';
import '../../core/models/loaded_spools.dart';
import '../../core/models/slicer_preset.dart';
import '../../core/slicer/loaded_spool_match.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../inventory/inventory_screen.dart' show SpoolSwatch;
import 'package:app_diagnostics/app_diagnostics.dart';

/// A spool picked for one filament row: the profile it stands for, and the
/// colour it really is (`#RRGGBB`, null when the printer named none).
typedef PickedSpool = ({SlicerPreset preset, String? colour});

/// The spools loaded in the online printers of the selected model, laid out
/// like the units themselves, for filling one filament row (#3172, the web's
/// `SliceSpoolPicker`). An empty slot stays in its place; a loaded spool with
/// no profile for the selected printer is shown and cannot be picked.
Future<PickedSpool?> showLoadedSpoolPicker(
  BuildContext context, {
  required String slotLabel,
  required List<LoadedSpoolPrinter> printers,
  required SlicerPreset? Function(LoadedSpoolTray tray) matchFor,
}) => dashSheet<PickedSpool>(
  context,
  builder: (_) => _SpoolPicker(
    slotLabel: slotLabel,
    printers: printers,
    matchFor: matchFor,
  ),
);

class _SpoolPicker extends StatelessWidget {
  const _SpoolPicker({
    required this.slotLabel,
    required this.printers,
    required this.matchFor,
  });

  final String slotLabel;
  final List<LoadedSpoolPrinter> printers;
  final SlicerPreset? Function(LoadedSpoolTray tray) matchFor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (ctx, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(
          DashSpace.gutter,
          0,
          DashSpace.gutter,
          DashSpace.xl,
        ),
        children: [
          Text(l10n.sliceLoadedSpools, style: t.titleSm),
          Text(slotLabel, style: t.labelSoft),
          const SizedBox(height: DashSpace.md),
          if (printers.isEmpty)
            Text(l10n.sliceLoadedNoneOfModel, style: t.bodySoft)
          else
            for (final printer in printers)
              _PrinterSection(printer: printer, matchFor: matchFor),
        ],
      ),
    );
  }
}

class _PrinterSection extends StatelessWidget {
  const _PrinterSection({required this.printer, required this.matchFor});

  final LoadedSpoolPrinter printer;
  final SlicerPreset? Function(LoadedSpoolTray tray) matchFor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final regular = [
      for (final u in printer.ams)
        if (!u.isAmsHt) u,
    ];
    final ht = [
      for (final u in printer.ams)
        if (u.isAmsHt) u,
    ];

    String externalLabel(LoadedSpoolTray tray) => printer.externalHolders > 1
        ? (tray.trayId == 0 ? 'Ext-L' : 'Ext-R')
        : l10n.mappingExternalSpool;

    Widget group(String title, List<(LoadedSpoolTray, String)> trays) =>
        Padding(
          padding: const EdgeInsets.only(bottom: DashSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: t.labelSoft),
              const SizedBox(height: DashSpace.xs),
              _TrayGrid(
                children: [
                  for (final (tray, label) in trays)
                    _TrayTile(tray: tray, label: label, match: matchFor(tray)),
                ],
              ),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: DashSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text([printer.name, ?printer.model].join(' · '), style: t.titleSm),
          const SizedBox(height: DashSpace.sm),
          if (printer.ams.isEmpty && printer.external.isEmpty)
            Text(l10n.sliceLoadedNothing, style: t.labelSoft),
          for (final unit in regular)
            group(amsUnitName(unit.id), [
              for (final tray in unit.trays)
                (tray, formatSlotLabel(unit.id, tray.trayId, isHt: false)),
            ]),
          if (ht.isNotEmpty)
            group('AMS-HT', [
              for (final unit in ht)
                for (final tray in unit.trays)
                  (tray, formatSlotLabel(unit.id, tray.trayId, isHt: true)),
            ]),
          if (printer.external.isNotEmpty)
            group(l10n.mappingExternalSpool, [
              for (final tray in printer.external) (tray, externalLabel(tray)),
            ]),
        ],
      ),
    );
  }
}

/// Two to a row, as the web lays a unit out on a phone.
class _TrayGrid extends StatelessWidget {
  const _TrayGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = (constraints.maxWidth - DashSpace.sm) / 2;
      return Wrap(
        spacing: DashSpace.sm,
        runSpacing: DashSpace.sm,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class _TrayTile extends StatelessWidget {
  const _TrayTile({
    required this.tray,
    required this.label,
    required this.match,
  });

  final LoadedSpoolTray tray;
  final String label;
  final SlicerPreset? match;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: t.subCardBorder),
    );
    if (!tray.isLoaded) {
      return Container(
        padding: const EdgeInsets.all(DashSpace.sm),
        decoration: ShapeDecoration(shape: shape),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: t.label),
            Text(
              tray.isUnidentified
                  ? l10n.sliceSpoolUnidentified
                  : l10n.sliceSpoolEmpty,
              style: t.labelSoft,
            ),
          ],
        ),
      );
    }
    final saved = savedPresetFor(tray);
    final profile = match != null
        ? presetDisplayName(match!.name)
        : saved != null
        ? presetDisplayName(saved.presetName)
        : tray.traySubBrands;
    final picked = match;
    return Material(
      color: t.subCard,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: picked == null
            ? null
            : () => Navigator.pop<PickedSpool>(context, (
                preset: picked,
                colour: trayColourHex(tray),
              )),
        child: Opacity(
          opacity: picked == null ? 0.5 : 1,
          child: Padding(
            padding: const EdgeInsets.all(DashSpace.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SpoolSwatch(rgba: tray.trayColor, size: 16, radius: 4),
                    const SizedBox(width: DashSpace.xs),
                    Text(label, style: t.label),
                    const Spacer(),
                    Flexible(
                      child: Text(
                        tray.trayType ?? '',
                        style: t.labelSoft,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DashSpace.xs),
                Text(
                  profile ?? '—',
                  style: t.labelSoft,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (picked == null)
                  Text(
                    l10n.sliceSpoolNoProfile,
                    style: t.labelSoft,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ),
      ),
    ).tagged('slice.spool_tile');
  }
}
