import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/diagnostic_recorder.dart';
import '../../core/diagnostics/log_event.dart';
import '../../core/diagnostics/log_tag.dart';
import '../../core/format/datetime_format.dart';
import '../../core/format/user_number.dart';
import '../../core/models/available_filament.dart';
import '../../core/models/calibration_option.dart';
import '../../core/models/filament_requirement.dart';
import '../../core/models/plate_list.dart';
import '../../core/models/printer_status.dart';
import '../../core/printers/nozzle_rack.dart';
import '../../core/models/queue_item.dart';
import '../../core/settings/print_options.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../data/queue_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../common/dash_snack.dart';
import '../common/date_time_picker.dart';
import '../common/print_thumbnail.dart';
import '../common/system_insets.dart';
import '../files/library_thumbnail.dart';
import '../slicer/slice_providers.dart';
import '../common/hex_color.dart';
import 'queue_mapping_sheet.dart';
import 'queue_plate_sheet.dart';
import 'queue_providers.dart';

/// Full print-job form — mirrors the web PrintModal, which serves both modes
/// from one component.
///
/// [QueueEditMode.edit]: `PATCH /queue/{id}` via [QueueRepository.updateItem].
/// Only pending items are editable (the server rejects the rest), so the entry
/// point is gated on status.
///
/// [QueueEditMode.create]: `POST /queue/` via [QueueRepository.addFromArchive]
/// or [QueueRepository.addFromLibraryFile], carrying the whole configuration.
/// Configuring BEFORE the item exists is what keeps the scheduler from starting
/// a job the user is still setting up — the race in
/// `docs/plans/06b-log-findings.md`.
///
/// Either way the payload follows the web's: printer mode clears
/// `target_model`/`target_location`, model mode clears `printer_id`,
/// `scheduled_time` is set only for Schedule, and `manual_start` is honoured
/// only in Queue mode. ASAP additionally sends `insert_at_top` — create-only,
/// since it is a position at insertion, not a stored field.
class QueueEditScreen extends ConsumerStatefulWidget {
  const QueueEditScreen({
    super.key,
    required this.item,
    this.mode = QueueEditMode.edit,
    this.initialSchedule,
  });

  /// In [QueueEditMode.create] this is a [QueueItem.draft]: it carries the
  /// source, the name and the values the form starts from, and its `id` is
  /// never used.
  final QueueItem item;

  final QueueEditMode mode;

  /// Which schedule segment starts selected. Null derives it from the item
  /// (a real `scheduled_time` = Schedule, else Queue), which is what edit wants.
  final QueueScheduleType? initialSchedule;

  bool get _isCreate => mode == QueueEditMode.create;

  @override
  ConsumerState<QueueEditScreen> createState() => _QueueEditScreenState();
}

/// What Save does: update an existing item, or create one from the form.
enum QueueEditMode { edit, create }

/// When the job should print. Only [QueueScheduleType.queue] can be staged with
/// `manual_start`; the other two dispatch on their own terms.
enum QueueScheduleType { asap, queue, scheduled }

/// Models with two nozzles — gate for the nozzle-offset-calibration option
/// (matches the web `showDualNozzleOptions` model list).
const _dualNozzleModels = {'H2D', 'H2DPRO', 'H2C', 'X2D'};

/// Dark ink for text/icons painted on a solid [DashTokens.accentGreen] fill.
/// `accentGreenInk` can't be used here: in the dark theme it equals
/// `accentGreen`, so the label would vanish into the fill. Mirrors the app's
/// on-accent ink (`dashPrimaryButtonStyle`).
const Color _onGreenFill = Color(0xFF0A0C08);

class _QueueEditScreenState extends ConsumerState<QueueEditScreen> {
  // Target
  late bool _modelMode; // false = specific printer, true = "Any <model>"
  late int? _printerId;
  late String? _targetModel;
  late String? _targetLocation;

  // Filament mapping (printer mode). Null = auto/unchanged.
  late List<int>? _amsMapping;

  // Which plate of a multi-plate 3MF to print. Null on a single-plate file and
  // on every server that does not report one, and null is what the print
  // scheduler reads as plate 1.
  late int? _plateId;

  // Filament overrides (model mode): slot_id → chosen filament, and per-slot
  // force-color-match flags. Prefilled from the item's stored overrides.
  final Map<int, ({String type, String color})> _overrides = {};
  final Map<int, bool> _forceColorMatch = {};

  // Nozzle rack (H2C, printer mode): filament group → 1-based rack position.
  // A group with no entry is left to the scheduler, which assigns from the rack
  // as it stands at dispatch.
  final Map<int, int> _nozzleRackChoice = {};

  // Print options
  late CalibrationOption _bedLevelling;
  late CalibrationOption _flowCali;
  late bool _vibrationCali;
  late bool _layerInspect;
  late bool _timelapse;
  late CalibrationOption _nozzleOffsetCali;

  // Preheat & heat soak
  late String _preheatOverride; // inherit | on | off
  late final TextEditingController _chamberTarget;

  // When to print
  late QueueScheduleType _scheduleType;
  DateTime? _scheduledTime;

  // Flags
  late bool _requireManualStart;
  late bool _requirePreviousSuccess;
  late bool _autoOffAfter;
  late bool _gcodeInjection;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    _modelMode = it.targetModel != null;
    _printerId = it.printerId;
    _targetModel = it.targetModel;
    _targetLocation = it.targetLocation;
    _amsMapping = it.amsMapping;
    _plateId = it.plateId;
    // Editing shows the item's own toggles. A new job has none, so it starts
    // from what the user last printed with — see [PrintOptions].
    final options = widget._isCreate
        ? ref.read(settingsRepositoryProvider).loadPrintOptions()
        : PrintOptions(
            bedLevelling: it.bedLevelling,
            flowCali: it.flowCali,
            vibrationCali: it.vibrationCali,
            layerInspect: it.layerInspect,
            timelapse: it.timelapse,
            nozzleOffsetCali: it.nozzleOffsetCali,
            gcodeInjection: it.gcodeInjection,
          );
    _bedLevelling = options.bedLevelling;
    _flowCali = options.flowCali;
    _vibrationCali = options.vibrationCali;
    _layerInspect = options.layerInspect;
    _timelapse = options.timelapse;
    _nozzleOffsetCali = options.nozzleOffsetCali;
    _gcodeInjection = options.gcodeInjection;
    _preheatOverride = it.preheatOverride;
    _chamberTarget = TextEditingController(
      text: it.preheatChamberTargetOverride?.toString() ?? '',
    );
    // Web maps a null/placeholder scheduled_time to Queue (ASAP is inert in
    // edit — insert_at_top is create-only); only a real timestamp is Schedule.
    // Create passes the segment it wants instead: printing now vs. lining a job
    // up are different intents, and the entry point is the one that knows which.
    _scheduledTime = it.scheduledTime;
    _scheduleType = widget.initialSchedule ??
        (it.scheduledTime != null
            ? QueueScheduleType.scheduled
            : QueueScheduleType.queue);
    _requireManualStart = it.manualStart;
    _requirePreviousSuccess = it.requirePreviousSuccess;
    _autoOffAfter = it.autoOffAfter;
    for (final o in it.filamentOverrides ?? const []) {
      final slot = (o['slot_id'] as num?)?.toInt();
      if (slot == null) continue;
      final type = o['type'] as String?;
      final color = o['color'] as String?;
      if (type != null && color != null) {
        _overrides[slot] = (type: type, color: color);
      }
      if (o['force_color_match'] == true) _forceColorMatch[slot] = true;
    }
    _nozzleRackChoice.addAll(it.nozzleRackChoice ?? const {});
  }

  @override
  void dispose() {
    _chamberTarget.dispose();
    super.dispose();
  }

  bool get _showNozzleOffset {
    final m = widget.item.slicedForModel?.toUpperCase();
    return m != null && _dualNozzleModels.contains(m);
  }

  /// Printer models the server has auto-print snippets for. Empty while
  /// `/settings` has not answered (or could not be read) — the injection
  /// checkbox stays hidden then, exactly as the web hides it.
  ///
  /// [watch] because the save path needs the same answer and `ref.watch` is
  /// build-only: the form watches so the checkbox appears once `/settings`
  /// answers, and [_submit] reads what is already resolved by then.
  Set<String> _snippetModels({required bool watch}) {
    final async = watch
        ? ref.watch(gcodeSnippetModelsProvider)
        : ref.read(gcodeSnippetModelsProvider);
    return async.valueOrNull ?? const {};
  }

  /// Whether the form may offer G-code injection at all.
  bool get _showGcodeInjection => _snippetModels(watch: true).isNotEmpty;

  /// The model this job will print on, as far as the form knows: the selected
  /// printer's own in printer mode, the chosen target otherwise. Null when the
  /// target is not settled yet, and then there is no snippet to check against.
  /// [watch] as in [_snippetModels].
  String? _resolvedTargetModel({required bool watch}) {
    if (_modelMode) return _targetModel ?? widget.item.slicedForModel;
    final async = watch
        ? ref.watch(allPrintersProvider)
        : ref.read(allPrintersProvider);
    for (final p in async.valueOrNull ?? const []) {
      if (p.id == _printerId) return p.model;
    }
    return null;
  }

  /// Warns that injection is on while the target model has no snippet, so the
  /// job will print exactly as sliced. Null when there is nothing to warn about.
  ///
  /// Shown twice on purpose: next to the checkbox, and again in the target
  /// section. The checkbox lives at the bottom of the form, and someone who came
  /// in only to change the printer never scrolls that far — while a remembered
  /// injection is precisely the setting they configured once and stopped
  /// watching. Same wording in both places, so it reads as one fact.
  Widget? _missingSnippetNote(
    AppLocalizations l10n,
    DashTokens t, {
    required EdgeInsets padding,
    bool announce = false,
  }) {
    final model = _modelMissingSnippet;
    return _note(
      t,
      model == null ? null : l10n.queueEditGcodeInjectionNoSnippet(model),
      padding: padding,
      announce: announce,
    );
  }

  /// A caveat under a control: what the form is about to do is not what the
  /// control looks like it does. Null [text] is "nothing to say", so a caller
  /// can hand its own condition straight in.
  ///
  /// Quiet by default — tertiary ink, not the amber a fault card uses. Most of
  /// these sit next to a setting the user chose and is still free to change,
  /// and the job prints either way.
  ///
  /// [urgent] is for the one that is not like that: a rack pick the live rack
  /// no longer satisfies fails the item at dispatch, *after* the upload, and
  /// nothing downstream softens it. Grey would have been an honest colour for
  /// every other note here and the wrong one for that.
  ///
  /// [announce] reads the note out when it appears. Only for a note that is the
  /// answer to the tap just made, and only where one of them appears at a time:
  /// a change that raises several — a printer swap can invalidate the rack pick
  /// of every filament group at once — would read them all out in a row, which
  /// is worse than the silence.
  Widget? _note(
    DashTokens t,
    String? text, {
    EdgeInsets padding = const EdgeInsets.only(top: 6),
    bool urgent = false,
    bool announce = false,
  }) {
    if (text == null) return null;
    final ink = urgent ? t.accentOrange : t.textTertiary;
    final row = Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: ink),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: urgent ? t.labelSoft.copyWith(color: ink) : t.labelSoft,
            ),
          ),
        ],
      ),
    );
    return announce
        ? Semantics(container: true, liveRegion: true, child: row)
        : row;
  }

  /// The target model when injection is asked for but that model has no snippet
  /// — the case where the scheduler silently prints without injecting anything.
  /// Null when there is nothing to warn about.
  String? get _modelMissingSnippet {
    if (!_gcodeInjection) return null;
    final model = _resolvedTargetModel(watch: true);
    if (model == null || model.isEmpty) return null;
    return _snippetModels(watch: true).contains(model) ? null : model;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(
          context,
          title: widget._isCreate ? l10n.queueCreateTitle : l10n.queueEditTitle,
          actions: [_submitAction(l10n, t)],
        ),
        body: AbsorbPointer(
          absorbing: _saving,
          child: ListView(
            padding: withSystemNavInset(
              context,
              const EdgeInsets.fromLTRB(16, 12, 16, 32),
            ),
            children: [
              _header(l10n, t),
              const SizedBox(height: 16),
              _targetSection(l10n, t),
              const SizedBox(height: 16),
              ?_plateSection(l10n, t),
              if (!_modelMode) ...[
                _mappingSection(l10n, t),
                const SizedBox(height: 16),
                ?_nozzleRackSection(l10n, t),
              ] else ...[
                _filamentOverrideSection(l10n, t),
                const SizedBox(height: 16),
              ],
              _printOptionsSection(l10n, t),
              const SizedBox(height: 16),
              _preheatSection(l10n, t),
              const SizedBox(height: 16),
              _scheduleSection(l10n, t),
            ],
          ),
        ),
      ),
    );
  }

  // --- Header (print job name + thumbnail) ---
  Widget _header(AppLocalizations l10n, DashTokens t) {
    final it = widget.item;
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: it.archiveId == null && it.libraryFileId != null
              ? LibraryThumbnail(
                  fileId: it.libraryFileId!,
                  hasThumbnail: it.libraryFileThumbnail != null,
                  size: 52,
                )
              : PrintThumbnail(archiveId: it.archiveId, size: 52),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.queueEditPrintJob,
                style: t.micro,
              ),
              const SizedBox(height: 2),
              Text(
                it.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.titleMd,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- Target: Specific Printer / Any <model> ---
  Widget _targetSection(AppLocalizations l10n, DashTokens t) {
    final printers = ref.watch(allPrintersProvider).valueOrNull ?? const [];
    final models = <String>{
      for (final p in printers)
        if (p.model != null && p.model!.isNotEmpty) p.model!,
    }.toList()
      ..sort();
    final locations = <String>{
      for (final p in printers)
        if (p.location != null && p.location!.isNotEmpty) p.location!,
    }.toList()
      ..sort();
    // Model dropdown mirrors web: hidden when the file has a known sliced model
    // (the target is fixed to it), shown only for model-agnostic files.
    final slicedModel = widget.item.slicedForModel;
    final modelFixed = slicedModel != null && slicedModel.isNotEmpty;
    final anyLabel = modelFixed
        ? l10n.queueEditAnyModel(slicedModel)
        : (_targetModel != null && _targetModel!.isNotEmpty
            ? l10n.queueEditAnyModel(_targetModel!)
            : l10n.queueEditAnyModelGeneric);

    return _SectionCard(
      title: l10n.queueEditTarget,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SegToggle<bool>(
            id: 'queue_edit.target_mode',
            selected: _modelMode,
            segments: [
              (value: false, label: l10n.queueEditSpecificPrinter, icon: Icons.print_outlined),
              (value: true, label: anyLabel, icon: Icons.groups_outlined),
            ],
            onChanged: (v) => setState(() {
              _modelMode = v;
              if (v) {
                _targetModel ??= modelFixed
                    ? slicedModel
                    : (models.isNotEmpty ? models.first : null);
              }
            }),
          ),
          const SizedBox(height: 12),
          if (!_modelMode)
            _printerList(l10n, t, printers)
          else
            _modelTarget(l10n, t, models, locations, modelFixed),
          ?_missingSnippetNote(l10n, t,
              padding: const EdgeInsets.only(top: 10)),
        ],
      ),
    );
  }

  Widget _printerList(AppLocalizations l10n, DashTokens t, List printers) {
    if (printers.isEmpty) {
      return Text(l10n.queueNoFreePrinters,
          style: t.bodyPlain.copyWith(color: t.textTertiary));
    }
    return Column(
      children: [
        for (final p in printers)
          _SelectableTile(
            selected: _printerId == p.id,
            title: p.name,
            subtitle: [
              if (p.model != null) p.model!,
              if (p.ipAddress != null) p.ipAddress!,
            ].join(' • '),
            onTap: () => setState(() {
              if (_printerId != p.id) _nozzleRackChoice.clear();
              _printerId = p.id;
            }),
          ).tagged('queue_edit.printer'),
      ],
    );
  }

  Widget _modelTarget(AppLocalizations l10n, DashTokens t, List<String> models,
      List<String> locations, bool modelFixed) {
    return Column(
      children: [
        if (!modelFixed && models.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _Dropdown<String?>(
              label: l10n.queueEditTargetModel,
              value: models.contains(_targetModel) ? _targetModel : null,
              placeholder: '—',
              items: [
                for (final m in models) (value: m, label: m, swatch: null),
              ],
              onChanged: (v) => setState(() => _targetModel = v),
            ),
          ),
        _Dropdown<String?>(
          label: l10n.queueEditTargetLocation,
          value: locations.contains(_targetLocation) ? _targetLocation : null,
          placeholder: l10n.queueEditAnyLocation,
          items: [
            (value: null, label: l10n.queueEditAnyLocation, swatch: null),
            for (final loc in locations)
              (value: loc, label: loc, swatch: null),
          ],
          onChanged: (v) => setState(() => _targetLocation = v),
        ),
      ],
    );
  }

  /// The one action of this screen, so it carries the app's primary-button fill
  /// instead of reading as a third piece of bar text next to the title and the
  /// back arrow. Compact padding and a shorter radius keep the pill inside the
  /// bar; the rest (colours, disabled state, weight) comes from
  /// [dashPrimaryButtonStyle] so it matches every other confirming button.
  Widget _submitAction(AppLocalizations l10n, DashTokens t) {
    return Padding(
      // Vertical inset leaves the pill room to grow with the text scale before
      // it meets the 56-high bar.
      padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
      child: FilledButton(
        style: dashPrimaryButtonStyle(t).copyWith(
          padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 18)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: _saving ? null : _submit,
        child: Text(
            widget._isCreate ? l10n.queueCreateSubmit : l10n.queueEditSave),
      ).tagged(widget._isCreate ? 'queue_create.save' : 'queue_edit.save'),
    );
  }

  /// Name of the printer picked in the Target section, for messages that would
  /// otherwise quote the item's stored (or, on a draft, missing) printer.
  String? _selectedPrinterName(int printerId) {
    for (final p in ref.read(allPrintersProvider).valueOrNull ?? const []) {
      if (p.id == printerId) return p.name;
    }
    return null;
  }

  // --- Filament mapping (printer mode) ---
  // --- Plate (multi-plate 3MF only) ---

  /// Which plate to print, for a file that has more than one.
  ///
  /// Null — the section is absent — for everything else: a single-plate file, a
  /// source the plates route cannot answer for, an older server without that
  /// route, and an item with no file behind it yet. A form that looks exactly as
  /// it did before is the correct answer to all of those.
  ///
  /// Read-only while editing an existing item. The plate decides which filament
  /// slots the job needs, and those are already mapped by then — changing it
  /// here would leave a mapping pointing at another plate's slots without
  /// anything saying so. A reprint is a *new* item, which is where the choice
  /// belongs.
  Widget? _plateSection(AppLocalizations l10n, DashTokens t) {
    final it = widget.item;
    final source = it.archiveId != null
        ? (true, it.archiveId!)
        : (it.libraryFileId != null ? (false, it.libraryFileId!) : null);
    if (source == null) return null;
    final plates =
        ref.watch(plateListProvider(source)).valueOrNull ?? PlateList.none;
    if (!plates.isMultiPlate) return null;

    final current = plates.byIndex(_plateId);
    final label = current == null
        ? l10n.queueEditPlateSelected(_plateId ?? 1)
        : plateLabel(l10n, current);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(Icons.layers_outlined, color: t.textSecondary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget._isCreate ? label : l10n.queueEditPlateFixed(_plateId ?? 1),
              style: t.body,
            ),
          ),
          if (widget._isCreate) Icon(Icons.chevron_right, color: t.textTertiary),
        ],
      ),
    );

    return Column(
      children: [
        _SectionCard(
          title: l10n.queueEditPlate,
          child: widget._isCreate
              ? InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _pickPlate(plates),
                  child: row,
                ).tagged('queue_edit.plate')
              : row,
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// Picking a plate drops the AMS mapping: it maps slot indexes of the plate it
  /// was built for, and another plate's slots are another set. Left in place it
  /// would send the printer to trays the new plate never asked about — better to
  /// fall back to the server's own auto-match, which is what an untouched
  /// mapping means.
  Future<void> _pickPlate(PlateList plates) async {
    final picked = await showQueuePlateSheet(
      context,
      plates: plates,
      selected: _plateId,
    );
    if (picked == null || picked == _plateId || !mounted) return;
    setState(() {
      _plateId = picked;
      _amsMapping = null;
      // The pick names filament groups of the plate it was made for; another
      // plate's groups are another set, and a group id that survives means a
      // position chosen for a filament nobody asked about.
      _nozzleRackChoice.clear();
    });
  }

  Widget _mappingSection(AppLocalizations l10n, DashTokens t) {
    final mapped = _amsMapping?.where((v) => v >= 0).length ?? 0;
    final printerId = _printerId;
    return _SectionCard(
      title: l10n.queueFilamentMapping,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: printerId == null
            ? null
            : () async {
                final mapping = await showQueueMappingSheet(
                  context,
                  item: widget.item,
                  printerId: printerId,
                  printerName: _selectedPrinterName(printerId),
                  confirmLabel: l10n.fmSave,
                  plateId: _plateId,
                );
                if (mapping != null) setState(() => _amsMapping = mapping);
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(Icons.bento_outlined, color: t.textSecondary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  printerId == null
                      ? l10n.queueEditMappingNeedsPrinter
                      : (mapped > 0
                          ? l10n.queueEditMappingSummary(mapped)
                          : l10n.queueEditMappingAuto),
                  style: t.body,
                ),
              ),
              if (printerId != null)
                Icon(Icons.chevron_right, color: t.textTertiary),
            ],
          ),
        ),
      ).tagged('queue_edit.mapping'),
    );
  }

  // --- Nozzle rack (H2C, printer mode) ---

  /// The rack-bound filament groups of the plate about to print, lowest id
  /// first — the unit a rack position is chosen for.
  ///
  /// Groups rather than slots: two slots in one group share a hotend and cannot
  /// be pointed at different positions. Empty on every plate the server did not
  /// annotate, which is every plate not sliced for a rack printer and every
  /// plate at all on a server that predates the group table.
  List<({int id, RackGroup need, List<int> slots})> _rackGroups() {
    final slotsByGroup = <int, List<int>>{};
    final needByGroup = <int, RackGroup>{};
    for (final requirement in _parsedRequirements()) {
      final id = requirement.groupId;
      final need = requirement.group;
      if (id == null || need == null || !need.onRack) continue;
      needByGroup[id] = need;
      (slotsByGroup[id] ??= []).add(requirement.slotId);
    }
    final ids = needByGroup.keys.toList()..sort();
    return [
      for (final id in ids)
        (id: id, need: needByGroup[id]!, slots: slotsByGroup[id]!..sort()),
    ];
  }

  /// Which rack nozzle each filament group prints from, or null when there is no
  /// choice to offer.
  ///
  /// Three things have to hold, and each absence is itself the answer "leave it
  /// to the scheduler": a specific printer is targeted (a model target cannot
  /// name a rack, and a pick the server cannot satisfy stops the print rather
  /// than degrading), that printer reports a rack, and the plate has groups
  /// bound to it. So no version check is needed — an older server annotates no
  /// groups and reports no rack, and the section simply never appears.
  Widget? _nozzleRackSection(AppLocalizations l10n, DashTokens t) {
    final printerId = _printerId;
    if (printerId == null) return null;
    final groups = _rackGroups();
    if (groups.isEmpty) return null;
    final rack = rackByPosition(
      ref.watch(printerStatusOnceProvider(printerId)).valueOrNull?.nozzleRack,
    );
    if (rack.isEmpty) return null;

    return Column(
      children: [
        _SectionCard(
          title: l10n.queueEditNozzleRack,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.queueEditNozzleRackDesc, style: t.labelSoft),
              const SizedBox(height: 12),
              for (final group in groups) _rackGroupRow(l10n, t, group, rack),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _rackGroupRow(
    AppLocalizations l10n,
    DashTokens t,
    ({int id, RackGroup need, List<int> slots}) group,
    Map<int, NozzleRackSlot> rack,
  ) {
    final taken = {
      for (final entry in _nozzleRackChoice.entries)
        if (entry.key != group.id) entry.value,
    };
    final fits = {
      for (final entry in rack.entries)
        if (rackSlotFits(entry.value,
            diameter: group.need.nozzleDiameter,
            volumeType: group.need.volumeType))
          entry.key,
    };
    final positions = rack.keys.toList()..sort();
    final needed = _nozzleLabel(
      l10n,
      diameter: group.need.nozzleDiameter,
      highFlow: highFlowFromName(group.need.volumeType),
    );
    // A pick the live rack no longer satisfies is the one case the server does
    // not paper over: it fails the item at dispatch, after the upload, rather
    // than choosing something else. Say so while it can still be changed.
    final picked = _nozzleRackChoice[group.id];
    final stale = picked != null && !fits.contains(picked);
    final warning = stale
        ? l10n.queueEditRackPickStale
        : (fits.isEmpty ? l10n.queueEditRackNoFit(needed) : null);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Dropdown<int?>(
            label: l10n.queueEditRackGroupLabel(
                group.slots.map((s) => '$s').join(', '), needed),
            value: _nozzleRackChoice[group.id],
            placeholder: l10n.queueEditRackAuto,
            items: [
              (value: null, label: l10n.queueEditRackAuto, swatch: null),
              for (final position in positions)
                (
                  value: position,
                  label: _rackPositionLabel(
                    l10n,
                    position,
                    rack[position]!,
                    fits: fits.contains(position),
                    taken: taken.contains(position),
                  ),
                  swatch: null,
                ),
            ],
            // A position the nozzle does not fit, and one another group already
            // holds, are both refused at dispatch — the pick is checked against
            // the live rack there, and a stale one fails the print instead of
            // falling back. Better to refuse it here, where it costs a tap.
            disabled: {
              for (final position in positions)
                if (!fits.contains(position) || taken.contains(position))
                  position,
            },
            onChanged: (picked) => setState(() {
              if (picked == null) {
                _nozzleRackChoice.remove(group.id);
              } else {
                _nozzleRackChoice[group.id] = picked;
              }
            }),
          ),
          ?_note(t, warning, urgent: stale),
        ],
      ),
    );
  }

  /// One row of the picker: the position, what it holds, and — when it cannot
  /// be taken — which of the two reasons that is.
  ///
  /// The reason is in the label rather than left to the greying out: a disabled
  /// row otherwise reads as "unavailable, no idea why", and a screen reader
  /// announces it as dimmed and stops there. Not fitting outranks being taken,
  /// because freeing the position would not help this group either.
  String _rackPositionLabel(
    AppLocalizations l10n,
    int position,
    NozzleRackSlot slot, {
    required bool fits,
    required bool taken,
  }) {
    final held = _rackSlotLabel(l10n, slot);
    if (!fits) return l10n.queueEditRackPositionUnfit(position, held);
    if (taken) return l10n.queueEditRackPositionTaken(position, held);
    return l10n.queueEditRackPosition(position, held);
  }

  /// What one rack position holds, or the empty-dock label.
  String _rackSlotLabel(AppLocalizations l10n, NozzleRackSlot slot) =>
      slot.isEmpty
          ? l10n.queueEditRackEmpty
          : _nozzleLabel(
              l10n,
              diameter: slot.nozzleDiameter ?? '',
              highFlow: highFlowFromCode(slot.nozzleType),
            );

  /// A nozzle as both sides of this screen name it: `0.4 High flow`. The flow
  /// type is dropped when nothing states it, rather than guessed at standard.
  String _nozzleLabel(
    AppLocalizations l10n, {
    required String diameter,
    required bool? highFlow,
  }) {
    final size = nozzleDiameterLabel(diameter);
    final flow = switch (highFlow) {
      true => l10n.nozzleFlowHigh,
      false => l10n.nozzleFlowStandard,
      null => '',
    };
    return [size, flow].where((part) => part.isNotEmpty).join(' ');
  }

  // --- Filament override (model mode) ---

  /// The filament slots as the server parsed them out of the 3MF, or empty when
  /// the job has no source to parse (a queued reprint whose archive is created
  /// only at print start) and while the request is in flight.
  ///
  /// Separate from [_requirements] because that one flattens the records down to
  /// what the override rows need, and the rack picker needs the filament-group
  /// table only the parsed form carries.
  List<FilamentRequirement> _parsedRequirements() {
    final it = widget.item;
    if (it.archiveId != null) {
      return ref
              .watch(filamentRequirementsProvider(
                  (isArchive: true, id: it.archiveId!, plate: _plateId ?? 1)))
              .valueOrNull ??
          const [];
    }
    if (it.libraryFileId != null) {
      return ref
              .watch(filamentRequirementsProvider((
                isArchive: false,
                id: it.libraryFileId!,
                plate: _plateId ?? 1,
              )))
              .valueOrNull ??
          const [];
    }
    return const [];
  }

  /// Required filament slots for the queued file. Prefers the parsed 3MF
  /// requirements (archive/library source); falls back to the item's own
  /// comma-separated `filament_type`/`filament_color` when there is no source
  /// yet (e.g. a queued reprint whose archive is created only at print start).
  List<({int slotId, String type, String color})> _requirements() {
    final it = widget.item;
    final reqs = _parsedRequirements();
    if (reqs.isNotEmpty) {
      return [
        for (final r in reqs)
          (slotId: r.slotId, type: r.type ?? '', color: r.color ?? ''),
      ];
    }
    final types = (it.filamentType ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final colors =
        (it.filamentColor ?? '').split(',').map((s) => s.trim()).toList();
    return [
      for (var i = 0; i < types.length; i++)
        (
          slotId: i + 1,
          type: types[i],
          color: i < colors.length ? colors[i] : '',
        ),
    ];
  }

  Widget _filamentOverrideSection(AppLocalizations l10n, DashTokens t) {
    final model = _targetModel ?? '';
    final available = model.isEmpty
        ? const <AvailableFilament>[]
        : (ref
                .watch(availableFilamentsProvider((model, _targetLocation ?? '')))
                .valueOrNull ??
            const <AvailableFilament>[]);
    final reqs = _requirements();
    return _SectionCard(
      title: l10n.queueEditFilamentOverride,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.queueEditFilamentOverrideDesc,
            style: t.labelSoft,
          ),
          const SizedBox(height: 12),
          if (reqs.isEmpty)
            Text(
              l10n.queueEditNoFilamentReqs,
              style: t.bodyPlain.copyWith(color: t.textTertiary),
            )
          else
            for (final r in reqs) _overrideRow(l10n, t, r, available),
        ],
      ),
    );
  }

  Widget _overrideRow(
    AppLocalizations l10n,
    DashTokens t,
    ({int slotId, String type, String color}) req,
    List<AvailableFilament> available,
  ) {
    // Same-material options only (uppercase compare — good enough without the
    // full canonical grouping the web does for CF families).
    final canon = req.type.trim().toUpperCase();
    final compatible = [
      for (final f in available)
        if (f.type.trim().toUpperCase() == canon) f,
    ];
    final override = _overrides[req.slotId];
    final selected = override == null ? null : '${override.type}|${override.color}';
    final typeLabel = req.type.isEmpty ? '—' : req.type;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Dropdown<String?>(
            label: l10n.queueEditSlotLabel('${req.slotId}', typeLabel),
            value: selected,
            placeholder: l10n.queueEditOriginal,
            items: [
              (
                value: null,
                label: '${l10n.queueEditOriginal}: $typeLabel',
                swatch: _swatch(req.color),
              ),
              for (final f in compatible)
                (
                  value: '${f.type}|${f.color}',
                  label: f.label,
                  swatch: _swatch(f.color),
                ),
            ],
            onChanged: (v) => setState(() {
              if (v == null) {
                _overrides.remove(req.slotId);
              } else {
                final parts = v.split('|');
                _overrides[req.slotId] =
                    (type: parts[0], color: parts.length > 1 ? parts[1] : '');
              }
            }),
          ),
          _CheckRow(
            id: 'queue_edit.force_color_match',
            icon: Icons.palette_outlined,
            label: l10n.queueEditForceColorMatch,
            value: _forceColorMatch[req.slotId] ?? false,
            onChanged: (v) => setState(() {
              if (v) {
                _forceColorMatch[req.slotId] = true;
              } else {
                _forceColorMatch.remove(req.slotId);
              }
            }),
          ),
        ],
      ),
    );
  }

  /// Build the `filament_overrides` payload (model mode). Mirrors the web rule:
  /// include a slot iff the user overrode it OR force-color-match is on; a
  /// force-only slot carries the ORIGINAL type/color. Returns null when empty
  /// (sent as an explicit clear). `color_name` has no catalogue on mobile, so
  /// the hex stands in — the backend uses it only for display messages.
  List<Map<String, dynamic>>? _buildFilamentOverrides() {
    final entries = <Map<String, dynamic>>[];
    for (final r in _requirements()) {
      final ov = _overrides[r.slotId];
      final force = _forceColorMatch[r.slotId] ?? false;
      if (ov == null && !force) continue;
      final type = ov?.type ?? r.type;
      final color = ov?.color ?? r.color;
      entries.add({
        'slot_id': r.slotId,
        'type': type,
        'color': color,
        'color_name': color,
        'force_color_match': force,
      });
    }
    return entries.isEmpty ? null : entries;
  }

  Color? _swatch(String hex) => colorFromHex(hex);

  // --- Print options ---
  Widget _printOptionsSection(AppLocalizations l10n, DashTokens t) {
    // Two states until the server is known to have a third. A pre-1.2.5 server
    // rejects `auto` outright, so offering the position before the probe answers
    // would promise something we cannot deliver.
    final triState =
        ref.watch(triStateCalibrationProvider).valueOrNull ?? false;
    return _SectionCard(
      title: l10n.queueEditPrintOptions,
      child: Column(
        children: [
          _CalibrationRow(
            id: 'queue_edit.bed_levelling',
            title: l10n.queueOptBedLevelling,
            subtitle: l10n.queueOptBedLevellingDesc,
            value: _bedLevelling,
            triState: triState,
            onChanged: (v) => setState(() => _bedLevelling = v),
          ),
          _CalibrationRow(
            id: 'queue_edit.flow_cali',
            title: l10n.queueOptFlowCali,
            subtitle: l10n.queueOptFlowCaliDesc,
            value: _flowCali,
            triState: triState,
            onChanged: (v) => setState(() => _flowCali = v),
          ),
          _OptionSwitch(
            id: 'queue_edit.vibration_cali',
            title: l10n.queueOptVibrationCali,
            subtitle: l10n.queueOptVibrationCaliDesc,
            value: _vibrationCali,
            onChanged: (v) => setState(() => _vibrationCali = v),
          ),
          _OptionSwitch(
            id: 'queue_edit.layer_inspect',
            title: l10n.queueOptLayerInspect,
            subtitle: l10n.queueOptLayerInspectDesc,
            value: _layerInspect,
            onChanged: (v) => setState(() => _layerInspect = v),
          ),
          _OptionSwitch(
            id: 'queue_edit.timelapse',
            title: l10n.queueOptTimelapse,
            subtitle: l10n.queueOptTimelapseDesc,
            value: _timelapse,
            onChanged: (v) => setState(() => _timelapse = v),
          ),
          if (_showNozzleOffset)
            _CalibrationRow(
              id: 'queue_edit.nozzle_offset_cali',
              title: l10n.queueOptNozzleOffset,
              subtitle: l10n.queueOptNozzleOffsetDesc,
              value: _nozzleOffsetCali,
              triState: triState,
              onChanged: (v) => setState(() => _nozzleOffsetCali = v),
            ),
        ],
      ),
    );
  }

  // --- Preheat & heat soak ---
  Widget _preheatSection(AppLocalizations l10n, DashTokens t) {
    return _SectionCard(
      title: l10n.queueEditPreheat,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.queueEditPreheatDesc,
            style: t.labelSoft,
          ),
          const SizedBox(height: 12),
          _SegToggle<String>(
            id: 'queue_edit.preheat_override',
            selected: _preheatOverride,
            segments: [
              (value: 'inherit', label: l10n.queuePreheatInherit, icon: null),
              (value: 'on', label: l10n.commonOn, icon: null),
              (value: 'off', label: l10n.commonOff, icon: null),
            ],
            onChanged: (v) => setState(() => _preheatOverride = v),
          ),
          if (_preheatOverride != 'off') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _chamberTarget,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: t.bodyStrong,
              decoration: dashFieldDecoration(
                t,
                labelText: l10n.queueEditChamberTarget,
                hintText: '—',
                // States the ceiling rather than silently clamping to it: the
                // value differs by server version (60 / 65), so a bare field
                // gives no way to tell what this one will accept.
                helperText: l10n.queueEditChamberTargetRange(_chamberMax),
              ),
            ).tagged('queue_edit.chamber_target'),
          ],
        ],
      ),
    );
  }

  // --- When to print ---
  Widget _scheduleSection(AppLocalizations l10n, DashTokens t) {
    return _SectionCard(
      title: l10n.queueEditWhenToPrint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SegToggle<QueueScheduleType>(
            id: 'queue_edit.schedule_type',
            selected: _scheduleType,
            segments: [
              (value: QueueScheduleType.asap, label: l10n.queueScheduleAsap, icon: Icons.schedule),
              (value: QueueScheduleType.queue, label: l10n.queueScheduleQueue, icon: Icons.list),
              (value: QueueScheduleType.scheduled, label: l10n.queueScheduleSchedule, icon: Icons.calendar_today),
            ],
            onChanged: (v) => setState(() {
              _scheduleType = v;
              // Manual start only makes sense in Queue mode (matches web).
              if (v != QueueScheduleType.queue) _requireManualStart = false;
            }),
          ),
          if (_scheduleType == QueueScheduleType.scheduled) ...[
            const SizedBox(height: 12),
            _scheduleTimeRow(l10n, t),
          ],
          const SizedBox(height: 8),
          if (_scheduleType == QueueScheduleType.queue)
            _CheckRow(
              id: 'queue_edit.require_manual_start',
              icon: Icons.pan_tool_outlined,
              label: l10n.queueEditRequireManualStart,
              value: _requireManualStart,
              onChanged: (v) => setState(() => _requireManualStart = v),
            ),
          _CheckRow(
            id: 'queue_edit.require_previous',
            icon: Icons.check_circle_outline,
            label: l10n.queueEditRequirePrevious,
            value: _requirePreviousSuccess,
            onChanged: (v) => setState(() => _requirePreviousSuccess = v),
          ),
          _CheckRow(
            id: 'queue_edit.power_off',
            icon: Icons.power_settings_new,
            label: l10n.queueEditPowerOff,
            value: _autoOffAfter,
            onChanged: (v) => setState(() => _autoOffAfter = v),
          ),
          // Injection is offered only while the server actually holds snippets:
          // the flag does nothing without them, and the web gates it the same way.
          if (_showGcodeInjection)
            _CheckRow(
              id: 'queue_edit.gcode_injection',
              icon: Icons.code,
              label: l10n.queueEditGcodeInjection,
              value: _gcodeInjection,
              onChanged: (v) => setState(() => _gcodeInjection = v),
            ),
          // Announced, unlike its twin in the target section: this one appears
          // as the direct answer to the tap just made, and a reader that says
          // nothing leaves the tick looking like it worked. Only one of the two
          // says it, or the same sentence is read out twice.
          ?_missingSnippetNote(l10n, t,
              padding: const EdgeInsets.only(left: 4, top: 2), announce: true),
        ],
      ),
    );
  }

  Widget _scheduleTimeRow(AppLocalizations l10n, DashTokens t) {
    final label = _scheduledTime == null
        ? l10n.queueEditPickTime
        : DateTimeFormats.of(context).dateTime(_scheduledTime!);
    return Row(
      children: [
        Icon(Icons.event_outlined, color: t.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: t.monoValue,
          ),
        ),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: t.textPrimary,
            side: BorderSide(color: t.cardBorder),
          ),
          onPressed: _pickScheduledTime,
          child: Text(l10n.queueEditPickTime),
        ).tagged('queue_edit.pick_time'),
      ],
    );
  }

  Future<void> _pickScheduledTime() async {
    // Yesterday, not today: this form also edits a job whose time has already
    // passed, and a calendar that refused to show that day would make picking
    // "the same day, an hour later" impossible.
    final picked = await pickDateTime(
      context,
      initial: _scheduledTime,
      firstDate: clock.now().subtract(const Duration(days: 1)),
    );
    if (picked == null || !mounted) return;
    setState(() => _scheduledTime = picked);
  }

  // --- Save ---
  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    if (_modelMode && (_targetModel == null || _targetModel!.isEmpty)) {
      messenger.snack(l10n.queueEditNoModel);
      return;
    }
    if (!_modelMode && _printerId == null) {
      messenger.snack(l10n.queueEditNoPrinter);
      return;
    }

    setState(() => _saving = true);
    _logGcodeInjection();

    final result = await ref
        .read(queueProvider.notifier)
        .runAction(widget._isCreate ? _create : _update,
            widget._isCreate ? 'queue_edit.create' : 'queue_edit.save');

    // Remember the toggles only once a job was really created with them.
    // Editing an existing item is about THAT item — treating it as "what I print
    // with" would let a one-off tweak follow the user into every later job.
    if (widget._isCreate && result.isOk) {
      await ref.read(settingsRepositoryProvider).savePrintOptions(_options);
    }

    if (!mounted) return;
    setState(() => _saving = false);
    final ok = widget._isCreate ? l10n.queueCreateAdded : l10n.queueEditSaved;
    messenger.snack(result.messageFor(l10n) ?? ok);
    // Create pops `true` — its caller (a list of archives or files) refreshes
    // what it shows only when something was really added.
    if (result.isOk) navigator.pop(widget._isCreate);
  }

  /// The print toggles as they stand in the form.
  PrintOptions get _options => PrintOptions(
        bedLevelling: _bedLevelling,
        flowCali: _flowCali,
        vibrationCali: _vibrationCali,
        layerInspect: _layerInspect,
        timelapse: _timelapse,
        nozzleOffsetCali: _nozzleOffsetCali,
        gcodeInjection: _gcodeInjection,
      );

  /// The injection flag as it may ship, or null to leave the key out.
  ///
  /// Null while the form is not offering the checkbox: create then falls back to
  /// the server's own default (off), and update leaves the stored value alone
  /// instead of rewriting it from a control the user could not see. A remembered
  /// ON from a server that has snippets therefore cannot follow the user onto one
  /// that has none.
  bool? get _gcodeInjectionPayload =>
      _snippetModels(watch: false).isEmpty ? null : _gcodeInjection;

  /// Records what the injection flag did to this save.
  ///
  /// The request body never reaches the log (only responses are sampled), and
  /// this is the one option that can be ticked and still do nothing: the
  /// scheduler skips a model it has no snippet for, and says so in the server's
  /// own log rather than anywhere the user can see. `sent` separates "the user
  /// wanted it" from "the key shipped", and `match` answers whether the target
  /// model had a snippet at all — the two questions a "my plate did not swap"
  /// report turns on.
  ///
  /// `models` is a count and `match` a boolean on purpose: a printer model is
  /// user data, and the count is all that "were snippets configured" needs.
  /// Silent when there is nothing to say — no snippets and nothing asked for.
  void _logGcodeInjection() {
    final models = _snippetModels(watch: false);
    if (models.isEmpty && !_gcodeInjection) return;
    DiagnosticRecorder.active?.add(
      LogSource.app,
      'queue_gcode_injection',
      fields: {
        'on': _gcodeInjection,
        'sent': _gcodeInjectionPayload != null,
        'models': models.length,
        'match': _gcodeInjection &&
            models.contains(_resolvedTargetModel(watch: false)),
      },
    );
  }

  /// `scheduled_time` as ISO (UTC), only when scheduling. Null on the update
  /// path is an explicit clear (back to ASAP/queue); on create it is simply
  /// omitted from the body.
  String? get _scheduledTimeIso =>
      _scheduleType == QueueScheduleType.scheduled && _scheduledTime != null
          ? _scheduledTime!.toUtc().toIso8601String()
          : null;

  /// The server's chamber ceiling — 65 from 1.2.6, 60 before it and until the
  /// version is known.
  static int _ceiling(AsyncValue<int> probe) =>
      probe.maybeWhen(data: (v) => v, orElse: () => 60);

  /// `watch`, so the helper text stops advertising 60 the moment the version
  /// probe answers with the form already open.
  int get _chamberMax => _ceiling(ref.watch(chamberMaxTargetProvider));

  int? get _chamberTargetValue {
    if (_preheatOverride == 'off') return null;
    // `read`: this one runs from the save button, outside a build.
    final max = _ceiling(ref.read(chamberMaxTargetProvider));
    return parseUserInt(_chamberTarget.text)?.clamp(0, max);
  }

  /// A calibration option for the PATCH body, or `null` to leave the key out.
  ///
  /// Unchanged means unsent. That matters when the server has an `auto` stored
  /// but this build is showing two states (an older server, or a probe that has
  /// not answered): the switch renders `auto` as ON, and sending that back would
  /// rewrite the user's `auto` as a plain `on` for a value they never touched.
  CalibrationOption? _calibrationUpdate(
    CalibrationOption current,
    CalibrationOption stored,
  ) =>
      current == stored ? null : current;

  Future<void> _update(QueueRepository repo) => repo.updateItem(
        widget.item.id,
        printerId: _modelMode ? null : _printerId,
        targetModel: _modelMode ? _targetModel : null,
        targetLocation: _modelMode ? _targetLocation : null,
        amsMapping: _modelMode ? kQueueUpdateUnset : _amsMapping,
        filamentOverrides:
            _modelMode ? _buildFilamentOverrides() : kQueueUpdateUnset,
        scheduledTime: _scheduledTimeIso,
        requirePreviousSuccess: _requirePreviousSuccess,
        autoOffAfter: _autoOffAfter,
        manualStart:
            _scheduleType == QueueScheduleType.queue && _requireManualStart,
        bedLevelling:
            _calibrationUpdate(_bedLevelling, widget.item.bedLevelling),
        flowCali: _calibrationUpdate(_flowCali, widget.item.flowCali),
        vibrationCali: _vibrationCali,
        layerInspect: _layerInspect,
        timelapse: _timelapse,
        nozzleOffsetCali: _showNozzleOffset
            ? _calibrationUpdate(
                _nozzleOffsetCali, widget.item.nozzleOffsetCali)
            : null,
        gcodeInjection: _gcodeInjectionPayload,
        preheatOverride: _preheatOverride,
        preheatChamberTargetOverride: _chamberTargetValue,
        nozzleRackChoice: _rackChoiceUpdate,
      );

  /// The rack pick for a PATCH: the chosen positions, `null` to clear one the
  /// item still carries, and [kQueueUpdateUnset] when there is nothing to say —
  /// which is every item on every printer without a rack, and the only shape a
  /// server that predates the field ever sees.
  Object? get _rackChoiceUpdate {
    final stored = widget.item.nozzleRackChoice ?? const <int, int>{};
    final picked = _modelMode ? const <int, int>{} : _nozzleRackChoice;
    if (picked.isEmpty && stored.isEmpty) return kQueueUpdateUnset;
    return picked.isEmpty ? null : picked;
  }

  Future<void> _create(QueueRepository repo) {
    final it = widget.item;
    final options = QueueCreateOptions(
      plateId: _plateId,
      targetModel: _modelMode ? _targetModel : null,
      targetLocation: _modelMode ? _targetLocation : null,
      filamentOverrides: _modelMode ? _buildFilamentOverrides() : null,
      amsMapping: _modelMode ? null : _amsMapping,
      scheduledTime: _scheduledTimeIso,
      requirePreviousSuccess: _requirePreviousSuccess,
      autoOffAfter: _autoOffAfter,
      manualStart:
          _scheduleType == QueueScheduleType.queue && _requireManualStart,
      bedLevelling: _bedLevelling,
      flowCali: _flowCali,
      vibrationCali: _vibrationCali,
      layerInspect: _layerInspect,
      timelapse: _timelapse,
      nozzleOffsetCali: _showNozzleOffset ? _nozzleOffsetCali : null,
      gcodeInjection: _gcodeInjectionPayload,
      preheatOverride: _preheatOverride,
      preheatChamberTargetOverride: _chamberTargetValue,
      nozzleRackChoice: _modelMode ? null : _nozzleRackChoice,
    );
    // ASAP is a position at insertion, not a stored field — the web sends it the
    // same way, and it is what makes "reprint" print next.
    final insertAtTop = _scheduleType == QueueScheduleType.asap;
    final printerId = _modelMode ? null : _printerId;
    return it.archiveId != null
        ? repo.addFromArchive(it.archiveId!,
            printerId: printerId, insertAtTop: insertAtTop, options: options)
        : repo.addFromLibraryFile(it.libraryFileId!,
            printerId: printerId, insertAtTop: insertAtTop, options: options);
  }
}

/// Imperative entry: open the Edit Queue Item screen for [item].
Future<void> openQueueEdit(BuildContext context, QueueItem item) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => QueueEditScreen(item: item)),
    );

/// Imperative entry: configure a NEW queue item and post it. [draft] carries the
/// source and starting values ([QueueItem.draft]); [schedule] picks the segment
/// the form opens on — ASAP for "print this now", Queue for "line this up".
///
/// Returns true when an item was created, so the caller can refresh what it
/// shows. The queue itself is already refreshed by then.
Future<bool> openQueueCreate(
  BuildContext context, {
  required QueueItem draft,
  QueueScheduleType schedule = QueueScheduleType.asap,
}) async {
  final created = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => QueueEditScreen(
        item: draft,
        mode: QueueEditMode.create,
        initialSchedule: schedule,
      ),
    ),
  );
  return created ?? false;
}

// ---------------------------------------------------------------------------
// Local building blocks
// ---------------------------------------------------------------------------

/// Titled card wrapper matching the app's grouped-section look.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.subCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.subCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: t.bodyBold.copyWith(letterSpacing: 0.2),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// A segment for [_SegToggle].
typedef _Segment<T> = ({T value, String label, IconData? icon});

/// Horizontal pill toggle (Specific/Any, Inherit/On/Off, ASAP/Queue/Schedule).
/// Selected segment is green-filled; the rest are neutral.
class _SegToggle<T> extends StatelessWidget {
  const _SegToggle({
    required this.id,
    required this.selected,
    required this.segments,
    required this.onChanged,
  });

  /// Log identifier, required from the call site — see [_CheckRow.id]. Six of
  /// these are rendered on this screen and they set six different things, so a
  /// tag written into `build` made a report say only that "a segment in the
  /// queue form" was pressed.
  final String id;

  final T selected;
  final List<_Segment<T>> segments;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Row(
      children: [
        for (var i = 0; i < segments.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _segButton(t, segments[i]),
          ),
        ],
      ],
    );
  }

  Widget _segButton(DashTokens t, _Segment<T> seg) {
    final isSel = seg.value == selected;
    return Material(
      color: isSel ? t.accentGreen : t.groupCard,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onChanged(seg.value),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSel ? Colors.transparent : t.groupCardBorder,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (seg.icon != null) ...[
                Icon(seg.icon,
                    size: 16,
                    color: isSel ? _onGreenFill : t.textSecondary),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  seg.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyBold.copyWith(color: isSel ? _onGreenFill : t.textPrimary),
                ),
              ),
            ],
          ),
        ),
        // The fill is the only thing that says which segment is on.
      ).tagged(id, selected: isSel),
    );
  }
}

/// Title + subtitle row with a trailing [Switch] (print options).
/// One tri-state calibration option.
///
/// bambuddy 1.2.5+ stores `off` / `on` / `auto`, so the row is a three-way
/// segment. Older servers only have the boolean, and they are the reason this
/// falls back to [_OptionSwitch] rather than greying a third position out: a
/// position the server cannot store has no honest disabled state, it simply does
/// not exist there.
///
/// The fallback maps `auto` onto the switch's ON side ([CalibrationOption.asSwitch]).
/// That reads right — `auto` still lets the printer calibrate — and it cannot
/// quietly rewrite the stored value, because the save path omits an untouched
/// field entirely (see `_calibrationUpdate`).
class _CalibrationRow extends StatelessWidget {
  const _CalibrationRow({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.triState,
    required this.onChanged,
  });

  /// One id for both shapes this row takes: the three-way segment and the
  /// two-state switch an older server falls back to are the same setting, and a
  /// log that split them would be naming the server's version rather than the
  /// control the user touched.
  final String id;

  final String title;
  final String subtitle;
  final CalibrationOption value;
  final bool triState;
  final ValueChanged<CalibrationOption> onChanged;

  @override
  Widget build(BuildContext context) {
    if (!triState) {
      return _OptionSwitch(
        id: id,
        title: title,
        subtitle: subtitle,
        value: value.asSwitch,
        onChanged: (v) =>
            onChanged(v ? CalibrationOption.on : CalibrationOption.off),
      );
    }
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: t.titleSm,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: t.labelSoft,
          ),
          const SizedBox(height: 8),
          _SegToggle<CalibrationOption>(
            id: id,
            selected: value,
            segments: [
              (
                value: CalibrationOption.auto,
                label: l10n.commonAuto,
                icon: null
              ),
              (value: CalibrationOption.on, label: l10n.commonOn, icon: null),
              (value: CalibrationOption.off, label: l10n.commonOff, icon: null),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _OptionSwitch extends StatelessWidget {
  const _OptionSwitch({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  /// Log identifier, required from the call site — see [_CheckRow.id].
  final String id;

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      // Merged, so the switch is announced with the setting it belongs to. On
      // its own it read as "off, switch" — six of these sit on this screen and
      // nothing said which one had focus. The probe treats a merged subtree as
      // one control and keeps the identifier, so the log is unchanged.
      child: MergeSemantics(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: t.titleSm,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: t.labelSoft,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(
              value: value,
              activeThumbColor: Colors.white,
              activeTrackColor: t.accentGreen,
              onChanged: onChanged,
            ).tagged(id),
          ],
        ),
      ),
    );
  }
}

/// Leading-icon checkbox row (schedule flags).
class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.id,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  /// Log identifier, required from the call site: one shared tag would make
  /// every checkbox on the screen report as the same control, and the log would
  /// then claim the user ticked "manual start" when they ticked injection.
  final String id;

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Checkbox(
              value: value,
              activeColor: t.accentGreen,
              onChanged: (v) => onChanged(v ?? false),
            ),
            Icon(icon, size: 18, color: t.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: t.body,
              ),
            ),
          ],
        ),
      ),
    ).tagged(id);
  }
}

/// Anchored dropdown built on [MenuAnchor] — a real popup below the field, with
/// full control over shape/background/width so it matches the app instead of
/// the default squared grey Material menu. `T` may be nullable (a null-valued
/// item is a valid choice, unlike [PopupMenuButton] which treats null as
/// cancel).
class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.placeholder = '—',
    this.disabled,
  });

  final String label;
  final T value;
  final String placeholder;
  final List<({T value, String label, Color? swatch})> items;
  final ValueChanged<T> onChanged;

  /// Values shown but not selectable. Listing a choice the caller cannot honour
  /// says why it is unavailable; leaving it out only makes the list shorter.
  final Set<T>? disabled;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final current = items.where((it) => it.value == value).firstOrNull;
    return LayoutBuilder(
      builder: (context, constraints) {
        return MenuAnchor(
          crossAxisUnconstrained: false,
          style: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(t.overlaySurface),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            elevation: const WidgetStatePropertyAll(8),
            padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(vertical: 6)),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: t.overlayBorder),
              ),
            ),
            minimumSize:
                WidgetStatePropertyAll(Size(constraints.maxWidth, 0)),
            maximumSize: WidgetStatePropertyAll(
                Size(constraints.maxWidth, double.infinity)),
          ),
          menuChildren: [
            for (final it in items)
              _menuItem(t, it.label, it.swatch, it.value == value,
                  disabled?.contains(it.value) ?? false,
                  () => onChanged(it.value)),
          ],
          builder: (context, controller, _) => _field(
            t,
            current?.label ?? placeholder,
            current?.swatch,
            isOpen: controller.isOpen,
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
          ),
        );
      },
    );
  }

  Widget _menuItem(DashTokens t, String label, Color? swatch, bool selected,
      bool disabled, VoidCallback onTap) {
    return MenuItemButton(
      onPressed: disabled ? null : onTap,
      leadingIcon: swatch != null
          ? _SwatchDot(color: swatch, ring: selected ? t.accentGreenInk : null)
          : Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
              color: selected ? t.accentGreenInk : t.textTertiary,
            ),
      style: MenuItemButton.styleFrom(
        foregroundColor: t.textPrimary,
        textStyle: const TextStyle(
          fontFamily: DashTokens.fontUi,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Text(label),
    ).tagged('queue_edit.menu_item', selected: selected);
  }

  Widget _field(
    DashTokens t,
    String text,
    Color? swatch, {
    required bool isOpen,
    required VoidCallback onTap,
  }) {
    return Material(
      color: t.groupCard,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.groupCardBorder),
          ),
          child: Row(
            children: [
              if (swatch != null) ...[
                _SwatchDot(color: swatch),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: t.micro,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      text,
                      style: t.titleSm,
                    ),
                  ],
                ),
              ),
              Icon(Icons.expand_more, color: t.textSecondary),
            ],
          ),
        ),
      ).tagged('queue_edit.picker', expanded: isOpen),
    );
  }
}

/// Small round colour swatch used in filament dropdowns.
class _SwatchDot extends StatelessWidget {
  const _SwatchDot({required this.color, this.ring});
  final Color color;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: ring ?? t.hairline, width: ring != null ? 2 : 1),
      ),
    );
  }
}

/// Selectable printer tile (specific-printer mode).
class _SelectableTile extends StatelessWidget {
  const _SelectableTile({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? t.accentGreen.withValues(alpha: 0.14) : t.groupCard,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? t.accentGreen.withValues(alpha: 0.5) : t.groupCardBorder,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.print_outlined,
                    size: 20, color: selected ? t.accentGreenInk : t.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: t.titleSm,
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: t.monoMicro,
                        ),
                    ],
                  ),
                ),
                if (selected) Icon(Icons.check_circle, color: t.accentGreenInk),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
