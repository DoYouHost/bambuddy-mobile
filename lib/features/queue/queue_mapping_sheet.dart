import 'package:app_util/app_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ams/color_names.dart';
import '../../core/ams/filament_mapping.dart';
import '../../core/ams/slot_addressing.dart';
import '../../core/diagnostics/log_tag_material.dart';
import '../../core/models/ams_filament_preset.dart';
import '../../core/models/archive.dart';
import '../../core/models/filament_requirement.dart';
import '../../core/models/inventory.dart';
import '../../core/models/printer_status.dart';
import '../../core/models/queue_item.dart';
import '../../core/theme/dash_theme.dart';
import '../../data/printers_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../inventory/inventory_providers.dart';
import '../slicer/slice_providers.dart';

/// The printer's live status — the only source of slots the web's mapping
/// reads (`useFilamentMapping.ts::buildLoadedFilaments`): it is what the
/// firmware resolves the mapping against, and a slot offered from anywhere
/// else is how a job gets rejected with "unable to fetch AMS mapping".
final mappingStatusProvider = FutureProvider.autoDispose
    .family<PrinterStatus?, int>(
      (ref, printerId) =>
          ref.watch(printersRepositoryProvider).fetchStatus(printerId),
    );

/// What the inventory knows of [printerId]'s slots: the grams the "prefer
/// lowest remaining" sort reads first, and the spool names the slots go by.
final mappingInventoryRemainProvider = FutureProvider.autoDispose
    .family<SlotInventory, int>(
      (ref, printerId) =>
          ref.watch(printersRepositoryProvider).fetchInventoryRemain(printerId),
    );

/// `filament_id` → name, the way the web names a sliced filament
/// (`useFilamentLabels.ts`): Bambu's built-in table, then the user's cloud
/// presets, which win. Either may be missing; the 3MF's type stands in then.
final mappingFilamentNamesProvider =
    FutureProvider.autoDispose<Map<String, String>>((ref) async {
      final repo = ref.watch(amsSlotConfigRepositoryProvider);
      final (builtin, cloud) = await (
        repo.builtinFilaments().catchError((Object _) => <AmsFilamentPreset>[]),
        repo.cloudFilamentNames(),
      ).wait;
      return {
        for (final f in builtin)
          if (f.id.isNotEmpty) f.id: f.name,
        ...cloud,
      };
    });

/// The server's colour catalogue; empty when it cannot be read, and names
/// then come from the hue alone.
final mappingColorCatalogProvider = FutureProvider.autoDispose<ColorCatalog>(
  (ref) => ref
      .watch(amsSlotConfigRepositoryProvider)
      .colorCatalog()
      .catchError((Object _) => ColorCatalog.empty),
);

/// The catalogue's name for a hex within a material, which the flat map can
/// get wrong where one hex names two colours (`/inventory/colors/by-material`).
final mappingColorByMaterialProvider = FutureProvider.autoDispose
    .family<String?, ({String hex, String material})>(
      (ref, key) => ref
          .watch(amsSlotConfigRepositoryProvider)
          .colorByMaterial(key.hex, key.material)
          .catchError((Object _) => null),
    );

/// `getColorName`: the catalogue's name, else the hue family's.
String mappingColorName(
  AppLocalizations l10n,
  ColorCatalog catalog,
  String? hex, {
  String? material,
}) =>
    catalog.nameOf(hex, material: material) ??
    switch (colorFamily(hex)) {
      ColorFamily.red => l10n.colorFamilyRed,
      ColorFamily.orange => l10n.colorFamilyOrange,
      ColorFamily.yellow => l10n.colorFamilyYellow,
      ColorFamily.green => l10n.colorFamilyGreen,
      ColorFamily.cyan => l10n.colorFamilyCyan,
      ColorFamily.blue => l10n.colorFamilyBlue,
      ColorFamily.purple => l10n.colorFamilyPurple,
      ColorFamily.pink => l10n.colorFamilyPink,
      ColorFamily.brown => l10n.colorFamilyBrown,
      ColorFamily.white => l10n.colorFamilyWhite,
      ColorFamily.lightGray => l10n.colorFamilyLightGray,
      ColorFamily.gray => l10n.colorFamilyGray,
      ColorFamily.darkGray => l10n.colorFamilyDarkGray,
      ColorFamily.black => l10n.colorFamilyBlack,
      ColorFamily.clear => l10n.colorFamilyClear,
      null => l10n.colorFamilyUnknown,
    };

/// `extractMaterialHint`: "Bambu PLA Matte" → "PLA Matte", the material the
/// colour lookup is narrowed by.
String _materialHint(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  return parts.length <= 1 ? name.trim() : parts.skip(1).join(' ');
}

/// The archive a queued reprint comes from, for the mapping its slicer sent.
final mappingArchiveProvider = FutureProvider.autoDispose.family<Archive?, int>(
  (ref, archiveId) => ref
      .watch(archiveRepositoryProvider)
      .byId(archiveId)
      .then<Archive?>((a) => a)
      .catchError((Object _) => null),
);

/// Manual picks from a stored mapping, as the web's edit form seeds them
/// (`PrintModal/index.tsx`): `slot_id` → global tray id, `-1` left to the
/// match.
Map<int, int> _manualFrom(List<int>? mapping) => {
  for (final (i, global) in (mapping ?? const <int>[]).indexed)
    if (global != -1) i + 1: global,
};

List<FilamentComparison> _compare(
  List<FilamentRequirement> requirements,
  PrinterStatus? status,
  List<LoadedFilament> loaded,
  Map<int, int> manual,
  Map<int, double>? remain,
  bool? preferLowestSetting,
) => buildFilamentComparison(
  requirements,
  loaded,
  manual,
  preferLowest: effectivePreferLowest(
    preferLowestSetting,
    status?.amsFilamentBackup,
  ),
  inventoryByTrayId: remain,
  ftsActive: status?.filaSwitch?.installed ?? false,
);

/// The `ams_mapping` the web sends when it saves or adds a job for
/// [printerId] (`getMappingForPrinter`): the plate's [requirements] matched
/// afresh against the live status, starting from [startFrom]. Null when the
/// printer reports no loaded slot — the web then sends no mapping at all.
Future<List<int>?> queueMappingToSend({
  required List<FilamentRequirement> requirements,
  required PrintersRepository printers,
  required int printerId,
  List<int>? startFrom,
  bool? preferLowestSetting,
}) async {
  final (status, remain) = await (
    printers.fetchStatus(printerId),
    printers.fetchInventoryRemain(printerId),
  ).wait;
  final loaded = buildLoadedFilaments(status);
  if (loaded.isEmpty) return null;
  return buildAmsMapping(
    _compare(
      requirements,
      status,
      loaded,
      _manualFrom(startFrom),
      remain.grams,
      preferLowestSetting,
    ),
  );
}

/// Opens the filament-mapping screen for [item] against [printerId], matched
/// as the web matches (`lib/core/ams/filament_mapping.dart`) and starting from
/// the item's stored mapping. Returns the whole `ams_mapping` the web would
/// send — `-1` for a filament no slot matches — an empty list when the printer
/// reports nothing to map to, or null if dismissed. Persisting/starting is the caller's job — [confirmLabel]
/// is the action verb on the button (e.g. "Start" or "Save").
/// [printerName] names [printerId] in the "no AMS" note. Pass it whenever the
/// caller knows the printer currently selected in the form — the item's own
/// `printer_name` is the one it was filed under, which is stale after a switch
/// and absent entirely on a draft.
/// [forceColorMatch] and [onForceColorMatch] put the web's per-filament
/// "force colour match" box on each row.
/// [startFrom] is the mapping to start from when the caller holds a newer one
/// than the item's stored mapping — the edit form after a pick, or `[]` once a
/// printer or plate switch dropped it, as the web drops its picks then.
/// [plateId] overrides the plate the slots are read for — pass it when the
/// caller holds a newer plate than the item does, which is the queue-create
/// form after the user picked one. Null falls back to the item's own plate.
Future<List<int>?> showQueueMappingSheet(
  BuildContext context, {
  required QueueItem item,
  required int printerId,
  required String confirmLabel,
  String? printerName,
  int? plateId,
  List<int>? startFrom,
  Map<int, bool>? forceColorMatch,
  void Function(int slotId, bool value)? onForceColorMatch,
}) {
  return dashSheet<List<int>>(
    context,
    builder: (_) => _MappingSheet(
      item: item,
      printerId: printerId,
      confirmLabel: confirmLabel,
      printerName: printerName,
      plateId: plateId,
      startFrom: startFrom,
      forceColorMatch: forceColorMatch,
      onForceColorMatch: onForceColorMatch,
    ),
  );
}

class _MappingSheet extends ConsumerStatefulWidget {
  const _MappingSheet({
    required this.item,
    required this.printerId,
    required this.confirmLabel,
    this.printerName,
    this.plateId,
    this.startFrom,
    this.forceColorMatch,
    this.onForceColorMatch,
  });
  final QueueItem item;
  final int printerId;
  final String confirmLabel;
  final String? printerName;
  final int? plateId;
  final List<int>? startFrom;

  /// Per-slot "force colour match" (#1717 on the web): shown when the caller
  /// keeps the flags, which only the edit form does.
  final Map<int, bool>? forceColorMatch;
  final void Function(int slotId, bool value)? onForceColorMatch;

  @override
  ConsumerState<_MappingSheet> createState() => _MappingSheetState();
}

class _MappingSheetState extends ConsumerState<_MappingSheet> {
  /// `slot_id` → global tray id the user picked, seeded from the stored
  /// mapping as the web's edit form is (`PrintModal/index.tsx`); every other
  /// slot is auto-matched.
  late final Map<int, int> _manual = _manualFrom(
    widget.startFrom ?? widget.item.amsMapping,
  );

  /// The caller's flags, mirrored here: this route is not rebuilt by the
  /// form's own state.
  late final Map<int, bool> _force = {...?widget.forceColorMatch};

  /// The slots the slicer-mapping toggle wrote into [_manual], so turning it
  /// off takes back exactly those and no pick made by hand
  /// (`FilamentMapping.tsx`); empty while it is off.
  List<int> _fromSlicer = const [];
  bool _rereading = false;

  AppLocalizations get _l10n => AppLocalizations.of(context);
  bool get _isArchive => widget.item.archiveId != null;
  int? get _sourceId => widget.item.archiveId ?? widget.item.libraryFileId;

  /// Which plate's slots to show. The caller's plate wins over the item's — see
  /// [showQueueMappingSheet] — and 1 is the plate the print starts on when
  /// neither names one (`item.plate_id or 1`, `print_scheduler.py`).
  int get _plateId => widget.plateId ?? widget.item.plateId ?? 1;

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n;
    final theme = Theme.of(context);
    final sourceId = _sourceId;

    Widget wrap(Widget child) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          DashSpace.gutter,
          0,
          DashSpace.gutter,
          DashSpace.lg + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: child,
      ),
    );

    if (sourceId == null) {
      return logTag(
        'sheet.queue_mapping',
        wrap(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: DashSpace.xl),
            child: Text(l10n.mappingNoSlots),
          ),
        ),
      );
    }

    final reqsAsync = ref.watch(
      printRequirementsProvider((
        isArchive: _isArchive,
        id: sourceId,
        plate: _plateId,
      )),
    );
    final statusAsync = ref.watch(mappingStatusProvider(widget.printerId));
    // Neither holds the sheet: like the web's queries they only reorder
    // slots once they answer.
    final remain = ref
        .watch(mappingInventoryRemainProvider(widget.printerId))
        .valueOrNull;
    final preferLowest = ref.watch(preferLowestFilamentProvider).valueOrNull;
    // Loads the shelf while the sheet is open, for the picker's grams — a
    // listen, as nothing on this sheet shows them.
    ref.listen(assignedSpoolsProvider(widget.printerId), (_, _) {});

    // A re-read keeps what is on screen until the new answer is in.
    if (!reqsAsync.hasValue && reqsAsync.isLoading ||
        !statusAsync.hasValue && statusAsync.isLoading) {
      return wrap(
        const Padding(
          padding: EdgeInsets.all(DashSpace.xxl),
          child: DashLoading(),
        ),
      );
    }
    final status = statusAsync.valueOrNull;
    final loaded = buildLoadedFilaments(status);
    final comparison = _compare(
      reqsAsync.valueOrNull ?? const [],
      status,
      loaded,
      _manual,
      remain?.grams,
      preferLowest,
    );
    return wrap(
      _content(
        theme,
        comparison,
        loaded,
        status: status,
        spools: remain?.spools ?? const {},
      ),
    );
  }

  Widget _content(
    ThemeData theme,
    List<FilamentComparison> comparison,
    List<LoadedFilament> loaded, {
    required PrinterStatus? status,
    required Map<int, SlotSpool> spools,
  }) {
    final l10n = _l10n;
    if (comparison.isEmpty) {
      // No per-slot info — nothing to map; let the caller proceed with defaults.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: DashSpace.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: DashSpace.lg),
              child: Text(l10n.mappingNoSlots),
            ),
            _confirmButton(const []),
          ],
        ),
      );
    }

    final t = DashTokens.of(context);
    final catalog =
        ref.watch(mappingColorCatalogProvider).valueOrNull ??
        ColorCatalog.empty;
    final names =
        ref.watch(mappingFilamentNamesProvider).valueOrNull ?? const {};
    final options = _SlotOptions(
      l10n: l10n,
      catalog: catalog,
      spools: spools,
      dualExternal: (status?.vtTray?.length ?? 0) > 1,
      // `ftsInletForAms`: the inlet an AMS is plumbed into, when a Filament
      // Track Switch is fitted.
      inletOf: (amsId) {
        if (!(status?.filaSwitch?.installed ?? false)) return null;
        return status?.amsSwitchInlet?[amsId];
      },
    );
    // `FilamentMapping.tsx`: the nozzle badge shows when the file was sliced
    // for two nozzles.
    final dualNozzle = comparison.any((c) => c.requirement.nozzleId != null);
    final (
      summary,
      summaryInk,
    ) = comparison.any((c) => c.status == FilamentMatch.mismatch)
        ? (l10n.mappingStatusTypeNotFound, t.dangerInk)
        : comparison.any((c) => c.status == FilamentMatch.typeOnly)
        ? (l10n.mappingStatusColorMismatch, t.warningInk)
        : (l10n.mappingStatusReady, t.accentGreenInk);

    return ListView(
      shrinkWrap: true,
      children: [
        Text(l10n.queueFilamentMapping, style: theme.textTheme.titleLarge),
        const SizedBox(height: DashSpace.xs),
        Text(
          widget.item.displayName,
          style: theme.textTheme.bodySmall,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: DashSpace.sm),
        Row(
          children: [
            Icon(Icons.circle, size: 10, color: summaryInk),
            const SizedBox(width: DashSpace.sm),
            Expanded(
              child: Text(
                summary,
                style: theme.textTheme.labelLarge?.copyWith(color: summaryInk),
              ),
            ),
          ],
        ),
        _actions(comparison),
        if (loaded.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: DashSpace.sm),
            child: Text(
              l10n.mappingNoAms(
                widget.printerName ?? widget.item.printerName ?? '',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: DashSpace.xs),
            child: Text(
              l10n.mappingTapToChange,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: DashSpace.md),
        for (final c in comparison)
          _slotRow(
            theme,
            t,
            c,
            loaded,
            options,
            name: _filamentName(c.requirement, names),
            dualNozzle: dualNozzle,
          ),
        const SizedBox(height: DashSpace.lg),
        // The web sends no mapping when the printer reports no slot, which
        // leaves the stored one alone and the start to the server.
        _confirmButton(
          loaded.isEmpty ? const [] : buildAmsMapping(comparison) ?? const [],
        ),
      ],
    );
  }

  /// The web's two header buttons: the slicer's own mapping, offered only for
  /// the printer it was resolved against (`resolveArchiveSlicerAmsMapping`),
  /// and a re-read of the AMS.
  Widget _actions(List<FilamentComparison> comparison) {
    final l10n = _l10n;
    final archiveId = widget.item.archiveId;
    final saved = archiveId == null
        ? null
        : ref
              .watch(mappingArchiveProvider(archiveId))
              .valueOrNull
              ?.slicerAmsMapping;
    final slicer = saved?.printerId == widget.printerId ? saved!.mapping : null;
    return Padding(
      padding: const EdgeInsets.only(top: DashSpace.sm),
      child: Wrap(
        spacing: DashSpace.sm,
        runSpacing: DashSpace.sm,
        children: [
          if (slicer != null)
            Tooltip(
              message: l10n.mappingUseSlicerHint,
              child: FilterChip(
                label: Text(l10n.mappingUseSlicer),
                selected: _fromSlicer.isNotEmpty,
                onSelected: (_) => _toggleSlicer(slicer, comparison),
              ).tagged('queue_mapping.use_slicer'),
            ),
          ActionChip(
            avatar: _rereading
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 18),
            label: Text(l10n.mappingReRead),
            onPressed: _rereading ? null : _reread,
          ).tagged('queue_mapping.reread'),
        ],
      ),
    );
  }

  /// `toggleArchiveMapping`: on, every filament the slicer resolved to a
  /// slot (`>= 0`) takes that slot as a manual pick; off, those picks go.
  void _toggleSlicer(List<int> slicer, List<FilamentComparison> comparison) {
    setState(() {
      if (_fromSlicer.isNotEmpty) {
        _fromSlicer.forEach(_manual.remove);
        _fromSlicer = const [];
        return;
      }
      final applied = <int>[];
      for (final c in comparison) {
        final slotId = c.requirement.slotId;
        final idx = slotId - 1;
        if (slotId > 0 && idx < slicer.length && slicer[idx] >= 0) {
          _manual[slotId] = slicer[idx];
          applied.add(slotId);
        }
      }
      _fromSlicer = applied;
    });
  }

  /// `handleRefresh`: ask the printer to report everything again, give it a
  /// moment, then read the status anew. The answer to the request itself
  /// does not matter — a disconnected printer refuses it, and the read
  /// still shows what there is.
  Future<void> _reread() async {
    setState(() => _rereading = true);
    try {
      await ref
          .read(printerCommandsRepositoryProvider)
          .refreshStatus(widget.printerId);
    } on Object {
      // A hint, as everywhere else it is sent.
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    ref.invalidate(mappingStatusProvider(widget.printerId));
    setState(() => _rereading = false);
  }

  /// `useFilamentLabels`: the sliced filament's name by its `tray_info_idx`,
  /// else the 3MF's type.
  String _filamentName(FilamentRequirement req, Map<String, String> names) {
    final idx = req.trayInfoIdx;
    final named = idx == null || idx.isEmpty ? null : names[idx];
    return named ?? req.type ?? '';
  }

  Widget _confirmButton(List<int> mapping) => FilledButton.icon(
    icon: const Icon(Icons.check),
    label: Text(widget.confirmLabel),
    onPressed: () => Navigator.pop(context, mapping),
  ).tagged('queue_mapping.confirm');

  Widget _slotRow(
    ThemeData theme,
    DashTokens t,
    FilamentComparison c,
    List<LoadedFilament> loaded,
    _SlotOptions options, {
    required String name,
    required bool dualNozzle,
  }) {
    final l10n = _l10n;
    final req = c.requirement;
    final pick = c.loaded;
    final hex = req.color ?? '';
    // `useFilamentLabels`: the catalogue's name within the filament's own
    // material, else the flat lookup.
    final byMaterial = hex.isEmpty
        ? null
        : ref
              .watch(
                mappingColorByMaterialProvider((
                  hex: hex,
                  material: _materialHint(name),
                )),
              )
              .valueOrNull;
    final required = byMaterial ?? mappingColorName(l10n, options.catalog, hex);
    final (requiredLabel, loadedLabel) = disambiguateColorNames(
      (name: required, hex: hex),
      (name: pick == null ? null : options.colorOf(pick), hex: pick?.color),
    );
    final warning = switch (c.status) {
      FilamentMatch.match => null,
      FilamentMatch.typeOnly => (
        l10n.mappingSameTypeOtherColor(requiredLabel, loadedLabel),
        t.warningInk,
      ),
      FilamentMatch.mismatch => (l10n.mappingTypeNotLoaded, t.dangerInk),
    };
    final nozzle = !dualNozzle
        ? null
        : switch (req.nozzleId) {
            1 => l10n.extruderLeftShort,
            0 => l10n.extruderRightShort,
            _ => null,
          };
    final grams = req.usedGrams;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: DashSpace.xs),
      child: ListTile(
        leading: Tooltip(
          message: l10n.mappingRequired(name, requiredLabel),
          child: _swatch(theme, req.color, 28),
        ),
        title: Row(
          children: [
            if (nozzle != null) ...[
              _Badge(nozzle),
              const SizedBox(width: DashSpace.xs),
            ],
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge,
              ),
            ),
            if (grams != null)
              Text(
                ' (${l10n.inventoryUsageWeight(grams.toStringAsFixed(0))})',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              pick == null ? l10n.mappingPickTray : options.labelOf(pick),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (c.isManual) Text(l10n.mappingManual),
            if (warning != null)
              Text(warning.$1, style: TextStyle(color: warning.$2)),
            if (widget.onForceColorMatch case final onForce?
                when req.slotId > 0)
              Row(
                children: [
                  Checkbox(
                    value: _force[req.slotId] ?? false,
                    onChanged: (v) {
                      setState(() => _force[req.slotId] = v ?? false);
                      onForce(req.slotId, v ?? false);
                    },
                  ).tagged('queue_mapping.force_color'),
                  const Icon(Icons.palette_outlined, size: 16),
                  const SizedBox(width: DashSpace.xs),
                  Flexible(child: Text(l10n.queueEditForceColorMatch)),
                ],
              ),
          ],
        ),
        trailing: Icon(
          warning == null ? Icons.check_circle : Icons.warning_amber_rounded,
          color: warning?.$2 ?? t.accentGreenInk,
        ),
        onTap: loaded.isEmpty || req.slotId <= 0
            ? null
            : () => _pickTray(req, pick, loaded, options),
        // The material the *file* asks for, not the tray picked for it: a
        // mapping report is about the two disagreeing.
      ).taggedMaterial('queue_mapping.slot', req.type),
    );
  }

  /// Every loaded slot is offered for every filament, whichever nozzle it
  /// feeds (#1722 on the web); the first entry drops the pick and lets the
  /// match decide again, as the web's empty choice does.
  Future<void> _pickTray(
    FilamentRequirement req,
    LoadedFilament? current,
    List<LoadedFilament> loaded,
    _SlotOptions options,
  ) async {
    const auto = -1;
    final theme = Theme.of(context);
    final wanted = normalizeColorForCompare(req.color);
    final picked = await dashSheet<int>(
      context,
      scrollControlled: false,
      builder: (ctx) => SafeArea(
        // A Consumer, not the sheet's own ref: this is a route of its own,
        // which a watch in the sheet would not rebuild.
        child: Consumer(
          builder: (context, ref, _) {
            final assigned = ref.watch(
              assignedSpoolsProvider(widget.printerId),
            );
            Spool? spoolOf(LoadedFilament f) => assigned.builtInAt(
              f.isExternal ? externalHolderUnit : f.amsId,
              f.trayId,
            );

            return ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  title: Text(_l10n.mappingPickTray),
                  onTap: () => Navigator.pop(ctx, auto),
                ).tagged('queue_mapping.tray_auto'),
                for (final f in loaded)
                  ListTile(
                    leading: _swatch(theme, f.color, 28),
                    title: Text(options.labelOf(f)),
                    subtitle: Text(
                      [
                        // What the web's mapping shows: the built-in
                        // inventory's spool for the slot, in grams, and no
                        // percent (`FilamentMapping.tsx`,
                        // trayRemainingWeightMap).
                        if (spoolOf(f) case final spool?)
                          _l10n.inventoryRemaining(
                            spool.remainingWeight.toStringAsFixed(0),
                          ),
                        ?options.inletBadge(f),
                        if (wanted.isNotEmpty &&
                            normalizeColorForCompare(f.color) == wanted)
                          _l10n.mappingExactColor,
                      ].join(' · '),
                    ),
                    trailing: current?.globalTrayId == f.globalTrayId
                        ? Icon(Icons.check, color: theme.colorScheme.primary)
                        : null,
                    onTap: () => Navigator.pop(ctx, f.globalTrayId),
                  ).taggedMaterial('queue_mapping.tray_option', f.type),
              ],
            );
          },
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      if (picked == auto) {
        _manual.remove(req.slotId);
      } else {
        _manual[req.slotId] = picked;
      }
    });
  }

  Widget _swatch(ThemeData theme, String? hex, double size) {
    final c = colorFromHex(hex);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c ?? theme.colorScheme.surfaceContainerHighest,
        shape: BoxShape.circle,
        border: Border.all(color: theme.dividerColor),
      ),
      child: c == null
          ? Icon(
              Icons.help_outline,
              size: size * 0.6,
              color: theme.colorScheme.onSurfaceVariant,
            )
          : null,
    );
  }
}

/// How a loaded slot reads in the mapping (`FilamentMapping.tsx`):
/// `A1: Devil Design PLA Basic (Orange)` — the slot, the spool bound to it or
/// the printer's own name for the filament, and its colour.
class _SlotOptions {
  const _SlotOptions({
    required this.l10n,
    required this.catalog,
    required this.spools,
    required this.dualExternal,
    required this.inletOf,
  });

  final AppLocalizations l10n;
  final ColorCatalog catalog;
  final Map<int, SlotSpool> spools;
  final bool dualExternal;
  final String? Function(int amsId) inletOf;

  String slotOf(LoadedFilament f) {
    if (f.isExternal) {
      // `useFilamentMapping.ts`: the letters on the machine, not translated.
      if (!dualExternal) return l10n.mappingExternalSpool;
      return f.globalTrayId == externalTrayIdBase ? 'Ext-L' : 'Ext-R';
    }
    return formatSlotLabel(f.amsId, f.trayId, isHt: f.isHt);
  }

  String colorOf(LoadedFilament f) {
    final bound = spools[f.globalTrayId]?.colorName;
    if (bound != null && bound.isNotEmpty) return bound;
    return mappingColorName(
      l10n,
      catalog,
      f.color,
      material: f.traySubBrands.isEmpty ? null : f.traySubBrands,
    );
  }

  String labelOf(LoadedFilament f) {
    final what =
        spools[f.globalTrayId]?.name ??
        (f.traySubBrands.isNotEmpty ? f.traySubBrands : f.type);
    return '${slotOf(f)}: $what (${colorOf(f)})';
  }

  /// `[L]`/`[R]` for the Filament Track Switch inlet a slot's AMS feeds —
  /// In-A reads as L, In-B as R, as the printer card letters them.
  String? inletBadge(LoadedFilament f) {
    if (f.isExternal) return null;
    return switch (inletOf(f.amsId)) {
      'A' => '[L]',
      'B' => '[R]',
      _ => null,
    };
  }
}

/// The one-letter nozzle badge of a filament row.
class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DashSpace.xs),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: theme.textTheme.labelSmall),
    );
  }
}
