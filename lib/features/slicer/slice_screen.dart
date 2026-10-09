import 'dart:async';

import 'package:app_util/app_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/duration_format.dart';
import '../common/api_failure_snack.dart';
import 'package:app_diagnostics/app_diagnostics.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/models/embedded_settings.dart';
import '../../core/models/filament_requirement.dart';
import '../../core/models/loaded_spools.dart';
import '../../core/models/plate_list.dart';
import '../../core/models/slice_job.dart';
import '../../core/models/slicer_preset.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../../core/models/process_option.dart';
import '../../core/slicer/filament_slot_options.dart';
import '../../core/slicer/loaded_spool_match.dart';
import '../../core/slicer/preset_compatibility.dart';
import '../../core/slicer/process_settings_codec.dart';
import '../../core/theme/dash_theme.dart';
import '../common/dash_async.dart';
import '../common/inline_note.dart';
import '../dashboard/ams_slot_config_providers.dart'
    show printerModelRegistryProvider;
import '../../core/models/slicer_pipeline.dart';
import '../pipelines/pipeline_presets.dart';
import '../pipelines/pipeline_slice_bar.dart';
import 'process_settings_screen.dart';
import 'slice_filament_colours.dart';
import 'slice_refusal.dart';
import 'slice_preset_sheet.dart';
import '../queue/queue_plate_sheet.dart' show plateLabel, showQueuePlateSheet;
import 'slice_providers.dart';

/// What gets sliced — an archive or a library file. Both use the same
/// `SliceRequest`; only the enqueue endpoint differs.
class SliceTarget {
  const SliceTarget.archive(this.id, this.name) : isArchive = true;
  const SliceTarget.libraryFile(this.id, this.name) : isArchive = false;

  final int id;
  final String name;
  final bool isArchive;
}

/// Opens the slice form for [target]. Returns true if a slice completed
/// successfully (so callers can refresh their lists). Caller is responsible for
/// gating on [slicerEnabledProvider] / capabilities before showing.
///
/// A pushed route rather than a bottom sheet. The form is nine rows before a
/// multicolour file adds more, and in a sheet the submit button was the last
/// item of the scrolling list — reachable only by scrolling past everything and
/// clipped at the bottom edge. A screen gets an app bar and a pinned action bar.
Future<bool> showSliceScreen(BuildContext context, SliceTarget target) async {
  final done = await Navigator.of(
    context,
  ).push<bool>(MaterialPageRoute(builder: (_) => _SliceScreen(target: target)));
  return done ?? false;
}

class _SliceScreen extends ConsumerStatefulWidget {
  const _SliceScreen({required this.target});
  final SliceTarget target;

  @override
  ConsumerState<_SliceScreen> createState() => _SliceScreenState();
}

/// Canonical BambuStudio / OrcaSlicer bed types accepted by `SliceRequest`'s
/// `bed_type`. `null` ⇒ inherit the process preset's plate unchanged.
const _bedTypes = <String>[
  'Cool Plate',
  'Textured PEI Plate',
  'Smooth PEI Plate',
  'Engineering Plate',
  'High Temp Plate',
  'Cool Plate (SuperTack)',
  'Supertack Plate',
];

class _SliceScreenState extends ConsumerState<_SliceScreen> {
  SlicerPreset? _printer;
  SlicerPreset? _process;
  String? _bedType; // null = inherit from the process preset
  // One entry per filament slot the model needs (>= 1). A multicolor 3MF has
  // several; the slice request maps these to slots in order.
  List<SlicerPreset?> _filaments = [];
  bool _submitting = false;

  /// Let the slicer choose each object's orientation (`--orient 1`). Off by
  /// default, exactly as the server has it: it rotates geometry, so a model the
  /// designer laid flat on purpose would silently change.
  bool _autoOrient = false;

  /// Let the slicer lay the objects out on the plate (`--arrange 1`). Off by
  /// default for the same reason — it discards a deliberate layout.
  bool _autoArrange = false;

  /// What the user asked for; whether it applies needs the gate too, so read it
  /// through [_asDesigned].
  bool _useEmbedded = false;

  bool _printerPicked = false;
  bool _designedPrinterAdopted = false;

  /// The plate of a multi-plate 3MF to slice; 1 for anything else, which is
  /// what the sidecar does with no plate named.
  int _plate = 1;

  /// Every plate into one multi-plate output (`plate: 0`, the sidecar's
  /// sentinel). The rows then cover every project slot, all of them in use.
  bool _allPlates = false;

  /// The two filters (#3172), remembered on this device.
  late bool _onlyOnline = ref
      .read(settingsRepositoryProvider)
      .loadSliceOnlyOnline();
  late bool _onlyLoaded = ref
      .read(settingsRepositoryProvider)
      .loadSliceOnlyLoaded();

  /// The spool each row was filled from (#3172), per row. Its colour is what
  /// the row prints in; null leaves that to [sliceFilamentColours]' own rule.
  List<SpoolOrigin?> _spoolOrigins = [];

  /// Filament rows the user filled themselves. A filter only ever re-picks the
  /// others, as on the web: a profile somebody chose stays.
  final _explicitFilaments = <int>{};

  /// Process-option edits from the settings screen, as the user typed them.
  ///
  /// What actually goes on the wire is derived from these rather than stored, so
  /// switching the process preset re-decides which of them are deviations at
  /// all: an edit matching the new preset's own value stops being an override.
  Map<String, Object> _processValues = {};

  /// `GET /slicer/printer-models`, as of the last build — what a printer change
  /// checks the kept picks against.
  Map<String, String> _registry = const {};

  AppLocalizations get _l10n => AppLocalizations.of(context);

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n;
    final theme = Theme.of(context);
    final presetsAsync = ref.watch(slicerPresetsProvider);
    final ownedCodesAsync = ref.watch(ownedPrinterCodesProvider);
    final ownedCodes = ownedCodesAsync.valueOrNull ?? const <String>{};
    final owned =
        ref.watch(ownedFilamentsProvider).valueOrNull ??
        const <OwnedFilament>[];
    final reqsAsync = ref.watch(filamentRequirementsProvider(_filamentKey));
    final reqs = reqsAsync.valueOrNull ?? const <FilamentRequirement>[];
    // A plate just picked has no slots yet. Rows filled against nothing would
    // keep a material the plate never asked for once its slots arrive, so they
    // wait, and so does the button — the web's `filamentReqsQuery.isSuccess`.
    // A read that failed still lets the form go on with one plain row.
    final reqsPending = reqsAsync.isLoading && !reqsAsync.hasValue;
    final embeddedAsync = ref.watch(embeddedSettingsProvider(_sourceKey));
    final embedded = embeddedAsync.valueOrNull ?? EmbeddedSettings.none;
    // Watched here, not where the cards are built: those only exist once the
    // presets have loaded, and the schema behind the first one takes its own
    // time to decode — asked now, both answer during the presets spinner.
    final processSettings = ref.watch(processSettingsAvailableProvider).orFalse;
    final layoutOptions = ref.watch(sliceLayoutOptionsProvider).orFalse;
    final loadedPrinters = ref.watch(loadedSpoolsProvider).valueOrNull;
    final facets =
        ref.watch(ownedSpoolFacetsProvider).valueOrNull ??
        (materials: const <String>{}, brands: const <String>{});
    final registry = _registry =
        ref.watch(printerModelRegistryProvider).valueOrNull ??
        const <String, String>{};

    return Scaffold(
      appBar: dashAppBar(context, title: l10n.sliceTitle),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DashSpace.gutter),
        child: dashAsyncStrip(
          context,
          presetsAsync,
          padding: const EdgeInsets.all(DashSpace.xl),
          failureMessage: l10n.sliceNoPresets,
          data: (presets) {
            // One picker per *project* slot, because `filament_presets` is
            // positional — see [SlicerRepository.filamentRequirements].
            final slotCount = reqs.isEmpty ? 1 : reqs.length;
            _resizeFilaments(slotCount);
            // Across every plate each project slot prints somewhere, so none is
            // marked unused then — the web sets `used_in_plate` on all of them.
            final discriminated = !_allPlates && anyUnused(reqs);
            final plates =
                ref.watch(plateListProvider(_sourceKey)).valueOrNull ??
                PlateList.none;

            final online = loadedPrinters ?? const <LoadedSpoolPrinter>[];
            final connectedModels = [for (final p in online) p.model];
            // Each filter applies only while it has something to go on.
            final printerFilter = _onlyOnline && online.isNotEmpty
                ? (SlicerPreset p) =>
                      isConnectedModelPreset(p, connectedModels, registry)
                : null;
            final printers = _narrow(
              _filterPrinters(presets.printers, ownedCodes, registry),
              printerFilter,
            );
            _printer ??= _firstLocalOr(printers);
            if (!embeddedAsync.isLoading && !ownedCodesAsync.isLoading) {
              _adoptDesignedPrinter(printers, embedded);
            }
            if (printerFilter != null) {
              _moveToOnlinePrinter(
                printers,
                printerFilter,
                connectedModels,
                registry,
                embedded,
              );
            }
            final printerName = _printer?.name;
            final processes = _fitting(
              presets.processes,
              printerName,
              registry,
            );
            _process ??= _firstLocalOr(processes);

            // One filament list for every slot — any owned, printer-compatible
            // filament is selectable (swap PLA↔PETG↔TPU freely). The model's
            // per-slot type/colour only seeds the auto-picked default; plate
            // compatibility is enforced server-side at slice time.
            // Spools count only on printers of the selected profile's model:
            // an A1's AMS says nothing about what an X1C job can start on.
            final spoolPrinters = printersOfModel(
              online,
              printerPresetModel(_printer?.name, registry),
            );
            final nameIndex = buildFilamentNameIndex(presets.filaments);
            final loadedKeys = matchedFilamentKeys(
              spoolPrinters,
              filaments: presets.filaments,
              index: nameIndex,
              selectedPrinterName: _printer?.name,
              registry: registry,
            );
            final filamentFilter = _onlyLoaded && loadedKeys.isNotEmpty
                ? (SlicerPreset p) => loadedKeys.contains(presetKey(p))
                : null;
            final ownedFilaments = _filterFilaments(
              presets.filaments,
              printerName,
              registry,
              owned,
            );
            // From the whole catalog, not the owned list: a spool in the AMS
            // is better evidence than an inventory mapping, and may have none.
            final filaments = filamentFilter == null
                ? ownedFilaments
                : presets.filaments.where(filamentFilter).toList();
            for (var i = 0; i < slotCount && !reqsPending; i++) {
              final current = _filaments[i];
              final notLoaded =
                  current != null &&
                  filamentFilter != null &&
                  !_explicitFilaments.contains(i) &&
                  !filamentFilter(current);
              if (current != null && !notLoaded) continue;
              _filaments[i] = _autoPickFilament(
                loaded: filamentFilter == null ? null : filaments,
                filaments: ownedFilaments,
                owned: owned,
                req: i < reqs.length ? reqs[i] : null,
              );
            }

            final ready =
                !reqsPending &&
                _printer != null &&
                _process != null &&
                _filaments.every((f) => f != null) &&
                !_submitting;

            final canUseEmbedded = embedded.matchesPrinter(_printer?.name);
            final asDesigned = _useEmbedded && canUseEmbedded;

            // Watched rather than read so the count settles once the sidecar
            // answers; the same family key the settings screen uses, so opening
            // it costs no second request.
            final processRef = _processRef;
            final schema = ref.watch(processSchemaProvider).valueOrNull?.schema;
            final presetValues = processRef == null
                ? null
                : ref.watch(presetValuesProvider(processRef)).valueOrNull;
            final overrides = _overridesFrom(schema, presetValues);

            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: DashSpace.sm),
                    children: [
                      Text(
                        widget.target.name,
                        style: theme.textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: DashSpace.sm),
                      // Above the slots it fills, and hidden entirely on a server
                      // without the routes — see [PipelineSliceBar].
                      PipelineSliceBar(
                        printer: _printer,
                        process: _process,
                        filaments: _filaments,
                        bedType: _bedType,
                        busy: _submitting,
                        onApply: (p) => setState(
                          () => _applyPipeline(p, presets, slotCount),
                        ),
                      ),
                      // Shown only once the server said what is loaded: on
                      // an older one, or without printers:read, it has nothing
                      // to narrow by.
                      if (plates.isMultiPlate) _platesCard(plates),
                      if (loadedPrinters != null)
                        _filtersCard(
                          noneOnline:
                              (_onlyOnline || _onlyLoaded) && online.isEmpty,
                          noneLoaded:
                              _onlyLoaded &&
                              online.isNotEmpty &&
                              loadedKeys.isEmpty,
                        ),
                      _slotTile(
                        label: l10n.slicePrinter,
                        icon: Icons.print_outlined,
                        selected: _printer,
                        // The design's own printer is often one the user does not
                        // own, so it is not in `printers` — without this the switch
                        // would live behind the picker's "all presets" toggle.
                        footnote: _designedPrinterNote(
                          presets.printers,
                          embedded,
                        ),
                        // Locked, not just inert: moving off the design's target would
                        // drop the gate and take the switch with it.
                        enabled: !asDesigned,
                        onTap: () async {
                          final p = await _openPicker(
                            title: l10n.slicePrinter,
                            filtered: printers,
                            all: presets.printers,
                          );
                          if (p != null && mounted) {
                            setState(() => _pickPrinter(p));
                          }
                        },
                      ),
                      if (canUseEmbedded)
                        Card(
                          margin: const EdgeInsets.symmetric(
                            vertical: DashSpace.xs,
                          ),
                          child: SwitchListTile(
                            value: _useEmbedded,
                            onChanged: (v) => setState(() => _useEmbedded = v),
                            secondary: const Icon(Icons.auto_awesome_outlined),
                            title: Text(
                              l10n.sliceAsDesigned,
                              style: theme.textTheme.labelMedium,
                            ),
                            subtitle: Text(
                              l10n.sliceAsDesignedHint,
                              style: theme.textTheme.bodySmall,
                            ),
                          ).tagged('slice.as_designed'),
                        ),
                      _slotTile(
                        label: l10n.sliceProcess,
                        icon: Icons.tune,
                        selected: _process,
                        enabled: !asDesigned,
                        onTap: () async {
                          final p = await _openPicker(
                            title: l10n.sliceProcess,
                            filtered: processes,
                            all: presets.processes,
                          );
                          if (p != null && mounted) {
                            setState(() => _process = p);
                          }
                        },
                      ),
                      _dimWhenLocked(
                        !asDesigned,
                        Card(
                          margin: const EdgeInsets.symmetric(
                            vertical: DashSpace.xs,
                          ),
                          child: ListTile(
                            leading: const Icon(Icons.grid_on_outlined),
                            // Patches a process JSON the embedded path never builds.
                            enabled: !asDesigned,
                            title: Text(
                              l10n.sliceBedType,
                              style: theme.textTheme.labelMedium,
                            ),
                            subtitle: Text(
                              asDesigned
                                  ? l10n.sliceAsDesignedInactive
                                  : _bedType ?? l10n.sliceBedDefault,
                              style: theme.textTheme.bodyMedium,
                            ),
                            trailing: asDesigned
                                ? null
                                : const Icon(Icons.chevron_right),
                            onTap: _pickBedType,
                          ).tagged('slice.bed_type'),
                        ),
                      ),
                      // Absent, not disabled, unless the server accepts
                      // `process_overrides` *and* our own vendored metadata loaded —
                      // `SliceRequest` forbids no extra fields, so an older server
                      // would drop the whole map without a word.
                      if (processSettings)
                        _dimWhenLocked(
                          !asDesigned,
                          Card(
                            margin: const EdgeInsets.symmetric(
                              vertical: DashSpace.xs,
                            ),
                            child: ListTile(
                              leading: const Icon(Icons.tune_outlined),
                              enabled: processRef != null && !asDesigned,
                              title: Text(
                                l10n.processSettingsTitle,
                                style: theme.textTheme.labelMedium,
                              ),
                              subtitle: Text(
                                asDesigned
                                    ? l10n.sliceAsDesignedInactive
                                    : processRef == null
                                    ? l10n.sliceProcessSettingsNeedsProcess
                                    : overrides.isEmpty
                                    ? l10n.sliceProcessSettingsUnchanged
                                    : l10n.sliceProcessSettingsChanged(
                                        overrides.length,
                                      ),
                                style: theme.textTheme.bodyMedium,
                              ),
                              trailing: asDesigned
                                  ? null
                                  : const Icon(Icons.chevron_right),
                              onTap: processRef == null || asDesigned
                                  ? null
                                  : () => showProcessSettings(
                                      context,
                                      preset: processRef,
                                      values: _processValues,
                                      onChanged: (next) =>
                                          setState(() => _processValues = next),
                                      filamentSlots: _filamentSlots(
                                        slotCount,
                                        reqs,
                                        discriminated,
                                      ),
                                    ),
                            ).tagged('slice.process_settings'),
                          ),
                        ),
                      // Hidden entirely before server 1.2.6: the fields are dropped
                      // without a word there, and a switch that does nothing is worse
                      // than no switch. See [sliceLayoutOptionsProvider].
                      if (layoutOptions)
                        Card(
                          margin: const EdgeInsets.symmetric(
                            vertical: DashSpace.xs,
                          ),
                          child: Column(
                            children: [
                              SwitchListTile(
                                value: _autoOrient,
                                onChanged: (v) =>
                                    setState(() => _autoOrient = v),
                                secondary: const Icon(
                                  Icons.screen_rotation_alt_outlined,
                                ),
                                title: Text(
                                  l10n.sliceAutoOrient,
                                  style: theme.textTheme.labelMedium,
                                ),
                                subtitle: Text(
                                  l10n.sliceAutoOrientHint,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ).tagged('slice.auto_orient'),
                              SwitchListTile(
                                value: _autoArrange,
                                onChanged: (v) =>
                                    setState(() => _autoArrange = v),
                                secondary: const Icon(Icons.grid_view_outlined),
                                title: Text(
                                  l10n.sliceAutoArrange,
                                  style: theme.textTheme.labelMedium,
                                ),
                                subtitle: Text(
                                  l10n.sliceAutoArrangeHint,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ).tagged('slice.auto_arrange'),
                            ],
                          ),
                        ),
                      for (var i = 0; i < slotCount; i++)
                        _slotTile(
                          label: slotCount == 1
                              ? l10n.sliceFilament
                              : l10n.sliceFilamentNumbered('${i + 1}'),
                          icon: Icons.cable,
                          swatch: _spoolOrigins[i]?.colour != null
                              ? colorFromHex(_spoolOrigins[i]!.colour)
                              : i < reqs.length
                              ? colorFromHex(reqs[i].color)
                              : null,
                          footnote: _spoolOrigins[i] == null
                              ? null
                              : Text(
                                  l10n.sliceSpoolFrom(_spoolOrigins[i]!.label),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                          typeHint: i < reqs.length ? reqs[i].type : null,
                          // Only when the server actually told used from unused —
                          // its own fallback flags everything used, and marking every
                          // row then would claim knowledge nobody has.
                          unused:
                              discriminated &&
                              i < reqs.length &&
                              !reqs[i].usedInPlate,
                          selected: _filaments[i],
                          // An empty slot stays pickable: the validator wants a ref per
                          // slot on this path too, so locking it dead-ends the form.
                          enabled: !asDesigned || _filaments[i] == null,
                          onTap: () async {
                            final pick = await showPresetSheet(
                              context,
                              title: slotCount == 1
                                  ? l10n.sliceFilament
                                  : l10n.sliceFilamentNumbered('${i + 1}'),
                              // Not narrowed to the printer: the sheet's own
                              // printer filter does that, and starts on it.
                              filtered: filamentFilter == null
                                  ? _filterFilaments(
                                      presets.filaments,
                                      null,
                                      registry,
                                      owned,
                                    )
                                  : filaments,
                              all: presets.filaments,
                              filament: FilamentChoices(
                                // The Spools tab while any printer is online,
                                // even one of another model: it then says so.
                                spoolPrinters: online.isEmpty
                                    ? null
                                    : spoolPrinters,
                                matchFor: (tray) => matchSlotPreset(
                                  tray,
                                  filaments: presets.filaments,
                                  index: nameIndex,
                                  selectedPrinterName: _printer?.name,
                                  registry: registry,
                                ),
                                ownedModels: ownedCodes,
                                ownedMaterials: facets.materials,
                                ownedBrands: facets.brands,
                                registry: registry,
                                printerModel: printerPresetModel(
                                  _printer?.name,
                                  registry,
                                ),
                                needsMaterial: i < reqs.length
                                    ? reqs[i].type
                                    : null,
                              ),
                            );
                            if (pick != null && mounted) {
                              setState(() {
                                _filaments[i] = pick.preset;
                                _explicitFilaments.add(i);
                                _spoolOrigins[i] = pick.spool;
                              });
                            }
                          },
                        ),
                    ],
                  ),
                ),
                _submitBar(
                  l10n,
                  ready,
                  allPlates: plates.isMultiPlate && _allPlates
                      ? plates.plates.length
                      : null,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The submit button, pinned outside the scroll area so it is never something
  /// the user has to scroll a nine-row form to find.
  Widget _submitBar(AppLocalizations l10n, bool ready, {int? allPlates}) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(top: DashSpace.sm, bottom: DashSpace.sm),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: _submitting
                ? const DashSpinner()
                : const Icon(Icons.layers_outlined),
            label: Text(
              allPlates == null
                  ? l10n.sliceStart
                  : l10n.sliceAllPlates(allPlates),
            ),
            onPressed: ready ? _submit : null,
          ).tagged('slice.submit'),
        ),
      ),
    );
  }

  /// The line under the printer naming the one the design targets, with the
  /// action that switches to it. Null once they are the same printer, or when
  /// the file names none.
  ///
  /// [all] is the unfiltered catalog on purpose: the design's printer is
  /// usually one the user does not own.
  Widget? _designedPrinterNote(
    List<SlicerPreset> all,
    EmbeddedSettings embedded,
  ) {
    if (!embedded.isAvailable || embedded.matchesPrinter(_printer?.name)) {
      return null;
    }
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final designed = all
        .where((p) => embedded.matchesPrinter(p.name))
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _l10n.sliceDesignedFor(_shortPresetName(embedded.printer!)),
          style: style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // Naming the printer is worth something even with nothing to switch to.
        if (designed != null)
          Padding(
            padding: const EdgeInsets.only(
              top: DashSpace.sm,
              bottom: DashSpace.xs,
            ),
            child: FilledButton.tonal(
              onPressed: () => setState(() => _pickPrinter(designed)),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: DashSpace.lg),
                // Material's dense floor. `shrinkWrap` only drops the invisible
                // 48px tap padding a button reserves in a form, which inside a
                // list subtitle would push the rows apart.
                minimumSize: const Size(48, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: theme.textTheme.labelLarge,
              ),
              child: Text(_l10n.sliceUseDesignedPrinter),
            ).tagged('slice.use_designed_printer'),
          ),
      ],
    );
  }

  /// Fold a saved bundle into the form's slots.
  ///
  /// Deliberately not routed through [_pickPrinter], which clears the process
  /// and filaments on purpose: here the whole bundle arrives together and was
  /// authored to fit, so wiping the very fields the pipeline just supplied
  /// would undo it. [_printerPicked] is set for the same reason the picker sets
  /// it — the design's printer must not be adopted over a deliberate choice.
  ///
  /// The filament list is right-padded from what is already there, so applying
  /// a one-slot pipeline to a four-slot model fills slot 1 and leaves the rest
  /// as they were rather than blanking them. `filament_presets` is positional,
  /// so an entry only ever lands on the slot of the same index.
  ///
  /// Process overrides are dropped: they were measured against whatever process
  /// preset was selected before, and the pipeline brings a different one.
  void _applyPipeline(
    SlicerPipeline pipeline,
    UnifiedPresets catalog,
    int slotCount,
  ) {
    _printerPicked = true;
    _printer = resolvePresetRef(
      catalog,
      pipeline.printerPreset,
      PresetSlot.printer,
    );
    _process = resolvePresetRef(
      catalog,
      pipeline.processPreset,
      PresetSlot.process,
    );
    _bedType = pipeline.bedType;
    _processValues = {};

    _resizeFilaments(slotCount);
    for (var i = 0; i < _filaments.length; i++) {
      if (i >= pipeline.filamentPresets.length) continue;
      _explicitFilaments.add(i);
      _spoolOrigins[i] = null;
      _filaments[i] = resolvePresetRef(
        catalog,
        pipeline.filamentPresets[i],
        PresetSlot.filament,
      );
    }

    // A bundle authored for a different printer must not keep the "as designed"
    // gate alive — that switch is only meaningful while the form sits on the
    // printer the file was made for, and the pipeline has just moved it.
    _useEmbedded = false;
  }

  /// Everything a printer change invalidates, in one place: the process and
  /// filaments were chosen for the old one, and the edits measured against a
  /// preset that is gone.
  void _pickPrinter(SlicerPreset printer) {
    _printerPicked = true;
    _printer = printer;
    // The web's re-pick (#1325): a pick that still fits the new printer stays,
    // the user's own included; one ruled out for it is chosen again.
    bool ruledOut(SlicerPreset? p) =>
        p != null &&
        presetCompatibility(p, printer.name, _registry) == PresetFit.mismatch;
    if (ruledOut(_process)) _process = null;
    for (var i = 0; i < _filaments.length; i++) {
      if (!ruledOut(_filaments[i])) continue;
      _filaments[i] = null;
      _spoolOrigins[i] = null;
      _explicitFilaments.remove(i);
    }
    _processValues = {};
  }

  /// With "only online printers" on, an auto-picked printer of a model that is
  /// not online moves to one that is — the file's own printer first, when that
  /// model is online (the web's effect of the same name). A printer the user
  /// chose stays, and so does the file's own while its settings are in use.
  /// [all] is the owned list, as for [_adoptDesignedPrinter].
  void _moveToOnlinePrinter(
    List<SlicerPreset> all,
    bool Function(SlicerPreset) online,
    List<String?> connectedModels,
    Map<String, String> registry,
    EmbeddedSettings embedded,
  ) {
    final current = _printer;
    if (_printerPicked || _useEmbedded || current == null) return;
    if (online(current)) return;
    final designed = all
        .where((p) => embedded.matchesPrinter(p.name))
        .firstOrNull;
    final next = designed != null && online(designed)
        ? designed
        : pickConnectedPrinterPreset(all, connectedModels, registry);
    if (next == null) return;
    // Rows the user filled while the answer was in flight survive the move
    // where they still fit the new printer — the web keeps a pick that is not
    // a mismatch and picks the rest again. The auto-picked rows are re-picked.
    // A spool picked for one stays behind: it sits in the printer that was
    // left, so the row keeps its profile, not that spool's colour or name.
    final kept = {
      for (final i in _explicitFilaments)
        if (i < _filaments.length)
          if (_filaments[i] case final preset?
              when presetCompatibility(preset, next.name, registry) !=
                  PresetFit.mismatch)
            i: preset,
    };
    _pickPrinter(next);
    _printerPicked = false;
    for (final MapEntry(key: i, value: preset) in kept.entries) {
      _filaments[i] = preset;
      _explicitFilaments.add(i);
    }
  }

  /// [list] narrowed by [keep], or [list] itself when that would leave nothing
  /// to pick — the rest stays one "All" away in the picker.
  List<SlicerPreset> _narrow(
    List<SlicerPreset> list,
    bool Function(SlicerPreset)? keep,
  ) {
    if (keep == null) return list;
    final narrowed = list.where(keep).toList();
    return narrowed.isEmpty ? list : narrowed;
  }

  /// A row's default: from the loaded spools first, but only one that does not
  /// state another material than the plate's slot — a loaded PLA is no answer
  /// for a PETG slot (web #2982). Otherwise the usual pick.
  SlicerPreset? _autoPickFilament({
    required List<SlicerPreset>? loaded,
    required List<SlicerPreset> filaments,
    required List<OwnedFilament> owned,
    required FilamentRequirement? req,
  }) {
    if (loaded != null && loaded.isNotEmpty) {
      final type = req?.type;
      // The slot's material first among the loaded, as the web's scorer
      // ranks it: otherwise the first loaded PLA hides a loaded PETG.
      final ofMaterial = type == null
          ? loaded
          : [
              for (final p in loaded)
                if (!statesDifferentMaterial(p, type)) p,
            ];
      final fromLoaded = _pickDefaultFilament(
        ofMaterial.isEmpty ? loaded : ofMaterial,
        owned,
        req,
      );
      if (fromLoaded != null &&
          (type == null || !statesDifferentMaterial(fromLoaded, type))) {
        return fromLoaded;
      }
    }
    return _pickDefaultFilament(filaments, owned, req);
  }

  /// Which plate to slice, and the switch that slices them all — shown only
  /// for a 3MF with more than one plate.
  Widget _platesCard(PlateList plates) {
    final l10n = _l10n;
    final theme = Theme.of(context);
    final current = plates.byIndex(_plate);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: DashSpace.xs),
      child: Column(
        children: [
          _dimWhenLocked(
            !_allPlates,
            ListTile(
              leading: const Icon(Icons.layers_outlined),
              enabled: !_allPlates && !_submitting,
              title: Text(
                l10n.queueEditPlate,
                style: theme.textTheme.labelMedium,
              ),
              subtitle: Text(
                current == null
                    ? l10n.queueEditPlateSelected(_plate)
                    : plateLabel(l10n, current),
                style: theme.textTheme.bodyMedium,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickPlate(plates),
            ).tagged('slice.plate'),
          ),
          SwitchListTile(
            value: _allPlates,
            onChanged: _submitting
                ? null
                : (v) => setState(() => _allPlates = v),
            secondary: const Icon(Icons.layers_clear_outlined),
            title: Text(
              l10n.sliceAllPlates(plates.plates.length),
              style: theme.textTheme.labelMedium,
            ),
            subtitle: Text(
              l10n.sliceAllPlatesHint,
              style: theme.textTheme.bodySmall,
            ),
          ).tagged('slice.all_plates'),
        ],
      ),
    );
  }

  /// Another plate has other slots, so the rows start over: what was picked,
  /// the spool colours and any process edit naming a slot all named a slot of
  /// the plate that was left.
  Future<void> _pickPlate(PlateList plates) async {
    final picked = await showQueuePlateSheet(
      context,
      plates: plates,
      selected: _plate,
    );
    if (picked == null || picked == _plate || !mounted) return;
    final schema = ref.read(processSchemaProvider).valueOrNull?.schema;
    setState(() {
      _plate = picked;
      _filaments = List.filled(_filaments.length, null);
      _spoolOrigins = List.filled(_filaments.length, null);
      _explicitFilaments.clear();
      // An edit naming a filament slot named one of the plate that was left.
      _processValues = {
        for (final MapEntry(:key, :value) in _processValues.entries)
          if (schema?[key] == null || !namesFilamentSlot(schema![key]!))
            key: value,
      };
    });
  }

  Widget _filtersCard({required bool noneOnline, required bool noneLoaded}) {
    final l10n = _l10n;
    final theme = Theme.of(context);
    final settings = ref.read(settingsRepositoryProvider);
    Widget toggle({
      required String id,
      required bool value,
      required String title,
      required String hint,
      required ValueChanged<bool> onChanged,
    }) => SwitchListTile(
      value: value,
      onChanged: _submitting ? null : onChanged,
      title: Text(title, style: theme.textTheme.labelMedium),
      subtitle: Text(hint, style: theme.textTheme.bodySmall),
    ).tagged(id);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: DashSpace.xs),
      child: Column(
        children: [
          toggle(
            id: 'slice.only_online',
            value: _onlyOnline,
            title: l10n.sliceOnlyOnline,
            hint: l10n.sliceOnlyOnlineHint,
            onChanged: (v) {
              setState(() => _onlyOnline = v);
              unawaited(settings.saveSliceOnlyOnline(v));
            },
          ),
          toggle(
            id: 'slice.only_loaded',
            value: _onlyLoaded,
            title: l10n.sliceOnlyLoaded,
            hint: l10n.sliceOnlyLoadedHint,
            onChanged: (v) {
              setState(() => _onlyLoaded = v);
              unawaited(settings.saveSliceOnlyLoaded(v));
            },
          ),
          if (noneOnline || noneLoaded)
            InlineNote(
              noneOnline ? l10n.sliceNoneOnline : l10n.sliceNoneLoaded,
              icon: Icons.info_outline,
              announce: true,
              padding: const EdgeInsets.fromLTRB(
                DashSpace.lg,
                0,
                DashSpace.lg,
                DashSpace.md,
              ),
            ),
        ],
      ),
    );
  }

  /// `ListTile.enabled` alone barely reads on the dark theme — the row looked
  /// tappable and its text still legible. Dimming the whole card is what shows
  /// the lock.
  Widget _dimWhenLocked(bool enabled, Widget card) =>
      enabled ? card : Opacity(opacity: 0.4, child: card);

  (bool, int) get _sourceKey => (widget.target.isArchive, widget.target.id);

  /// The plate the slots are read for. It has to be the plate the slice names,
  /// or the slots offered are not the slots the slice will use. With every
  /// plate sliced it is still the picked one, as on the web: the rows are every
  /// project slot (`full_slots`) whichever plate asks, though their colours and
  /// usage describe that plate.
  PlateSource get _filamentKey =>
      (isArchive: widget.target.isArchive, id: widget.target.id, plate: _plate);

  /// Re-checked against the gate, so a switch left on by a stale read cannot
  /// reach the request.
  bool get _asDesigned {
    if (!_useEmbedded) return false;
    final embedded = ref.read(embeddedSettingsProvider(_sourceKey)).valueOrNull;
    return embedded?.matchesPrinter(_printer?.name) ?? false;
  }

  /// Default the printer to the design's target once the plates read lands —
  /// without it nobody would guess which printer makes the switch appear.
  ///
  /// Once, over a default the user has not replaced, and only from [printers],
  /// which is already narrowed to the ones they own.
  void _adoptDesignedPrinter(
    List<SlicerPreset> printers,
    EmbeddedSettings embedded,
  ) {
    if (_designedPrinterAdopted) return;
    _designedPrinterAdopted = true;
    if (_printerPicked || !embedded.isAvailable) return;
    if (embedded.matchesPrinter(_printer?.name)) return;

    final designed = printers
        .where((p) => embedded.matchesPrinter(p.name))
        .firstOrNull;
    if (designed == null) return;
    _pickPrinter(designed);
    // Adopted, not chosen: the note below must still offer the other printers.
    _printerPicked = false;
  }

  /// The picked process preset as `/slicer/preset-values` takes it.
  ProcessPresetRef? get _processRef =>
      _process == null ? null : (_process!.source, _process!.id);

  /// The `process_overrides` body: only the edits that really differ from what
  /// the picked preset already says. Empty until both the vendored schema and
  /// the preset's values are in hand — sending edits measured against an unknown
  /// baseline would mean sending values the user never chose to change.
  Map<String, Object> _overridesFrom(
    Map<String, ProcessOption>? schema,
    PresetValues? presetValues,
  ) {
    if (schema == null || presetValues == null) return const {};
    return buildProcessOverrides(
      values: _processValues,
      schema: schema,
      presetValues: presetValues.values,
    );
  }

  /// The slots as the process-settings screen needs them: what to call each one
  /// in the eight pickers whose value is a slot index.
  ///
  /// [discriminated] gates the unused mark for the same reason it gates it on the
  /// rows above — all-used is also what the server's own fallback produces.
  List<FilamentSlotChoice> _filamentSlots(
    int slotCount,
    List<FilamentRequirement> reqs,
    bool discriminated,
  ) {
    final l10n = _l10n;
    return [
      for (var i = 0; i < slotCount; i++)
        FilamentSlotChoice(
          slot: i + 1,
          // The picker prefixes the number itself, so the type — or failing that
          // the bare word — is a more useful fallback than repeating it.
          label:
              _filaments[i]?.name ??
              (i < reqs.length ? reqs[i].type : null) ??
              l10n.sliceFilament,
          unused: discriminated && i < reqs.length && !reqs[i].usedInPlate,
        ),
    ];
  }

  /// Grow/shrink the per-slot list, preserving existing picks.
  void _resizeFilaments(int count) {
    if (_filaments.length == count) return;
    final next = List<SlicerPreset?>.filled(count, null);
    final origins = List<SpoolOrigin?>.filled(count, null);
    for (var i = 0; i < count && i < _filaments.length; i++) {
      next[i] = _filaments[i];
      if (i < _spoolOrigins.length) origins[i] = _spoolOrigins[i];
    }
    _filaments = next;
    _spoolOrigins = origins;
  }

  Widget _slotTile({
    required String label,
    required IconData icon,
    required SlicerPreset? selected,
    required VoidCallback onTap,
    Color? swatch,
    String? typeHint,
    bool unused = false,
    bool enabled = true,
    Widget? footnote,
  }) {
    final theme = Theme.of(context);
    // An applied pipeline can name a preset this catalog does not list — the
    // ref still slices, so the row says so rather than reading as empty, which
    // would invite a re-pick of something that is already set.
    final unresolved = selected != null && isUnresolved(selected);
    final subtitle = switch (selected) {
      null =>
        typeHint != null
            ? '${_l10n.sliceSelect} · $typeHint'
            : _l10n.sliceSelect,
      _ when unresolved => _l10n.pipelinePresetGone,
      _ => selected.name,
    };
    final card = Card(
      margin: const EdgeInsets.symmetric(vertical: DashSpace.xs),
      child: ListTile(
        enabled: enabled,
        leading: swatch != null
            ? Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: swatch,
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.dividerColor),
                ),
              )
            : Icon(icon),
        title: Text(label, style: theme.textTheme.labelMedium),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: selected == null || unresolved
                    ? theme.colorScheme.onSurfaceVariant
                    : null,
              ),
            ),
            // The slot still has to be picked — the slicer wants one preset per
            // project slot — but saying which ones the plate ignores stops the
            // user hunting for the right spool for a slot that prints nothing.
            if (unused)
              Text(
                _l10n.sliceFilamentUnused,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ?footnote,
          ],
        ),
        trailing: enabled ? const Icon(Icons.chevron_right) : null,
        onTap: onTap,
      ).tagged('slice.slot'),
    );
    return _dimWhenLocked(enabled, card);
  }

  Future<void> _pickBedType() async {
    final l10n = _l10n;
    // Sentinel '' = "Default (inherit from preset)" → stored as null.
    Widget tile(String value, String label) => ListTile(
      leading: Icon(
        (_bedType ?? '') == value
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
      ),
      title: Text(label),
      onTap: () => Navigator.pop(context, value),
    ).tagged('slice.bed_type');
    final picked = await dashSheet<String>(
      context,
      scrollControlled: false,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            tile('', l10n.sliceBedDefault),
            for (final b in _bedTypes) tile(b, b),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return; // dismissed
    setState(() => _bedType = picked.isEmpty ? null : picked);
  }

  Future<SlicerPreset?> _openPicker({
    required String title,
    required List<SlicerPreset> filtered,
    required List<SlicerPreset> all,
  }) async => (await showPresetSheet(
    context,
    title: title,
    filtered: filtered,
    all: all,
  ))?.preset;

  Future<void> _submit() async {
    final l10n = _l10n;
    final messenger = ScaffoldMessenger.of(context);
    final target = widget.target;
    final refs = [for (final f in _filaments) f!.toRef()];
    final asDesigned = _asDesigned;
    // Slot colours, positional like `refs`. Empty on the "as designed" path:
    // the file's own project settings carry the colours it was drawn with, and
    // the server ignores the resolved filament profiles there anyway.
    final colours = asDesigned
        ? const <String>[]
        : sliceFilamentColours(
            picked: _filaments,
            overrides: [for (final o in _spoolOrigins) o?.colour],
            owned:
                ref.read(ownedFilamentsProvider).valueOrNull ??
                const <OwnedFilament>[],
            requirements:
                ref
                    .read(filamentRequirementsProvider(_filamentKey))
                    .valueOrNull ??
                const <FilamentRequirement>[],
          );
    final overrides = asDesigned
        ? const <String, Object>{}
        : _overridesFrom(
            ref.read(processSchemaProvider).valueOrNull?.schema,
            _processRef == null
                ? null
                : ref.read(presetValuesProvider(_processRef!)).valueOrNull,
          );
    final body = <String, dynamic>{
      'printer_preset': _printer!.toRef(),
      'process_preset': _process!.toRef(),
      // Single slot → the singular field (the proven path); multicolor → the
      // ordered array, one entry per filament slot.
      if (refs.length == 1)
        'filament_preset': refs.first
      else
        'filament_presets': refs,
      // The preset refs above stay: the validator wants them here too, unused.
      if (asDesigned) 'use_embedded_settings': true,
      // 0 for every plate, another plate by number; plate 1 is what the sidecar
      // slices with none named, so it is left out as on a single-plate file.
      if (_allPlates) 'plate': 0 else if (_plate != 1) 'plate': _plate,
      // Override the plate only when the user picked one; null inherits.
      if (_bedType != null && !asDesigned) 'bed_type': _bedType,
      // Only when on: both default to false server-side, and an older server
      // ignores unknown keys silently, so sending the default would be noise
      // that also hides which servers actually honoured it.
      if (_autoOrient) 'auto_orient': true,
      if (_autoArrange) 'auto_arrange': true,
      // What each slot actually prints in, so the output records the spool's
      // colour rather than the slicer's compiled-in green (server #2977). No
      // version gate, unlike the switches above: this is derived from the
      // pickers rather than being a control of its own, so an older server that
      // drops the key just slices as it did before and there is nothing that
      // could appear to work while doing nothing.
      if (colours.isNotEmpty) 'filament_colours': colours,
      // Only genuine deviations, so an untouched screen leaves this slice
      // byte-identical to one from before the feature existed.
      if (overrides.isNotEmpty) 'process_overrides': overrides,
    };
    setState(() => _submitting = true);
    final int jobId;
    try {
      final repo = ref.read(slicerRepositoryProvider);
      jobId = target.isArchive
          ? await repo.sliceArchive(target.id, body)
          : await repo.sliceLibraryFile(target.id, body);
    } on AppApiException catch (e) {
      if (mounted) setState(() => _submitting = false);
      showApiFailure(
        mounted ? messenger : null,
        e,
        l10n,
        action: 'slice.submit',
        message: sliceRefusalMessage(l10n, e),
      );
      return;
    }
    if (!mounted) return;
    final ok =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _SliceProgressDialog(jobId: jobId),
        ) ??
        false;
    if (!mounted) return;
    Navigator.pop(context, ok); // close the sheet, report success upward
  }

  // --- filtering / auto-pick ---

  SlicerPreset? _firstLocalOr(List<SlicerPreset> list) => list.isEmpty
      ? null
      : list.firstWhere((p) => p.isLocal, orElse: () => list.first);

  List<SlicerPreset> _filterPrinters(
    List<SlicerPreset> all,
    Set<String> owned,
    Map<String, String> registry,
  ) {
    if (owned.isEmpty) return all;
    final models = owned.toList();
    return all
        .where((p) => p.isLocal || isConnectedModelPreset(p, models, registry))
        .toList();
  }

  /// The presets the web's rule (`presetCompatibility`) does not rule out for
  /// [printerName] — an untagged one stays. When that leaves nothing, all of
  /// them, as the web does (#2982): a preset for the wrong printer can be
  /// changed, an empty list cannot.
  List<SlicerPreset> _fitting(
    List<SlicerPreset> all,
    String? printerName,
    Map<String, String> registry,
  ) {
    final fit = [
      for (final p in all)
        if (presetCompatibility(p, printerName, registry) != PresetFit.mismatch)
          p,
    ];
    return fit.isEmpty ? all : fit;
  }

  /// Owned (any material) + printer-compatible. Not narrowed by the model's
  /// filament type — the user can pick a different material per slot.
  List<SlicerPreset> _filterFilaments(
    List<SlicerPreset> all,
    String? printerName,
    Map<String, String> registry,
    List<OwnedFilament> owned,
  ) {
    final fit = _fitting(all, printerName, registry);
    final ownedNames = {for (final o in owned) o.name};
    // No owned-filament signal — narrow by printer only.
    if (ownedNames.isEmpty) return fit;
    return fit
        .where((p) => p.isLocal || _ownedMatch(p.name, ownedNames))
        .toList();
  }

  /// Prefer the owned filament of the right material closest in colour to the
  /// requirement; fall back to a local preset, then the first option.
  SlicerPreset? _pickDefaultFilament(
    List<SlicerPreset> filtered,
    List<OwnedFilament> owned,
    FilamentRequirement? req,
  ) {
    if (filtered.isEmpty) return null;
    if (req != null) {
      final ofType =
          [
            for (final o in owned)
              if (req.type == null || _typeMatches(o.material, req.type!)) o,
          ]..sort(
            (a, b) => colorDistance(
              a.color,
              req.color,
            ).compareTo(colorDistance(b.color, req.color)),
          );
      for (final o in ofType) {
        final match = filtered.where((p) => p.name == o.name);
        if (match.isNotEmpty) return match.first;
      }
    }
    return _firstLocalOr(filtered);
  }
}

/// `Bambu Lab X1 Carbon 0.4 nozzle` → `X1 Carbon 0.4`. On one line inside a list
/// row only the middle tells the printers apart; anything not in that shape is
/// left alone.
String _shortPresetName(String name) => name
    .replaceFirst(RegExp(r'^Bambu Lab\s+'), '')
    .replaceFirst(RegExp(r'\s+nozzle$'), '');

bool _typeMatches(String material, String type) {
  final m = material.toUpperCase();
  final t = type.toUpperCase();
  return m == t || m.startsWith(t) || t.startsWith(m);
}

/// A preset belongs to an owned filament if its name equals an owned base name
/// or extends it ("Bambu PETG HF" → "Bambu PETG HF @BBL X2D 0.4 nozzle").
bool _ownedMatch(String name, Set<String> owned) {
  for (final base in owned) {
    if (name == base || name.startsWith('$base ')) return true;
  }
  return false;
}

/// Polls a slice job to completion, showing live stage/progress, then the
/// result (or error). Non-dismissible until terminal.
class _SliceProgressDialog extends ConsumerStatefulWidget {
  const _SliceProgressDialog({required this.jobId});
  final int jobId;

  @override
  ConsumerState<_SliceProgressDialog> createState() =>
      _SliceProgressDialogState();
}

class _SliceProgressDialogState extends ConsumerState<_SliceProgressDialog> {
  Timer? _timer;
  SliceJob? _job;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final job = await ref.read(slicerRepositoryProvider).job(widget.jobId);
      if (!mounted) return;
      setState(() => _job = job);
      if (job.isTerminal) _timer?.cancel();
    } on AppApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
      _timer?.cancel();
    }
  }

  /// Second half of the "it did not land where you asked" sentence. Unknown
  /// keys (a reason a newer server adds) get no clause rather than their raw
  /// wire value — the first half already says where the file actually is.
  String? _externalFallbackReason(AppLocalizations l10n, String reason) =>
      switch (reason) {
        'external_readonly' => l10n.sliceExternalReadonly,
        'external_no_path' => l10n.sliceExternalNoPath,
        'external_unreachable' => l10n.sliceExternalUnreachable,
        'external_not_writable' => l10n.sliceExternalNotWritable,
        'external_invalid_name' => l10n.sliceExternalInvalidName,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final job = _job;
    final terminal = _error != null || (job?.isTerminal ?? false);
    final success = job?.isCompleted ?? false;

    Widget content;
    if (_error != null) {
      content = Text(
        _error is AppApiException
            ? (_error! as AppApiException).localized(l10n)
            : l10n.sliceFailed,
      );
    } else if (job != null && job.isFailed) {
      content = Text(job.errorDetail ?? l10n.sliceFailed);
    } else if (success) {
      final r = job!.result;
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (r?.name != null)
            Text(
              r!.name!,
              style: theme.textTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          if (r?.printTimeSeconds != null)
            Text(
              l10n.sliceResultTime(formatSeconds(l10n, r!.printTimeSeconds!)),
            ),
          if (r?.filamentUsedG != null)
            Text(
              l10n.sliceResultFilament(r!.filamentUsedG!.toStringAsFixed(1)),
            ),
          if (r?.externalWriteFallback != null) ...[
            const SizedBox(height: DashSpace.sm),
            Text(
              [
                l10n.sliceExternalFallback,
                ?_externalFallbackReason(l10n, r!.externalWriteFallback!),
              ].join(' '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      );
    } else {
      final stage = job?.progress?.stage;
      final fraction = job?.progress?.fraction;
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(value: fraction),
          const SizedBox(height: DashSpace.md),
          Text(
            stage ?? l10n.sliceInProgress,
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return AlertDialog(
      title: Text(
        _error != null || (job?.isFailed ?? false)
            ? l10n.sliceFailed
            : success
            ? l10n.sliceDone
            : l10n.sliceInProgress,
      ),
      content: content,
      actions: terminal
          ? [
              logTag(
                'slice_progress.close',
                FilledButton(
                  onPressed: () => Navigator.pop(context, success),
                  child: Text(l10n.sliceClose),
                ),
              ),
            ]
          : null,
    );
  }
}
