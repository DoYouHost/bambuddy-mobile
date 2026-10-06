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
import '../../core/printers/nozzle_rack.dart';
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

/// `sameInletWarning`: the one Filament Track Switch inlet every filament of
/// the print comes through, when it is one — then every change in the job is
/// the slow kind, retracted all the way back to its AMS. Null with no switch
/// (no inlets), with an external spool or an unmatched filament in the mix,
/// or with fewer than two filaments.
String? _sameInlet(
  List<FilamentComparison> comparison,
  String? Function(int amsId) inletOf,
) {
  final inlets = <String>{};
  for (final c in comparison) {
    final pick = c.loaded;
    if (pick == null || pick.isExternal) return null;
    final inlet = inletOf(pick.amsId);
    if (inlet == null) return null;
    inlets.add(inlet);
  }
  if (comparison.length < 2 || inlets.length != 1) return null;
  return inlets.single;
}

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
/// [rackChoice] is the nozzle-rack position per filament group the caller
/// holds, and [onRackChoice] makes it pickable from the rows; without it the
/// positions are shown and cannot be changed, as the web's disabled picker.
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
  Map<int, int>? rackChoice,
  void Function(Map<int, int> choice)? onRackChoice,
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
      rackChoice: rackChoice,
      onRackChoice: onRackChoice,
    ),
  );
}

/// What the rows need to offer rack positions: the live rack by position, the
/// plate's filament groups, and the position each rack-bound group prints
/// from.
typedef _Rack = ({
  Map<int, NozzleRackSlot> byPosition,
  Map<int, RackGroup> groups,
  Map<int, int> positions,
});

/// A nozzle as the rack rows name it: `0.4 High flow`. The flow type is
/// dropped when nothing states it, rather than guessed at standard.
String rackNozzleLabel(
  AppLocalizations l10n, {
  required String? diameter,
  required bool? highFlow,
}) {
  final flow = switch (highFlow) {
    true => l10n.nozzleFlowHigh,
    false => l10n.nozzleFlowStandard,
    null => '',
  };
  return [
    nozzleDiameterLabel(diameter),
    flow,
  ].where((part) => part.isNotEmpty).join(' ');
}

bool _fitsGroup(_Rack rack, int position, RackGroup group) {
  final slot = rack.byPosition[position];
  return slot != null &&
      rackSlotFits(
        slot,
        diameter: group.nozzleDiameter,
        volumeType: group.volumeType,
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
    this.rackChoice,
    this.onRackChoice,
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

  final Map<int, int>? rackChoice;
  final void Function(Map<int, int> choice)? onRackChoice;

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

  /// The rack positions picked so far, mirrored for the same reason; the item's
  /// stored ones when the caller keeps none.
  late Map<int, int> _rack = {
    ...?(widget.rackChoice ?? widget.item.nozzleRackChoice),
  };

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
    final rack = _rackOf(status, comparison);
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
        if (_sameInlet(comparison, options.inletOf) case final inlet?)
          Padding(
            padding: const EdgeInsets.only(top: DashSpace.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: t.warningInk,
                ),
                const SizedBox(width: DashSpace.sm),
                Expanded(
                  child: Text(
                    l10n.mappingFtsSameInlet(inlet),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: t.warningInk,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
            rack: rack,
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

  /// `hasRack` and `effectiveRackChoice` (`FilamentMapping.tsx`, #1784): a
  /// rack is offered when the printer reports one and the plate binds a group
  /// to it, and each group shows the position the server would give it around
  /// the picks made so far — or the picks as they stand, when those cannot all
  /// be placed.
  _Rack? _rackOf(PrinterStatus? status, List<FilamentComparison> comparison) {
    final slots = status?.nozzleRack;
    final groups = <int, RackGroup>{
      for (final c in comparison)
        if ((c.requirement.groupId, c.requirement.group) case (
          final id?,
          final group?,
        ))
          id: group,
    };
    final hasRack = slots?.any((s) => (s.id ?? 0) >= 16) ?? false;
    if (!hasRack || !groups.values.any((g) => g.onRack)) return null;
    return (
      byPosition: rackByPosition(slots),
      groups: groups,
      positions: autoAssignRackPositions(slots, groups, _rack) ?? _rack,
    );
  }

  /// The row's rack picker, `R2 · 0.4`: the position the group prints from
  /// and the nozzle sitting there.
  Widget _rackButton(_Rack rack, int groupId, RackGroup group) {
    final l10n = _l10n;
    final theme = Theme.of(context);
    final position = rack.positions[groupId];
    final diameter = nozzleDiameterLabel(
      position == null ? null : rack.byPosition[position]?.nozzleDiameter,
    );
    final enabled = widget.onRackChoice != null;
    return Tooltip(
      message: l10n.mappingRackPositionHint,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: enabled ? () => _pickRackPosition(rack, groupId, group) : null,
        child: Container(
          padding: const EdgeInsets.only(left: DashSpace.xs),
          decoration: BoxDecoration(
            border: Border.all(
              color: enabled
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                [
                  position == null ? '–' : l10n.mappingRackSlot(position),
                  if (diameter.isNotEmpty) diameter,
                ].join(' · '),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Icon(Icons.arrow_drop_down, size: 18),
            ],
          ),
        ),
      ).tagged('queue_mapping.rack'),
    );
  }

  /// All six positions, as the web lists them (`rackOptionsForGroup`): one the
  /// group cannot print from is greyed out with the reason under it — the
  /// web's tooltip, which a touch screen has no hover for. A position another
  /// group holds is not refused; the server does that at dispatch, and says
  /// why on the item.
  Future<void> _pickRackPosition(
    _Rack rack,
    int groupId,
    RackGroup group,
  ) async {
    final l10n = _l10n;
    final theme = Theme.of(context);
    final current = rack.positions[groupId];
    final needs = rackNozzleLabel(
      l10n,
      diameter: group.nozzleDiameter,
      highFlow: highFlowFromName(group.volumeType),
    );
    // All six fit without a scroll on a phone only past the 9/16 cap.
    final picked = await dashSheet<int>(
      context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                l10n.mappingRackPosition,
                style: theme.textTheme.titleMedium,
              ),
              subtitle: Text(
                '${l10n.mappingRackNeeds(needs)} '
                '${l10n.mappingRackPositionHint}',
              ),
            ),
            for (final position in rackPositions)
              _rackOption(ctx, rack, position, group, needs, current),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    // Every group is written back, not just this one, as the web does: left
    // implicit, the others could be re-assigned around the new pick and move a
    // hotend the operator had already seen.
    setState(() => _rack = {...rack.positions, groupId: picked});
    widget.onRackChoice?.call(_rack);
  }

  Widget _rackOption(
    BuildContext ctx,
    _Rack rack,
    int position,
    RackGroup group,
    String needs,
    int? current,
  ) {
    final l10n = _l10n;
    final slot = rack.byPosition[position];
    final empty = slot == null || slot.isEmpty;
    final diameter = nozzleDiameterLabel(slot?.nozzleDiameter);
    final eligible = _fitsGroup(rack, position, group);
    final reason = eligible
        ? null
        : empty
        ? l10n.mappingRackEmptyPosition
        : l10n.mappingRackWrongNozzle(
            rackNozzleLabel(
              l10n,
              diameter: slot.nozzleDiameter,
              highFlow: highFlowFromCode(slot.nozzleType),
            ),
            needs,
          );
    return ListTile(
      enabled: eligible,
      title: Text(
        [
          l10n.mappingRackSlot(position),
          if (diameter.isNotEmpty) diameter,
        ].join(' · '),
      ),
      subtitle: reason == null ? null : Text(reason),
      trailing: current == position
          ? Icon(Icons.check, color: Theme.of(ctx).colorScheme.primary)
          : null,
      onTap: () => Navigator.pop(ctx, position),
    ).tagged(
      'queue_mapping.rack_position_$position',
      selected: current == position,
    );
  }

  /// Under the row, kept from the app's own rack section: a pick the live
  /// rack no longer fits — the server fails the item at dispatch rather than
  /// print from another nozzle — and a group no position can take.
  (String, Color)? _rackWarning(
    _Rack rack,
    int groupId,
    RackGroup group,
    DashTokens t,
  ) {
    final picked = _rack[groupId];
    if (picked != null && !_fitsGroup(rack, picked, group)) {
      return (_l10n.queueEditRackPickStale, t.dangerInk);
    }
    if (rackPositions.any((p) => _fitsGroup(rack, p, group))) return null;
    return (
      _l10n.queueEditRackNoFit(
        rackNozzleLabel(
          _l10n,
          diameter: group.nozzleDiameter,
          highFlow: highFlowFromName(group.volumeType),
        ),
      ),
      t.warningInk,
    );
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
    required _Rack? rack,
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
    final groupId = req.groupId;
    final group = groupId == null ? null : rack?.groups[groupId];
    // On a rack plate the group decides the badge (`FilamentMapping.tsx`): a
    // picker for a rack-bound group, `L` for one on the fixed hotend.
    final Widget? lead = switch (group) {
      RackGroup(onRack: true) => _rackButton(rack!, groupId!, group),
      RackGroup() => _Badge(l10n.extruderLeftShort),
      null => nozzle == null ? null : _Badge(nozzle),
    };
    final rackWarning = group != null && group.onRack
        ? _rackWarning(rack!, groupId!, group, t)
        : null;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: DashSpace.xs),
      child: ListTile(
        leading: Tooltip(
          message: l10n.mappingRequired(name, requiredLabel),
          child: _swatch(theme, req.color, 28),
        ),
        title: Row(
          children: [
            if (lead != null) ...[lead, const SizedBox(width: DashSpace.xs)],
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
            if (rackWarning != null)
              Text(rackWarning.$1, style: TextStyle(color: rackWarning.$2)),
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
