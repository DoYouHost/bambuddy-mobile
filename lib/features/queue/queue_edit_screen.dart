import 'package:app_util/app_util.dart';
import 'package:clock/clock.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app_diagnostics/app_diagnostics.dart';
import '../../core/ams/color_names.dart';
import '../../core/ams/job_cost.dart';
import '../../core/format/datetime_format.dart';
import '../../core/format/filament_colour.dart';
import '../../core/models/available_filament.dart';
import '../../core/models/calibration_option.dart';
import '../../core/models/cost_center.dart';
import '../../core/models/filament_requirement.dart';
import '../../core/models/printer.dart';
import '../../core/models/plate_list.dart';
import '../../core/models/queue_item.dart';
import '../../core/settings/print_options.dart';
import '../../core/theme/dash_theme.dart';
import '../../data/queue_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../slicer/slice_providers.dart';
import '../common/dash_async.dart';
import '../orders/orders_providers.dart';
import 'job_cost_providers.dart';
import 'queue_cost_center_state.dart';
import 'queue_create_service.dart';
import 'queue_form_parts.dart';
import 'queue_item_view.dart';
import 'queue_mapping_sheet.dart';
import 'queue_plate_sheet.dart';
import 'queue_providers.dart';
import 'queue_removal.dart';

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
/// a job the user is still setting up.
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
const queueDualNozzleModels = {'H2D', 'H2DPRO', 'H2C', 'X2D'};

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

  /// The last model actually targeted — nulls skipped — as the web's
  /// `prevTargetModel`, for [_dropOverridesOnRetarget].
  late String? _lastTargetModel = widget.item.targetModel;

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

  /// Null until the user touches the switch: a new job then follows the
  /// server's default, which may arrive after the form has opened.
  bool? _confirmOutcomeChoice;

  // Preheat & heat soak
  late String _preheatOverride; // inherit | on | off

  /// Collapsible sections the user has opened; the cards themselves hold no state.
  final _openSections = <String>{};
  late final TextEditingController _chamberTarget;

  // When to print
  late QueueScheduleType _scheduleType;
  DateTime? _scheduledTime;

  // Flags
  late bool _requireManualStart;

  /// The cost center the user picked; null until they do, and then the form
  /// follows [_selectedCostCenter]'s fallback. Starts at the item's own.
  late int? _costCenterId = widget.item.costCenterId;

  /// [awaitingReviewProvider] as [_submit] found it, for the payload builders
  /// that run past its first `await`.
  bool _heldForReview = false;
  late bool _requirePreviousSuccess;
  late bool _autoOffAfter;
  late bool _gcodeInjection;

  bool _saving = false;

  /// Copies to queue (create only). See [_copiesSection].
  int _copies = 1;

  /// The order for the copies was refused and they went in as a plain batch:
  /// the form promised an order, so the outcome says it was not one.
  bool _orderRefused = false;
  static const _maxCopies = 999;

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
    _scheduleType =
        widget.initialSchedule ??
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
    return m != null && queueDualNozzleModels.contains(m);
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
    return async.value ?? const {};
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
    for (final p in async.value ?? const []) {
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
    AppLocalizations l10n, {
    required EdgeInsets padding,
    bool announce = false,
  }) {
    final model = _modelMissingSnippet;
    return inlineNote(
      model == null ? null : l10n.queueEditGcodeInjectionNoSnippet(model),
      padding: padding,
      announce: announce,
    );
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
    // Loaded with the form, so the overrides name their colours on save.
    ref.watch(mappingColorCatalogProvider);
    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(
          context,
          title: widget._isCreate ? l10n.queueCreateTitle : l10n.queueEditTitle,
          actions: [_submitAction(l10n)],
        ),
        body: AbsorbPointer(
          absorbing: _saving,
          child: ListView(
            padding: screenListPadding(context),
            children: [
              _header(l10n, t),
              // The server refuses the job without a cost center and this
              // session has none to pick: say so before the form is filled
              // in rather than after.
              ?_costCenterBlockedNote(l10n),
              const SizedBox(height: DashSpace.lg),
              _targetSection(l10n, t),
              const SizedBox(height: DashSpace.lg),
              ?_plateSection(l10n, t),
              ?_copiesSection(l10n, t),
              if (!_modelMode) ...[
                _mappingSection(l10n, t),
                const SizedBox(height: DashSpace.lg),
              ] else ...[
                _filamentOverrideSection(l10n, t),
                const SizedBox(height: DashSpace.lg),
              ],
              _printOptionsSection(l10n, t),
              const SizedBox(height: DashSpace.lg),
              _preheatSection(l10n, t),
              const SizedBox(height: DashSpace.lg),
              if (_costCenterSection(l10n, t) case final section?) ...[
                section,
                const SizedBox(height: DashSpace.lg),
              ],
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
          child: QueueThumbnail(item: it, size: 52),
        ),
        const SizedBox(width: DashSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.queueEditPrintJob, style: t.micro),
              const SizedBox(height: DashSpace.xs),
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
    final printers = ref.watch(allPrintersProvider).value ?? const [];
    final models = distinctPrinterModels(printers);
    final locations = <String>{
      for (final p in printers)
        if (p.location != null && p.location!.isNotEmpty) p.location!,
    }.toList()..sort();
    // Model dropdown mirrors web: hidden when the file has a known sliced model
    // (the target is fixed to it), shown only for model-agnostic files.
    final slicedModel = widget.item.slicedForModel;
    final modelFixed = slicedModel != null && slicedModel.isNotEmpty;
    final anyLabel = modelFixed
        ? l10n.queueEditAnyModel(slicedModel)
        : (_targetModel != null && _targetModel!.isNotEmpty
              ? l10n.queueEditAnyModel(_targetModel!)
              : l10n.queueEditAnyModelGeneric);

    return QueueSectionCard(
      tone: QueueSectionTone.target,
      title: l10n.queueEditTarget,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashSegToggle<bool>(
            id: 'queue_edit.target_mode',
            selected: _modelMode,
            segments: [
              (
                value: false,
                label: l10n.queueEditSpecificPrinter,
                icon: Icons.print_outlined,
              ),
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
          const SizedBox(height: DashSpace.md),
          if (!_modelMode)
            _printerList(l10n, t, printers)
          else
            _modelTarget(l10n, t, models, locations, modelFixed),
          ?_missingSnippetNote(
            l10n,
            padding: const EdgeInsets.only(top: DashSpace.md),
          ),
        ],
      ),
    );
  }

  String _printerDetail(Printer p) => [
    if (p.model != null) p.model!,
    if (p.ipAddress != null) p.ipAddress!,
  ].join(' • ');

  Widget _printerList(
    AppLocalizations l10n,
    DashTokens t,
    List<Printer> printers,
  ) {
    if (printers.isEmpty) {
      return Text(
        l10n.queueNoFreePrinters,
        style: t.bodyPlain.copyWith(color: t.textTertiary),
      );
    }
    // A select, not a tile per printer: a farm of twenty would be twenty tiles
    // between the toggle and the rest of the form. Typing narrows it by name.
    return dashCombo<int>(
      context,
      id: 'queue_edit.printer_select',
      label: Text(l10n.queueEditPrinter),
      filterable: true,
      initialSelection: _printerId,
      onSelected: (id) => setState(() {
        if (id == null || id == _printerId) return;
        _nozzleRackChoice.clear();
        // A slot id names another spool on another printer; the web drops its
        // picks on a switch too (`PrintModal/index.tsx`).
        _amsMapping = null;
        _printerId = id;
      }),
      entries: [
        for (final p in printers)
          DropdownMenuEntry(
            value: p.id,
            label: p.name,
            labelWidget: logTag(
              'queue_edit.printer',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, style: t.titleSm),
                  if (_printerDetail(p) case final detail
                      when detail.isNotEmpty)
                    Text(detail, style: t.monoMicro),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _modelTarget(
    AppLocalizations l10n,
    DashTokens t,
    List<String> models,
    List<String> locations,
    bool modelFixed,
  ) {
    return Column(
      children: [
        if (!modelFixed && models.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: DashSpace.md),
            child: dashCombo<String>(
              context,
              id: 'queue_edit.target_model',
              label: Text(l10n.queueEditTargetModel),
              initialSelection: models.contains(_targetModel)
                  ? _targetModel
                  : null,
              onSelected: (v) => setState(() {
                _targetModel = v;
                _dropOverridesOnRetarget(plateChanged: false);
              }),
              entries: [
                for (final m in models)
                  DropdownMenuEntry(
                    value: m,
                    label: m,
                    labelWidget: logTag(
                      'queue_edit.target_model.option',
                      Text(m),
                    ),
                  ),
              ],
            ),
          ),
        dashAnyOrOne<String>(
          context,
          id: 'queue_edit.target_location',
          label: Text(l10n.queueEditTargetLocation),
          anyLabel: l10n.queueEditAnyLocation,
          selected: locations.contains(_targetLocation)
              ? _targetLocation
              : null,
          options: [for (final loc in locations) (loc, loc)],
          onPick: (v) => setState(() => _targetLocation = v),
        ),
      ],
    );
  }

  Widget _submitAction(AppLocalizations l10n) => QueueSubmitAction(
    id: widget._isCreate ? 'queue_create.save' : 'queue_edit.save',
    label: widget._isCreate ? l10n.queueCreateSubmit : l10n.queueEditSave,
    onPressed: _saving || !_costCenterAllowsSubmit ? null : _submit,
  );

  // --- Billing ---

  /// What the form can do about billing, from the flag and the centers this
  /// session may book to. [watch] as in [_snippetModels].
  CostCenterState _costCenterState({required bool watch}) =>
      costCenterStateOf(watch ? ref.watch : ref.read);

  /// A new job, or one queued before billing was on, cannot be saved without a
  /// cost center. An item that already has one keeps it on the server, so an
  /// edit of it never waits for, or depends on, the list.
  bool get _costCenterRequired =>
      widget._isCreate || widget.item.costCenterId == null;

  /// Whether Save may be pressed as far as billing is concerned: every step
  /// that cannot offer a pick leaves a job without a cost center stuck.
  bool get _costCenterAllowsSubmit =>
      costCenterAllowsCreate(_costCenterState(watch: true).step) ||
      !_costCenterRequired;

  /// The center Save sends: what the user picked if it is still on offer, else
  /// the web's default. Null when there is nothing to choose from.
  CostCenter? _selectedCostCenter(List<CostCenter> centers) =>
      selectedCostCenter(centers, _costCenterId);

  /// `cost_center_id` for the write, or null to leave the key out: on a server
  /// without billing, where the field is not read, and wherever there is no
  /// center to offer — an item that already has one keeps it server-side.
  int? get _costCenterPayload =>
      _selectedCostCenter(_costCenterState(watch: false).centers)?.id;

  /// Why the job cannot be saved, said before the form is filled in. Only for
  /// a job that needs a center: an item that has one is not blocked by this.
  Widget? _costCenterBlockedNote(AppLocalizations l10n) {
    if (!_costCenterRequired) return null;
    return inlineNote(switch (_costCenterState(watch: true).step) {
      CostCenterStep.refused => l10n.queueBillingCostCentersRefused,
      CostCenterStep.none => l10n.queueBillingNoCostCenter,
      _ => null,
    }, urgent: true);
  }

  /// Folds a section that is rarely touched, closed until the user opens it.
  QueueSectionCollapse _collapse(String id) => (
    id: id,
    open: _openSections.contains(id),
    onToggle: () => setState(() {
      if (!_openSections.remove(id)) _openSections.add(id);
    }),
  );

  /// The web's cost-center select (`PrintModal/CostCenterSelect.tsx`): shown
  /// while billing is on and there is something to choose from.
  Widget? _costCenterSection(AppLocalizations l10n, DashTokens t) {
    final state = _costCenterState(watch: true);
    final body = switch (state.step) {
      CostCenterStep.loading => const LinearProgressIndicator(),
      CostCenterStep.failed => Row(
        children: [
          Expanded(
            child: Text(
              l10n.queueCostCenterLoadFailed,
              style: t.bodyPlain.copyWith(color: t.textTertiary),
            ),
          ),
          TextButton(
            onPressed: () => ref.invalidate(printableCostCentersProvider),
            child: Text(l10n.retry),
          ).tagged('queue_edit.cost_center_retry'),
        ],
      ),
      CostCenterStep.pick => _costCenterPicker(l10n, t, state.centers),
      _ => null,
    };
    return body == null
        ? null
        : QueueSectionCard(
            tone: QueueSectionTone.cost,
            title: l10n.queueCostCenterTitle,
            child: body,
          );
  }

  Widget _costCenterPicker(
    AppLocalizations l10n,
    DashTokens t,
    List<CostCenter> centers,
  ) {
    final selected = _selectedCostCenter(centers);
    String label(CostCenter c) =>
        c.isPrivate ? l10n.queueCostCenterPersonal(c.name) : c.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        dashCombo<int>(
          context,
          id: 'queue_edit.cost_center',
          initialSelection: selected?.id,
          onSelected: (v) => setState(() => _costCenterId = v),
          entries: [
            for (final c in centers)
              DropdownMenuEntry(
                value: c.id,
                label: label(c),
                // A center's name is the user's own words, so every row is one
                // id — see `dashAnyOrOne`.
                labelWidget: logTag(
                  'queue_edit.cost_center.option',
                  Text(label(c)),
                ),
              ),
          ],
        ),
        if (selected?.budget == CostCenterBudget.none)
          InlineNote(l10n.queueCostCenterUnlimited, icon: Icons.info_outline),
        ?_budgetWarning(t, selected),
      ],
    );
  }

  /// The job's cost preview, or null where the web draws no mapping panel: a job
  /// aimed at "any printer of a model", no printer yet, no filament in the plate,
  /// or a printer status that has not arrived.
  JobCost? _jobCost() {
    final source = _plateSource;
    final printerId = _printerId;
    if (_modelMode || source == null || printerId == null) return null;
    return ref
        .watch(
          jobCostProvider((
            isArchive: source.$1,
            id: source.$2,
            plate: _plateId ?? 1,
            printerId: printerId,
            mapping: mappingKey(_amsMapping),
          )),
        )
        .value;
  }

  int get _costCopies => widget._isCreate ? _copies : 1;

  /// What the job is expected to cost, under the mapping it is priced from.
  /// Shown with or without billing, as the web's mapping panel does: the budget
  /// is the billing half, see [_budgetWarning]. The server prices the job itself;
  /// this says so before the form is sent.
  Widget? _costEstimate(AppLocalizations l10n, DashTokens t) {
    final cost = _jobCost();
    if (cost == null) return null;
    final currency = ref.watch(currencySymbolProvider);
    return Padding(
      padding: const EdgeInsets.only(top: DashSpace.xs),
      child: Text(
        jobCostText(l10n, currency, cost, _costCopies),
        style: t.labelSoft,
      ),
    );
  }

  /// A warning where the job, all its copies, is more than the center has left.
  /// The server refuses it when it does not fit; this says so before the form
  /// is sent.
  Widget? _budgetWarning(DashTokens t, CostCenter? selected) {
    if (!jobExceedsBudget(_jobCost(), selected, _costCopies)) return null;
    return Padding(
      padding: const EdgeInsets.only(top: DashSpace.sm),
      child: Text(
        AppLocalizations.of(context).queueInsufficientBudget,
        style: t.labelSoft.copyWith(color: t.dangerInk),
      ),
    );
  }

  /// Name of the printer picked in the Target section, for messages that would
  /// otherwise quote the item's stored (or, on a draft, missing) printer.
  String? _selectedPrinterName(int printerId) {
    for (final p in ref.read(allPrintersProvider).value ?? const []) {
      if (p.id == printerId) return p.name;
    }
    return null;
  }

  // --- Copies (create only) ---

  /// How many copies to queue. More than one is grouped server-side; with
  /// orders (1.2.5.3+) it becomes an order whose target is the copies, as the
  /// web's print dialog makes it, so a failed copy stays owed.
  ///
  /// Absent below v0.2.3, whose create takes no `quantity` and would queue one
  /// copy without a word — the same row that gates the orders screen.
  Widget? _copiesSection(AppLocalizations l10n, DashTokens t) {
    if (!widget._isCreate || !ref.watch(batchListingProvider).orFalse) {
      return null;
    }
    final order = ref.watch(batchOrdersProvider).orFalse;
    return Column(
      children: [
        QueueSectionCard(
          tone: QueueSectionTone.copies,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(l10n.queueEditCopies, style: t.body)),
                  DashStepper(
                    value: _copies,
                    min: 1,
                    max: _maxCopies,
                    onChanged: (v) => setState(() => _copies = v),
                    lessTooltip: l10n.copiesLess,
                    moreTooltip: l10n.copiesMore,
                    lessId: 'queue_edit.copies_down',
                    moreId: 'queue_edit.copies_up',
                  ),
                ],
              ),
              // What more than one copy turns into — said only once it does,
              // and across the card rather than squeezed beside the stepper.
              if (_copies > 1)
                Padding(
                  padding: const EdgeInsets.only(top: DashSpace.xs),
                  child: Text(
                    order
                        ? l10n.queueEditCopiesOrder
                        : l10n.queueEditCopiesHint,
                    style: t.bodySoft,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: DashSpace.lg),
      ],
    );
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
  /// The key [plateListProvider] takes for this item's file, or null.
  (bool, int)? get _plateSource {
    final it = widget.item;
    return it.archiveId != null
        ? (true, it.archiveId!)
        : (it.libraryFileId != null ? (false, it.libraryFileId!) : null);
  }

  Widget? _plateSection(AppLocalizations l10n, DashTokens t) {
    final source = _plateSource;
    if (source == null) return null;
    final plates = ref.watch(plateListProvider(source)).value ?? PlateList.none;
    if (!plates.isMultiPlate) return null;

    final current = plates.byIndex(_plateId);
    final label = current == null
        ? l10n.queueEditPlateSelected(_plateId ?? 1)
        : plateLabel(l10n, current);
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: DashSpace.sm),
        child: Row(
          children: [
            Icon(Icons.layers_outlined, color: t.textSecondary, size: 20),
            const SizedBox(width: DashSpace.md),
            Expanded(
              child: Text(
                widget._isCreate
                    ? label
                    : l10n.queueEditPlateFixed(_plateId ?? 1),
                style: t.body,
              ),
            ),
            if (widget._isCreate)
              Icon(Icons.chevron_right, color: t.textTertiary),
          ],
        ),
      ),
    );

    return Column(
      children: [
        QueueSectionCard(
          tone: QueueSectionTone.plate,
          title: l10n.queueEditPlate,
          child: widget._isCreate
              ? InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _pickPlate(plates),
                  child: row,
                ).tagged('queue_edit.plate')
              : row,
        ),
        const SizedBox(height: DashSpace.lg),
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
      _dropOverridesOnRetarget(plateChanged: true);
      // The pick names filament groups of the plate it was made for; another
      // plate's groups are another set, and a group id that survives means a
      // position chosen for a filament nobody asked about.
      _nozzleRackChoice.clear();
    });
  }

  Widget _mappingSection(AppLocalizations l10n, DashTokens t) {
    final mapped = _amsMapping?.where((v) => v >= 0).length ?? 0;
    final printerId = _printerId;
    return QueueSectionCard(
      tone: QueueSectionTone.filament,
      title: l10n.queueFilamentMapping,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: printerId == null
                ? null
                : () async {
                    // The rows write these back as they change; a sheet dismissed
                    // without saving takes them back, as it does its slot picks.
                    final rackBefore = {..._nozzleRackChoice};
                    final forceBefore = {..._forceColorMatch};
                    final mapping = await showQueueMappingSheet(
                      context,
                      item: widget.item,
                      printerId: printerId,
                      printerName: _selectedPrinterName(printerId),
                      confirmLabel: l10n.fmSave,
                      plateId: _plateId,
                      startFrom: _amsMapping ?? const [],
                      forceColorMatch: _forceColorMatch,
                      onForceColorMatch: (slotId, value) => setState(() {
                        if (value) {
                          _forceColorMatch[slotId] = true;
                        } else {
                          _forceColorMatch.remove(slotId);
                        }
                      }),
                      rackChoice: _nozzleRackChoice,
                      onRackChoice: (choice) => setState(
                        () => _nozzleRackChoice
                          ..clear()
                          ..addAll(choice),
                      ),
                    );
                    // Empty: the printer reported nothing to map to, and the web
                    // sends no mapping then — keep the stored one.
                    if (mapping == null) {
                      setState(() {
                        _nozzleRackChoice
                          ..clear()
                          ..addAll(rackBefore);
                        _forceColorMatch
                          ..clear()
                          ..addAll(forceBefore);
                      });
                    } else if (mapping.isNotEmpty) {
                      setState(() => _amsMapping = mapping);
                    }
                  },
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: kMinInteractiveDimension,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: DashSpace.sm),
                child: Row(
                  children: [
                    Icon(
                      Icons.bento_outlined,
                      color: t.textSecondary,
                      size: 20,
                    ),
                    const SizedBox(width: DashSpace.md),
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
            ),
          ).tagged('queue_edit.mapping'),
          ?_costEstimate(l10n, t),
        ],
      ),
    );
  }

  // --- Filament override (model mode) ---

  /// The filament slots the plate prints with, as the server parsed them out of
  /// the 3MF — unused project slots left out, as the web's print dialog reads
  /// them — or empty when the job has no source to parse (a queued reprint
  /// whose archive is created only at print start) and while the request is in
  /// flight.
  ///
  /// Separate from [_requirements] because that one flattens the records down to
  /// what the override rows need, and the rack picker needs the filament-group
  /// table only the parsed form carries.
  List<FilamentRequirement> _parsedRequirements() {
    final it = widget.item;
    if (it.archiveId != null) {
      return ref
              .watch(
                printRequirementsProvider((
                  isArchive: true,
                  id: it.archiveId!,
                  plate: _plateId ?? 1,
                )),
              )
              .value ??
          const [];
    }
    if (it.libraryFileId != null) {
      return ref
              .watch(
                printRequirementsProvider((
                  isArchive: false,
                  id: it.libraryFileId!,
                  plate: _plateId ?? 1,
                )),
              )
              .value ??
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
    // Paired by position, and the two strings diverge in BOTH directions —
    // which is why the loop runs to the longer of them rather than to either
    // one. Three mechanisms, all server-side and none repairable here, because
    // neither string says which slot a token belonged to:
    //
    //   - Colours shorter. The MQTT fallback joins every type but skips a
    //     filament whose colour is empty (`_extract_filament_data_from_mqtt`
    //     in main.py, where the `if f[1]` sits on the colour join alone), so a
    //     slot with no RFID tag shifts every colour after it by one.
    //   - Colours longer. The archive extractor deduplicates BOTH lists
    //     independently (`services/archive.py`, reading slice_info.config's
    //     `<filament type= color= used_g=>`), so two slots of one material in
    //     two colours collapse to one type while both colours survive. It is
    //     the duplicate value, not the field, that decides which list shortens.
    //     Measured on a live server: over 35 populated values the type string
    //     never once repeated a material.
    //   - Either, at length. The columns cap at 50 characters for the types
    //     and 200 for the colours, so a print with enough filaments loses the
    //     tail of one list before the other.
    //
    // Bounding the loop by the type list used to drop the surplus colour
    // outright — a two-colour print rendered as one filament. A row with no
    // type is not a guess: `_overrideRow` renders it as an em dash, which says
    // "a slot is here and we cannot name its material", where the colour
    // simply vanishing said nothing at all.
    final types = filamentTypeTokens(it.filamentType);
    final colors = filamentColourTokens(it.filamentColor);
    final slots = types.length > colors.length ? types.length : colors.length;
    // When the archive parser (archive.py) deduplicates identical materials across
    // slots, a single-material multi-color print yields 1 type and multiple colors.
    // In that case, every slot shares that single material.
    final singleType = types.length == 1 ? types.first : null;
    return [
      for (var i = 0; i < slots; i++)
        (
          slotId: i + 1,
          type: singleType ?? (i < types.length ? types[i] : ''),
          color: i < colors.length ? colors[i] : '',
        ),
    ];
  }

  Widget _filamentOverrideSection(AppLocalizations l10n, DashTokens t) {
    final model = _targetModel ?? '';
    final available = model.isEmpty
        ? const <AvailableFilament>[]
        : (ref
                  .watch(
                    availableFilamentsProvider((model, _targetLocation ?? '')),
                  )
                  .value ??
              const <AvailableFilament>[]);
    final reqs = _requirements();
    return QueueSectionCard(
      tone: QueueSectionTone.filament,
      title: l10n.queueEditFilamentOverride,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.queueEditFilamentOverrideDesc, style: t.labelSoft),
          const SizedBox(height: DashSpace.md),
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
    // full canonical grouping the web does for CF families). If the slot material
    // is unknown (e.g. multi-material print where types diverged), allow picking
    // from any available spool rather than presenting an empty list.
    final canon = req.type.trim().toUpperCase();
    final compatible = req.type.isEmpty
        ? available
        : [
            for (final f in available)
              if (f.type.trim().toUpperCase() == canon) f,
          ];
    final override = _overrides[req.slotId];
    final selected = override == null
        ? null
        : '${override.type}|${override.color}';
    final typeLabel = req.type.isEmpty ? '—' : req.type;
    return Padding(
      padding: const EdgeInsets.only(bottom: DashSpace.md),
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
                if (req.type.isEmpty) {
                  _forceColorMatch.remove(req.slotId);
                }
              } else {
                final parts = v.split('|');
                _overrides[req.slotId] = (
                  type: parts[0],
                  color: parts.length > 1 ? parts[1] : '',
                );
              }
            }),
          ),
          _CheckRow(
            id: 'queue_edit.force_color_match',
            icon: Icons.palette_outlined,
            label: l10n.queueEditForceColorMatch,
            value: _forceColorMatch[req.slotId] ?? false,
            onChanged: (req.type.isEmpty && override == null)
                ? null
                : (v) => setState(() {
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
  /// The web's `printerOverridesForPlate`: a job for one printer carries only
  /// the slots whose filament was changed (#3133) — the mapping was matched
  /// against them, and the scheduler needs them if it maps again at
  /// dispatch. A force-colour flag on its own stays behind, as the web's
  /// does: printer mode never sent one.
  List<Map<String, dynamic>>? _buildPrinterOverrides() {
    final entries = [
      for (final o
          in _buildFilamentOverrides() ?? const <Map<String, dynamic>>[])
        if (_overrides.containsKey(o['slot_id'])) o,
    ];
    return entries.isEmpty ? null : entries;
  }

  List<Map<String, dynamic>>? _buildFilamentOverrides() {
    final catalog =
        ref.read(mappingColorCatalogProvider).value ?? ColorCatalog.empty;
    final entries = <Map<String, dynamic>>[];
    for (final r in _requirements()) {
      final ov = _overrides[r.slotId];
      final force = _forceColorMatch[r.slotId] ?? false;
      if (ov == null && !force) continue;
      final type = ov?.type ?? r.type;
      final color = ov?.color ?? r.color;
      // Backend scheduler matches slots by canonical_filament_type(o['type']).
      // An empty type can never match any loaded spool and causes the job to
      // stall indefinitely waiting for filament.
      if (type.isEmpty) continue;
      entries.add({
        'slot_id': r.slotId,
        'type': type,
        'color': color,
        // The web's `getColorName`: the server quotes it back in its waiting
        // reasons, where a bare hex tells the reader nothing.
        'color_name': colorNameForServer(catalog, color),
        ...?_storedVariant(r.slotId, type, color),
        'force_color_match': force,
      });
    }
    return entries.isEmpty ? null : entries;
  }

  /// The web's `storedVariantFor`: a slot still asking for the filament its
  /// stored override named keeps that override's `tray_info_idx` — the exact
  /// variant a forced colour match is held to (`print_scheduler.py`). Any
  /// change of type or colour drops it. Only an edit has stored overrides.
  Map<String, String>? _storedVariant(int slotId, String type, String color) {
    if (widget._isCreate) return null;
    String hex(Object? c) {
      final clean = (c?.toString() ?? '').replaceFirst('#', '').toLowerCase();
      return clean.length > 6 ? clean.substring(0, 6) : clean;
    }

    for (final o
        in widget.item.filamentOverrides ?? const <Map<String, dynamic>>[]) {
      if (o['slot_id'] != slotId) continue;
      final idx = o['tray_info_idx'];
      final same =
          (o['type']?.toString() ?? '').toUpperCase() == type.toUpperCase() &&
          hex(o['color']) == hex(color);
      return idx is String && idx.isNotEmpty && same
          ? {'tray_info_idx': idx}
          : null;
    }
    return null;
  }

  Color? _swatch(String hex) => colorFromHex(hex);

  // --- Print options ---
  Widget _printOptionsSection(AppLocalizations l10n, DashTokens t) {
    // Two states until the server is known to have a third. A pre-1.2.5 server
    // rejects `auto` outright, so offering the position before the probe answers
    // would promise something we cannot deliver.
    final triState = ref.watch(triStateCalibrationProvider).orFalse;
    return QueueSectionCard(
      tone: QueueSectionTone.options,
      title: l10n.queueEditPrintOptions,
      collapse: _collapse('queue_edit.print_options_section'),
      child: Column(
        children: [
          QueueCalibrationRow(
            id: 'queue_edit.bed_levelling',
            title: l10n.queueOptBedLevelling,
            subtitle: l10n.queueOptBedLevellingDesc,
            value: _bedLevelling,
            triState: triState,
            onChanged: (v) => setState(() => _bedLevelling = v),
          ),
          QueueCalibrationRow(
            id: 'queue_edit.flow_cali',
            title: l10n.queueOptFlowCali,
            subtitle: l10n.queueOptFlowCaliDesc,
            value: _flowCali,
            triState: triState,
            onChanged: (v) => setState(() => _flowCali = v),
          ),
          QueueOptionSwitch(
            id: 'queue_edit.vibration_cali',
            title: l10n.queueOptVibrationCali,
            subtitle: l10n.queueOptVibrationCaliDesc,
            value: _vibrationCali,
            onChanged: (v) => setState(() => _vibrationCali = v),
          ),
          QueueOptionSwitch(
            id: 'queue_edit.layer_inspect',
            title: l10n.queueOptLayerInspect,
            subtitle: l10n.queueOptLayerInspectDesc,
            value: _layerInspect,
            onChanged: (v) => setState(() => _layerInspect = v),
          ),
          QueueOptionSwitch(
            id: 'queue_edit.timelapse',
            title: l10n.queueOptTimelapse,
            subtitle: l10n.queueOptTimelapseDesc,
            value: _timelapse,
            onChanged: (v) => setState(() => _timelapse = v),
          ),
          if (_offersConfirmOutcome)
            QueueOptionSwitch(
              id: 'queue_edit.confirm_outcome',
              title: l10n.queueOptConfirmOutcome,
              subtitle: _confirmOutcomeSticky
                  ? l10n.queueOptConfirmOutcomeSticky
                  : l10n.queueOptConfirmOutcomeDesc,
              value: _confirmOutcome(watch: true),
              // Held while a new job's default is on its way: a switch that
              // moves by itself after the first look is one tapped wrong.
              onChanged: _confirmOutcomeUnanswered || _confirmOutcomeSticky
                  ? null
                  : (v) => setState(() => _confirmOutcomeChoice = v),
            ),
          if (_showNozzleOffset)
            QueueCalibrationRow(
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
    return QueueSectionCard(
      tone: QueueSectionTone.preheat,
      title: l10n.queueEditPreheat,
      collapse: _collapse('queue_edit.preheat_section'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.queueEditPreheatDesc, style: t.labelSoft),
          const SizedBox(height: DashSpace.md),
          DashSegToggle<String>(
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
            const SizedBox(height: DashSpace.md),
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
    return QueueSectionCard(
      tone: QueueSectionTone.schedule,
      title: l10n.queueEditWhenToPrint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashSegToggle<QueueScheduleType>(
            id: 'queue_edit.schedule_type',
            selected: _scheduleType,
            segments: [
              (
                value: QueueScheduleType.asap,
                label: l10n.queueScheduleAsap,
                icon: Icons.schedule,
              ),
              (
                value: QueueScheduleType.queue,
                label: l10n.queueScheduleQueue,
                icon: Icons.list,
              ),
              (
                value: QueueScheduleType.scheduled,
                label: l10n.queueScheduleSchedule,
                icon: Icons.calendar_today,
              ),
            ],
            onChanged: (v) => setState(() {
              _scheduleType = v;
              // Manual start only makes sense in Queue mode (matches web).
              if (v != QueueScheduleType.queue) _requireManualStart = false;
            }),
          ),
          if (_scheduleType == QueueScheduleType.scheduled) ...[
            const SizedBox(height: DashSpace.md),
            _scheduleTimeRow(l10n, t),
          ],
          const SizedBox(height: DashSpace.sm),
          // Their jobs always wait, so the switch would only mislead (#1620).
          if (ref.watch(awaitingReviewProvider))
            InlineNote(
              l10n.queueEditAwaitingReviewNote,
              icon: Icons.pan_tool_outlined,
              padding: const EdgeInsets.symmetric(vertical: DashSpace.sm),
            )
          else if (_scheduleType == QueueScheduleType.queue)
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
          ?_missingSnippetNote(
            l10n,
            padding: const EdgeInsets.only(
              left: DashSpace.xs,
              top: DashSpace.xs,
            ),
            announce: true,
          ),
        ],
      ),
    );
  }

  Widget _scheduleTimeRow(AppLocalizations l10n, DashTokens t) {
    final label = _scheduledTime == null
        ? l10n.queueEditPickTime
        : DateTimeFormats.of(context).dateTime(_scheduledTime!);
    return BesideOrBelow(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_outlined, color: t.textSecondary),
          const SizedBox(width: DashSpace.md),
          Flexible(child: Text(label, style: t.monoValue)),
        ],
      ),
      control: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.textPrimary,
          side: BorderSide(color: t.cardBorder),
        ),
        onPressed: _pickScheduledTime,
        child: Text(l10n.queueEditPickTime),
      ).tagged('queue_edit.pick_time'),
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

    _heldForReview = ref.read(awaitingReviewProvider);
    setState(() => _saving = true);
    _logGcodeInjection();
    _sentMapping = _modelMode ? null : await _matchMapping();

    final result = await ref
        .read(queueProvider.notifier)
        .runOnRepository(
          widget._isCreate ? _create : _update,
          widget._isCreate ? 'queue_edit.create' : 'queue_edit.save',
        );

    // Remember the toggles only once a job was really created with them.
    // Editing an existing item is about THAT item — treating it as "what I print
    // with" would let a one-off tweak follow the user into every later job.
    if (widget._isCreate && result.isOk) {
      await ref.read(settingsRepositoryProvider).savePrintOptions(_options);
    }

    if (!mounted) return;
    setState(() => _saving = false);
    final ok = !widget._isCreate
        ? l10n.queueEditSaved
        : (_orderRefused ? l10n.queueEditOrderRefused : l10n.queueCreateAdded);
    messenger.snack(queueWriteMessage(l10n, result) ?? ok);
    // Create pops `true` — its caller (a list of archives or files) refreshes
    // what it shows only when something was really added.
    if (result.isOk) navigator.pop(widget._isCreate);
  }

  /// The web's rule for the filament overrides when the target model or the
  /// plate changes (`PrintModal/index.tsx`): they go, unless this is the first
  /// model after none — a choice, not a change — or an edit of a job that had
  /// no model before. Leaving "any P2S" for a printer keeps them: they are
  /// the job's filament, not a tray (#3133).
  void _dropOverridesOnRetarget({required bool plateChanged}) {
    final previous = _lastTargetModel;
    final modelChanged = _targetModel != null && _targetModel != previous;
    if (!modelChanged && !plateChanged) return;
    if (modelChanged) _lastTargetModel = _targetModel;
    if (modelChanged && !plateChanged && previous == null) return;
    if (widget._isCreate || previous != null) {
      _overrides.clear();
      _forceColorMatch.clear();
    }
  }

  /// What [_update] and [_create] send as `ams_mapping`, worked out just
  /// before; null is "send none".
  List<int>? _sentMapping;

  /// The mapping the web sends on save (`getMappingForPrinter`): matched
  /// afresh against the printer as it is now, from the form's own picks. None
  /// when the printer reports no loaded slot, which keeps the stored one.
  Future<List<int>?> _matchMapping() async {
    final printerId = _printerId;
    final it = widget.item;
    final source = it.archiveId ?? it.libraryFileId;
    if (printerId == null || source == null) return null;
    try {
      return await queueMappingToSend(
        // The provider the form already watches, so this is no second fetch.
        requirements: await ref.read(
          printRequirementsProvider((
            isArchive: it.archiveId != null,
            id: source,
            plate: _plateId ?? 1,
          )).future,
        ),
        printers: ref.read(printersRepositoryProvider),
        printerId: printerId,
        startFrom: _amsMapping ?? const [],
        preferLowestSetting: ref.read(preferLowestFilamentProvider).value,
      );
    } on Object {
      // A lost session surfaces on the write itself; the mapping only rides
      // along with it.
      return null;
    }
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

  /// Hidden where the server would drop the flag: a switch that is on and
  /// never asks is worse than no switch.
  bool get _offersConfirmOutcome => ref.watch(queueOutcomeProvider).orFalse;

  /// What the switch shows: the user's choice, else the item's own flag when
  /// editing, else the server's default for a new job.
  bool _confirmOutcome({required bool watch}) {
    if (_confirmOutcomeSticky) return true;
    if (_confirmOutcomeChoice case final choice?) return choice;
    if (!widget._isCreate) return widget.item.confirmOutcome;
    final server = watch
        ? ref.watch(defaultConfirmOutcomeProvider)
        : ref.read(defaultConfirmOutcomeProvider);
    return server.value ?? false;
  }

  bool get _confirmOutcomeUnanswered =>
      widget._isCreate &&
      _confirmOutcomeChoice == null &&
      ref.watch(defaultConfirmOutcomeProvider).isUnanswered;

  /// The flag for a PATCH, sent only when it changed — as the calibrations
  /// are ([_calibrationUpdate]) — so a save about something else cannot
  /// rewrite what another client set meanwhile.
  bool? get _confirmOutcomeUpdate {
    final choice = _confirmOutcomeChoice;
    if (ref.read(queueOutcomeProvider).value == false) return null;
    return choice == widget.item.confirmOutcome ? null : choice;
  }

  /// A reprint of an archive that already asks: the server copies only a
  /// `true` onto the archive and never clears it (`print_scheduler.py`), so
  /// this job asks whatever the switch says — which is why it says so.
  bool get _confirmOutcomeSticky =>
      widget._isCreate &&
      widget.item.archiveId != null &&
      widget.item.confirmOutcome;

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
        'match':
            _gcodeInjection &&
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

  /// `watch`, so the helper text stops advertising 60 the moment the version
  /// probe answers with the form already open.
  int get _chamberMax => ref.watch(chamberMaxTargetProvider);

  int? get _chamberTargetValue {
    if (_preheatOverride == 'off') return null;
    // `read`: this one runs from the save button, outside a build.
    final max = ref.read(chamberMaxTargetProvider);
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
  ) => current == stored ? null : current;

  /// The web's `editManualStart`: a user held for review always waits (#1620),
  /// and an edit keeps a scheduled job's wait rather than clearing it — which
  /// would start it, and is refused to such a user.
  bool get _manualStartSent =>
      _heldForReview ||
      switch (_scheduleType) {
        QueueScheduleType.queue => _requireManualStart,
        QueueScheduleType.scheduled =>
          !widget._isCreate && widget.item.manualStart,
        QueueScheduleType.asap => false,
      };

  Future<void> _update(QueueRepository repo) => repo.updateItem(
    widget.item.id,
    printerId: _modelMode ? null : _printerId,
    targetModel: _modelMode ? _targetModel : null,
    targetLocation: _modelMode ? _targetLocation : null,
    amsMapping: _modelMode
        ? kQueueUpdateUnset
        : _sentMapping ?? kQueueUpdateUnset,
    // Null, not unset: a job moved to a printer must not keep a model job's
    // overrides it no longer carries (#3133).
    filamentOverrides: _modelMode
        ? _buildFilamentOverrides()
        : _buildPrinterOverrides(),
    scheduledTime: _scheduledTimeIso,
    requirePreviousSuccess: _requirePreviousSuccess,
    autoOffAfter: _autoOffAfter,
    manualStart: _manualStartSent,
    bedLevelling: _calibrationUpdate(_bedLevelling, widget.item.bedLevelling),
    flowCali: _calibrationUpdate(_flowCali, widget.item.flowCali),
    vibrationCali: _vibrationCali,
    layerInspect: _layerInspect,
    timelapse: _timelapse,
    nozzleOffsetCali: _showNozzleOffset
        ? _calibrationUpdate(_nozzleOffsetCali, widget.item.nozzleOffsetCali)
        : null,
    gcodeInjection: _gcodeInjectionPayload,
    confirmOutcome: _confirmOutcomeUpdate,
    preheatOverride: _preheatOverride,
    preheatChamberTargetOverride: _chamberTargetValue,
    nozzleRackChoice: _rackChoiceUpdate,
    costCenterId: _costCenterPayload,
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

  Future<void> _create(QueueRepository repo) async {
    final it = widget.item;
    _orderRefused = false;
    final outcome = await createQueueJobs(
      repo: repo,
      providers: ProviderScope.containerOf(context, listen: false),
      archiveId: it.archiveId,
      libraryFileId: it.libraryFileId,
      sourceName: it.displayName,
      printerId: _modelMode ? null : _printerId,
      copies: _copies,
      insertAtTop: _scheduleType == QueueScheduleType.asap,
      plateId: _plateId,
      confirmOutcomeChoice: _confirmOutcomeChoice,
      confirmOutcomeSticky: _confirmOutcomeSticky,
      buildOptions: () => QueueCreateOptions(
        targetModel: _modelMode ? _targetModel : null,
        targetLocation: _modelMode ? _targetLocation : null,
        filamentOverrides: _modelMode
            ? _buildFilamentOverrides()
            : _buildPrinterOverrides(),
        amsMapping: _modelMode ? null : _sentMapping,
        scheduledTime: _scheduledTimeIso,
        requirePreviousSuccess: _requirePreviousSuccess,
        autoOffAfter: _autoOffAfter,
        manualStart: _manualStartSent,
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
        costCenterId: _costCenterPayload,
      ),
    );
    _orderRefused = outcome.orderRefused;
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
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final enabled = onChanged != null;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: enabled ? () => onChanged!(!value) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: DashSpace.sm),
        child: Row(
          children: [
            Checkbox(
              value: value,
              activeColor: t.accentGreen,
              onChanged: onChanged == null
                  ? null
                  : (v) => onChanged!(v ?? false),
            ),
            Icon(
              icon,
              size: 18,
              color: enabled ? t.textSecondary : t.textTertiary,
            ),
            const SizedBox(width: DashSpace.md),
            Expanded(
              child: Text(
                label,
                style: enabled
                    ? t.body
                    : t.body.copyWith(color: t.textTertiary),
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
  });

  final String label;
  final T value;
  final String placeholder;
  final List<({T value, String label, Color? swatch})> items;
  final ValueChanged<T> onChanged;

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
              EdgeInsets.symmetric(vertical: DashSpace.sm),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: t.overlayBorder),
              ),
            ),
            minimumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, 0)),
            maximumSize: WidgetStatePropertyAll(
              Size(constraints.maxWidth, double.infinity),
            ),
          ),
          menuChildren: [
            for (final it in items)
              _menuItem(
                t,
                it.label,
                it.swatch,
                it.value == value,
                () => onChanged(it.value),
              ),
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

  Widget _menuItem(
    DashTokens t,
    String label,
    Color? swatch,
    bool selected,
    VoidCallback onTap,
  ) {
    return MenuItemButton(
      onPressed: onTap,
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
          padding: const EdgeInsets.symmetric(
            horizontal: DashSpace.lg,
            vertical: DashSpace.md,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.groupCardBorder),
          ),
          child: Row(
            children: [
              if (swatch != null) ...[
                _SwatchDot(color: swatch),
                const SizedBox(width: DashSpace.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: t.micro),
                    const SizedBox(height: DashSpace.xs),
                    Text(text, style: t.titleSm),
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
        border: Border.all(
          color: ring ?? t.hairline,
          width: ring != null ? 2 : 1,
        ),
      ),
    );
  }
}
