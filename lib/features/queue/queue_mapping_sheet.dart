import 'package:app_util/app_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ams/filament_mapping.dart';
import '../../core/ams/slot_addressing.dart';
import '../../core/diagnostics/log_tag_material.dart';
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

/// Grams left on the spools bound to [printerId]'s slots, by global tray id —
/// the first tier of the "prefer lowest remaining" sort.
final mappingInventoryRemainProvider = FutureProvider.autoDispose
    .family<Map<int, double>, int>(
      (ref, printerId) =>
          ref.watch(printersRepositoryProvider).fetchInventoryRemain(printerId),
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
      remain,
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
  });
  final QueueItem item;
  final int printerId;
  final String confirmLabel;
  final String? printerName;
  final int? plateId;
  final List<int>? startFrom;

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

    if (reqsAsync.isLoading || statusAsync.isLoading) {
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
      remain,
      preferLowest,
    );
    return wrap(
      _content(
        theme,
        comparison,
        loaded,
        dualExternal: (status?.vtTray?.length ?? 0) > 1,
      ),
    );
  }

  Widget _content(
    ThemeData theme,
    List<FilamentComparison> comparison,
    List<LoadedFilament> loaded, {
    required bool dualExternal,
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

    String label(LoadedFilament f) => _trayLabel(f, dualExternal: dualExternal);

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
          ),
        const SizedBox(height: DashSpace.md),
        for (final c in comparison) _slotRow(theme, c, loaded, label),
        const SizedBox(height: DashSpace.lg),
        // The web sends no mapping when the printer reports no slot, which
        // leaves the stored one alone and the start to the server.
        _confirmButton(
          loaded.isEmpty ? const [] : buildAmsMapping(comparison) ?? const [],
        ),
      ],
    );
  }

  Widget _confirmButton(List<int> mapping) => FilledButton.icon(
    icon: const Icon(Icons.check),
    label: Text(widget.confirmLabel),
    onPressed: () => Navigator.pop(context, mapping),
  ).tagged('queue_mapping.confirm');

  Widget _slotRow(
    ThemeData theme,
    FilamentComparison c,
    List<LoadedFilament> loaded,
    String Function(LoadedFilament) label,
  ) {
    final l10n = _l10n;
    final req = c.requirement;
    final pick = c.loaded;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: DashSpace.xs),
      child: ListTile(
        // Show the chosen filament's colour once mapped, else the file's
        // required colour.
        leading: _swatch(theme, pick?.color ?? req.color, 28),
        title: Text(
          l10n.sliceFilamentNumbered('${req.slotId}'),
          style: theme.textTheme.labelMedium,
        ),
        subtitle: Text(
          pick == null ? l10n.mappingPickTray : '${label(pick)} · ${pick.type}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: loaded.isEmpty || req.slotId <= 0
            ? null
            : () => _pickTray(req.slotId, pick, loaded, label),
        // The material the *file* asks for, not the tray picked for it: a
        // mapping report is about the two disagreeing.
      ).taggedMaterial('queue_mapping.slot', req.type),
    );
  }

  /// Every loaded slot is offered for every filament, whichever nozzle it
  /// feeds (#1722 on the web); the first entry drops the pick and lets the
  /// match decide again, as the web's empty choice does.
  Future<void> _pickTray(
    int slotId,
    LoadedFilament? current,
    List<LoadedFilament> loaded,
    String Function(LoadedFilament) label,
  ) async {
    const auto = -1;
    final theme = Theme.of(context);
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
                    title: Text(label(f)),
                    subtitle: Text(
                      [
                        f.type,
                        // What the web's mapping shows: the built-in
                        // inventory's spool for the slot, in grams, and no
                        // percent (`FilamentMapping.tsx`,
                        // trayRemainingWeightMap).
                        if (spoolOf(f) case final spool?)
                          _l10n.inventoryRemaining(
                            spool.remainingWeight.toStringAsFixed(0),
                          ),
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
        _manual.remove(slotId);
      } else {
        _manual[slotId] = picked;
      }
    });
  }

  String _trayLabel(LoadedFilament f, {required bool dualExternal}) {
    // `useFilamentMapping.ts`: Ext-L/Ext-R when the printer reports two
    // holders — the letters on the machine, not translated.
    if (f.isExternal && dualExternal) {
      return f.globalTrayId == externalTrayIdBase ? 'Ext-L' : 'Ext-R';
    }
    if (f.isExternal) return _l10n.mappingExternalSpool;
    final slot = localSlotOf(f.globalTrayId);
    return amsSlotName(slot.amsId, slot.trayId);
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
