import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';

import '../../core/ams/printer_model_match.dart';
import '../../core/ams/slot_addressing.dart';
import '../../core/models/loaded_spools.dart';
import '../../core/models/slicer_preset.dart';
import '../../core/slicer/loaded_spool_match.dart';
import '../../core/slicer/preset_filters.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../common/dash_search_field.dart';
import '../inventory/inventory_screen.dart' show SpoolSwatch;

/// Where a filament row was filled from a spool loaded in a printer (#3172):
/// its colour (`#RRGGBB`, null when the printer named none) and the printer
/// and slot, for the row to say so.
typedef SpoolOrigin = ({String? colour, String label});

/// A preset picked in [showPresetSheet], and the spool it came from, if any.
typedef PresetPick = ({SlicerPreset preset, SpoolOrigin? spool});

/// What a filament row adds to the plain preset list: the spools loaded in
/// the online printers, and the filters the catalogue needs to be usable.
class FilamentChoices {
  const FilamentChoices({
    required this.spoolPrinters,
    required this.matchFor,
    required this.ownedModels,
    required this.ownedMaterials,
    required this.ownedBrands,
    required this.registry,
    this.printerModel,
    this.needsMaterial,
  });

  /// The online printers of the selected model; null when no printer at all is
  /// online, and then the sheet has no Spools tab.
  final List<LoadedSpoolPrinter>? spoolPrinters;
  final SlicerPreset? Function(LoadedSpoolTray tray) matchFor;

  /// The filter options while "All" is off: the user's printer models, and the
  /// materials and brands of the spools they own.
  final Set<String> ownedModels;
  final Set<String> ownedMaterials;
  final Set<String> ownedBrands;

  /// `GET /slicer/printer-models`, which resolves a preset's printer tag.
  final Map<String, String> registry;

  /// The selected printer's model and the plate slot's material: the filters
  /// start on them.
  final String? printerModel;
  final String? needsMaterial;
}

/// One sheet per preset slot. A printer or process gets the list alone; a
/// filament row ([filament]) gets a Spools tab in front of it while a printer
/// is online, and the list gains printer, material and brand filters.
Future<PresetPick?> showPresetSheet(
  BuildContext context, {
  required String title,
  required List<SlicerPreset> filtered,
  required List<SlicerPreset> all,
  FilamentChoices? filament,
}) => dashSheet<PresetPick>(
  context,
  builder: (_) => _PresetSheet(
    title: title,
    filtered: filtered,
    all: all,
    filament: filament,
  ),
);

enum _Tab { spools, profiles }

class _PresetSheet extends StatefulWidget {
  const _PresetSheet({
    required this.title,
    required this.filtered,
    required this.all,
    required this.filament,
  });

  final String title;
  final List<SlicerPreset> filtered;
  final List<SlicerPreset> all;
  final FilamentChoices? filament;

  @override
  State<_PresetSheet> createState() => _PresetSheetState();
}

class _PresetSheetState extends State<_PresetSheet> {
  late _Tab _tab = widget.filament?.spoolPrinters != null
      ? _Tab.spools
      : _Tab.profiles;
  late bool _showAll = widget.filtered.isEmpty && widget.all.isNotEmpty;
  String _query = '';
  late String? _model = widget.filament?.printerModel;
  late String? _material = widget.filament?.needsMaterial?.toUpperCase();
  String? _brand;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final filament = widget.filament;
    final hasSpools = filament?.spoolPrinters != null;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      // The search field keeps the keyboard up; 0.5 is what the app's other
      // keyboard sheets settled on.
      minChildSize: 0.5,
      builder: (ctx, scrollController) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DashSpace.gutter,
                0,
                DashSpace.gutter,
                DashSpace.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title, style: t.titleSm),
                        if (filament?.needsMaterial case final m?)
                          Text(l10n.sliceNeedsMaterial(m), style: t.labelSoft),
                      ],
                    ),
                  ),
                  if (_tab == _Tab.profiles)
                    // Merged, or the reader announces a bare "switch".
                    MergeSemantics(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l10n.sliceShowAll, style: t.labelSoft),
                          Switch(
                            value: _showAll,
                            onChanged: (v) => setState(() => _showAll = v),
                          ).tagged('slice.show_all_presets'),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (hasSpools)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DashSpace.gutter,
                  0,
                  DashSpace.gutter,
                  DashSpace.sm,
                ),
                child: SegmentedButton<_Tab>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: _Tab.spools,
                      icon: const Icon(Icons.adjust),
                      label: Text(l10n.sliceTabSpools),
                    ),
                    ButtonSegment(
                      value: _Tab.profiles,
                      icon: const Icon(Icons.list),
                      label: Text(l10n.sliceTabProfiles),
                    ),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (s) => setState(() => _tab = s.first),
                ).tagged('slice.filament_tab'),
              ),
            Expanded(
              child: _tab == _Tab.spools
                  ? _SpoolsTab(
                      printers: filament!.spoolPrinters!,
                      matchFor: filament.matchFor,
                      scrollController: scrollController,
                    )
                  : _profiles(l10n, t, scrollController),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profiles(
    AppLocalizations l10n,
    DashTokens t,
    ScrollController scrollController,
  ) {
    final base = _showAll ? widget.all : widget.filtered;
    final filament = widget.filament;

    // The options: what the user owns, or the whole catalogue once "All" is
    // on — one chip per value whatever its case ("A1 MINI" and "A1 Mini").
    Set<String> options(Set<String> owned, String? Function(SlicerPreset) of) {
      final seen = <String>{};
      return {
        for (final v in [
          ...owned,
          if (_showAll)
            for (final p in widget.all) ?of(p),
        ])
          if (seen.add(v.toUpperCase())) v,
      };
    }

    final models = filament == null
        ? const <String>{}
        : options(
            filament.ownedModels,
            (p) => presetPrinterModel(p.name, filament.registry),
          );
    final materials = filament == null
        ? const <String>{}
        : options(filament.ownedMaterials, presetMaterial);
    final brands = filament == null
        ? const <String>{}
        : options(filament.ownedBrands, presetBrand);

    // A pick that is not on offer (not owned, "All" off) does not filter.
    String? applied(String? pick, Set<String> from) =>
        pick != null && from.any((o) => o.toUpperCase() == pick.toUpperCase())
        ? pick
        : null;
    final model = applied(_model, models);
    final material = applied(_material, materials);
    final brand = applied(_brand, brands);

    final needle = _query.trim().toLowerCase();
    final items = [
      for (final p in base)
        if (needle.isEmpty || p.name.toLowerCase().contains(needle))
          if (filament == null ||
              (presetFitsPrinterModel(p.name, model, filament.registry) &&
                  presetFitsMaterial(p, material) &&
                  presetFitsBrand(p, brand)))
            p,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DashSpace.gutter),
          child: DashSearchField(
            id: 'slice.search',
            hintText: l10n.sliceSearchHint,
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        if (filament != null) ...[
          _FilterRow(
            id: 'slice.filter_printer',
            label: l10n.sliceFilterPrinter,
            options: models,
            selected: model,
            onSelected: (v) => setState(() => _model = v),
          ),
          _FilterRow(
            id: 'slice.filter_material',
            label: l10n.sliceFilterMaterial,
            options: materials,
            selected: material,
            onSelected: (v) => setState(() => _material = v),
          ),
          _FilterRow(
            id: 'slice.filter_brand',
            label: l10n.sliceFilterBrand,
            options: brands,
            selected: brand,
            onSelected: (v) => setState(() => _brand = v),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DashSpace.gutter,
              DashSpace.xs,
              DashSpace.gutter,
              0,
            ),
            child: Text(
              l10n.sliceProfilesShown(items.length, base.length),
              style: t.labelSoft,
            ),
          ),
        ],
        const SizedBox(height: DashSpace.sm),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(DashSpace.xl),
                    child: Text(
                      widget.filtered.isEmpty && !_showAll
                          ? l10n.sliceOwnedEmpty
                          : l10n.sliceNoPresets,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  controller: scrollController,
                  itemCount: items.length,
                  itemBuilder: (ctx, i) {
                    final p = items[i];
                    return ListTile(
                      dense: true,
                      title: Text(
                        p.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(_sourceLabel(l10n, p.source)),
                      trailing: p.isLocal
                          ? Icon(Icons.star, size: 16, color: t.accentGreen)
                          : null,
                      onTap: () => Navigator.pop<PresetPick>(ctx, (
                        preset: p,
                        spool: null,
                      )),
                    ).tagged('slice.preset_option');
                  },
                ),
        ),
      ],
    );
  }

  String _sourceLabel(AppLocalizations l10n, String source) => switch (source) {
    'local' => l10n.sliceTierLocal,
    'cloud' => l10n.sliceTierCloud,
    'orca_cloud' => l10n.sliceTierOrcaCloud,
    _ => l10n.sliceTierStandard,
  };
}

/// One filter: its label, then a chip per option; the selected one again
/// clears it. Hidden while there is nothing to choose between.
class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.id,
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final String id;
  final String label;
  final Set<String> options;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    final t = DashTokens.of(context);
    final sorted = options.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return Padding(
      padding: const EdgeInsets.only(top: DashSpace.sm),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: DashSpace.gutter),
        child: Row(
          spacing: DashSpace.xs,
          children: [
            SizedBox(
              width: _filterLabelWidth,
              child: Text(label, style: t.labelSoft),
            ),
            for (final o in sorted)
              ChoiceChip(
                label: Text(o),
                selected: selected?.toUpperCase() == o.toUpperCase(),
                onSelected: (on) => onSelected(on ? o : null),
              ).tagged(id),
          ],
        ),
      ),
    );
  }
}

/// Room for the longest of the three labels, so the chips of every row start
/// in one column.
const _filterLabelWidth = 76.0;

/// The online printers' spools, laid out unit by unit (#3172). Only a spool
/// that can be picked gets a tile; an empty slot, an unidentified spool and
/// one with no profile for the printer are a compact line underneath, so they
/// say what is loaded without taking the room.
class _SpoolsTab extends StatelessWidget {
  const _SpoolsTab({
    required this.printers,
    required this.matchFor,
    required this.scrollController,
  });

  final List<LoadedSpoolPrinter> printers;
  final SlicerPreset? Function(LoadedSpoolTray tray) matchFor;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(
        DashSpace.gutter,
        DashSpace.sm,
        DashSpace.gutter,
        DashSpace.xl,
      ),
      children: [
        if (printers.isEmpty)
          Text(l10n.sliceLoadedNoneOfModel, style: t.bodySoft)
        else
          for (final printer in printers)
            _PrinterSpools(printer: printer, matchFor: matchFor),
      ],
    );
  }
}

class _PrinterSpools extends StatelessWidget {
  const _PrinterSpools({required this.printer, required this.matchFor});

  final LoadedSpoolPrinter printer;
  final SlicerPreset? Function(LoadedSpoolTray tray) matchFor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);

    String externalLabel(LoadedSpoolTray tray) => printer.externalHolders > 1
        ? (tray.trayId == 0 ? 'Ext-L' : 'Ext-R')
        : l10n.mappingExternalSpool;

    // Units in the printer's order, AMS-HT together, then the holders.
    final groups = <(String, List<(LoadedSpoolTray, String)>)>[
      for (final unit in printer.ams)
        if (!unit.isAmsHt)
          (
            amsUnitName(unit.id),
            [
              for (final tray in unit.trays)
                (tray, formatSlotLabel(unit.id, tray.trayId, isHt: false)),
            ],
          ),
      if (printer.ams.any((u) => u.isAmsHt))
        (
          'AMS-HT',
          [
            for (final unit in printer.ams)
              if (unit.isAmsHt)
                for (final tray in unit.trays)
                  (tray, formatSlotLabel(unit.id, tray.trayId, isHt: true)),
          ],
        ),
      if (printer.external.isNotEmpty)
        (
          l10n.mappingExternalSpool,
          [for (final tray in printer.external) (tray, externalLabel(tray))],
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: DashSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text([printer.name, ?printer.model].join(' · '), style: t.titleSm),
          const SizedBox(height: DashSpace.sm),
          if (groups.isEmpty) Text(l10n.sliceLoadedNothing, style: t.labelSoft),
          for (final (title, trays) in groups)
            _UnitSpools(
              title: title,
              printer: printer.name,
              trays: [
                for (final (tray, label) in trays)
                  (tray: tray, label: label, match: matchFor(tray)),
              ],
            ),
        ],
      ),
    );
  }
}

typedef _Slot = ({LoadedSpoolTray tray, String label, SlicerPreset? match});

class _UnitSpools extends StatelessWidget {
  const _UnitSpools({
    required this.title,
    required this.printer,
    required this.trays,
  });

  final String title;
  final String printer;
  final List<_Slot> trays;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final usable = [
      for (final s in trays)
        if (s.match != null) s,
    ];
    final unavailable = [
      for (final s in trays)
        if (s.match == null) s,
    ];

    String why(_Slot s) => [
      s.label,
      if (!s.tray.isLoaded)
        s.tray.isUnidentified
            ? l10n.sliceSpoolUnidentified
            : l10n.sliceSpoolEmpty
      else ...[
        ?s.tray.trayType,
        l10n.sliceSpoolNoProfileShort,
      ],
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: DashSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: t.labelSoft),
          const SizedBox(height: DashSpace.xs),
          if (usable.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) {
                // Two to a row, as the web lays a unit out on a phone.
                final width = (constraints.maxWidth - DashSpace.sm) / 2;
                return Wrap(
                  spacing: DashSpace.sm,
                  runSpacing: DashSpace.sm,
                  children: [
                    for (final s in usable)
                      SizedBox(
                        width: width,
                        child: _SpoolTile(slot: s, printer: printer),
                      ),
                  ],
                );
              },
            ),
          if (unavailable.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: DashSpace.sm),
              child: Wrap(
                spacing: DashSpace.xs,
                runSpacing: DashSpace.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(l10n.sliceSpoolsUnavailable, style: t.labelSoft),
                  for (final s in unavailable)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DashSpace.sm,
                        vertical: DashSpace.xs,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: t.subCardBorder),
                      ),
                      child: Text(why(s), style: t.labelSoft),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SpoolTile extends StatelessWidget {
  const _SpoolTile({required this.slot, required this.printer});

  final _Slot slot;
  final String printer;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final (:tray, :label, :match) = slot;
    final preset = match!;
    return Material(
      color: t.subCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: t.subCardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.pop<PresetPick>(context, (
          preset: preset,
          spool: (colour: trayColourHex(tray), label: '$printer · $label'),
        )),
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
                presetDisplayName(preset.name),
                style: t.labelSoft,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    ).tagged('slice.spool_tile');
  }
}
