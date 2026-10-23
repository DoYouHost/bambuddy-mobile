import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ams/color_names.dart';
import '../../core/ams/filament_mapping.dart';
import '../../core/ams/slot_addressing.dart';
import '../../core/format/datetime_format.dart';
import '../../core/format/duration_format.dart';
import '../../core/format/filament_colour.dart';
import '../../core/models/current_user.dart';
import '../../core/models/plate_list.dart';
import '../../core/models/printer.dart';
import '../../core/models/queue_item.dart';
import '../../core/printers/gcode_compat.dart';
import '../../core/settings/print_options.dart';
import '../../core/theme/dash_theme.dart';
import '../../data/queue_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../archive/archive_providers.dart';
import '../common/dash_async.dart';
import '../queue/job_cost_providers.dart';
import '../queue/queue_cost_center_state.dart';
import '../queue/queue_create_service.dart';
import '../queue/queue_drafts.dart';
import '../queue/queue_edit_screen.dart';
import '../queue/queue_item_view.dart';
import '../queue/queue_mapping_sheet.dart';
import '../queue/queue_providers.dart';
import '../queue/queue_removal.dart';
import '../slicer/slice_providers.dart';
import '../stats/stats_common.dart';
import '../orders/orders_providers.dart';
import 'controller_controls.dart';
import 'controller_print_more.dart';
import 'controller_print_parts.dart';
import 'controller_providers.dart';
import 'scale_to_fit.dart';

/// Why a job cannot be printed on this printer from the controller, or null
/// when it can, in the order a dialog names them: a printer gone from the
/// roster first, since nothing else can be said of it; then what `POST /queue/`
/// would refuse this account; then what the file itself rules out.
enum ControllerPrintBlock {
  printerGone,
  noQueue,
  noReprint,
  notSliced,
  wrongModel;

  String reason(AppLocalizations l10n, {required String? slicedForModel}) =>
      switch (this) {
        printerGone => l10n.controllerPrinterGone,
        noQueue => ArchiveReprintBlock.noQueue.reason(l10n),
        noReprint => ArchiveReprintBlock.noReprint.reason(l10n),
        notSliced => l10n.controllerFileReasonNotSliced,
        wrongModel => l10n.controllerFileReasonModel(slicedForModel ?? ''),
      };
}

/// [refused] is what the account may not do: `queue:create` for any job, the
/// reprint right on top for an archive ([archiveReprintBlockProvider]).
ControllerPrintBlock? controllerPrintBlock({
  required bool printerKnown,
  required ArchiveReprintBlock? refused,
  required bool printable,
  required String? slicedForModel,
  required String? printerModel,
}) {
  if (!printerKnown) return ControllerPrintBlock.printerGone;
  switch (refused) {
    case ArchiveReprintBlock.noQueue:
      return ControllerPrintBlock.noQueue;
    case ArchiveReprintBlock.noReprint:
      return ControllerPrintBlock.noReprint;
    case null:
  }
  if (!printable) return ControllerPrintBlock.notSliced;
  if (!isGcodeCompatible(slicedForModel, printerModel)) {
    return ControllerPrintBlock.wrongModel;
  }
  return null;
}

/// The print screen of the single-printer controller
/// ([docs/single-printer-controller.md]): a library file or an archive, aimed at
/// the controller's printer and at no other. Everything the queue form asks is here
/// or one tap away, laid out for a phone held sideways instead of upright.
///
/// Pushed over the controller, never replacing it, and answers true when a job
/// was created.
Future<bool> openControllerPrint(
  BuildContext context, {
  required Printer printer,
  required QueueItem draft,
}) async {
  final created = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => ControllerPrintScreen(printer: printer, draft: draft),
    ),
  );
  return created ?? false;
}

class ControllerPrintScreen extends ConsumerStatefulWidget {
  const ControllerPrintScreen({
    super.key,
    required this.printer,
    required this.draft,
  });

  /// The controller's printer. It is the target of the job and cannot be
  /// changed from here.
  final Printer printer;

  /// What is printed, as the phone's print form takes it: a library file
  /// ([libraryFileQueueDraft]) or an archive ([archiveQueueDraft]).
  final QueueItem draft;

  @override
  ConsumerState<ControllerPrintScreen> createState() =>
      _ControllerPrintScreenState();
}

const _maxCopies = 999;

class _ControllerPrintScreenState extends ConsumerState<ControllerPrintScreen> {
  late PrintOptions _options = ref
      .read(settingsRepositoryProvider)
      .loadPrintOptions();

  /// The plate an archive ran on, so a reprint runs the same one; otherwise
  /// null until the user picks one, and the job prints the first plate the file
  /// lists, see [_plate].
  late int? _plateId = widget.draft.plateId;
  int _copies = 1;
  QueueScheduleType _when = QueueScheduleType.asap;
  DateTime? _scheduledTime;

  /// The whole mapping as the sheet confirmed it, or null while the filament is
  /// matched automatically. Never filled from the preview: a stored mapping
  /// reads as picks made by hand, and the automatic match would stop following
  /// the AMS.
  List<int>? _manualMapping;

  /// The switches and the cost centre of the "More options" dialog.
  ControllerJobExtras _extras = const ControllerJobExtras();

  /// Nozzle-rack positions by filament group, written back by the mapping
  /// sheet while it is open.
  final Map<int, int> _rack = {};

  bool _saving = false;

  /// The factor the body is drawn at, for the dialogs this screen opens: they
  /// are routes of their own and would stay at the design size.
  double _scale = 1;

  Printer get _printer => widget.printer;
  QueueItem get _source => widget.draft;
  bool get _isArchive => _source.archiveId != null;

  /// The archive's id or the library file's: every route below is keyed by it
  /// together with [_isArchive].
  int get _sourceId => _source.archiveId ?? _source.libraryFileId!;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // A keyboard must not shrink the body, as on the controller itself.
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          left: false,
          right: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              DashSpace.gutter,
              0,
              DashSpace.gutter,
              DashSpace.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopBar(
                  printer: _printer,
                  name: _source.displayName,
                  title: l10n.controllerPrintTitle,
                ),
                const SizedBox(height: DashSpace.md),
                Expanded(
                  child: ScaleToFit(
                    // The state's own context is above the scale, so the dialogs
                    // this screen opens take it from here.
                    child: Builder(
                      builder: (scaled) {
                        _scale = ControllerScale.of(scaled);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(flex: 3, child: _jobCard(l10n)),
                                  const SizedBox(width: DashSpace.md),
                                  Expanded(flex: 4, child: _filamentCard(l10n)),
                                  const SizedBox(width: DashSpace.md),
                                  Expanded(flex: 3, child: _optionsCard(l10n)),
                                ],
                              ),
                            ),
                            const SizedBox(height: DashSpace.md),
                            _bottomBar(l10n),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Job ---

  PlateList get _plates =>
      ref.read(plateListProvider((_isArchive, _sourceId))).valueOrNull ??
      PlateList.none;

  /// The plate the job prints. A file lists the plates it holds, and they need
  /// not start at 1 or run without gaps (the server reads them off the gcode
  /// names), so the default is the first one listed and not plate 1.
  /// An archive's plate its file no longer lists gives way to the first listed.
  int get _plate {
    final listed = _plates.plates;
    final picked = _plateId;
    if (picked != null &&
        (listed.isEmpty || listed.any((p) => p.index == picked))) {
      return picked;
    }
    return listed.firstOrNull?.index ?? 1;
  }

  /// What the request carries: nothing for plate 1, which is what the server
  /// reads an absent plate as.
  int? get _plateToSend => _plate == 1 ? null : _plate;

  PlateSource get _plateSource =>
      (isArchive: _isArchive, id: _sourceId, plate: _plate);

  /// What the cost preview prices: the plate, the printer and the slots picked
  /// by hand. An empty mapping is matched by the provider as the submit will.
  JobCostKey get _costKey => (
    isArchive: _isArchive,
    id: _sourceId,
    plate: _plate,
    printerId: _printer.id,
    mapping: mappingKey(_manualMapping),
  );

  Widget _jobCard(AppLocalizations l10n) {
    final t = DashTokens.of(context);
    final plates =
        ref.watch(plateListProvider((_isArchive, _sourceId))).valueOrNull ??
        PlateList.none;
    final copiesOffered = ref.watch(batchListingProvider).orFalse;
    final position = plates.plates.indexWhere((p) => p.index == _plate);
    final meta = [
      if (_source.printTimeSeconds case final s?) formatSeconds(l10n, s),
      if (_source.filamentUsedGrams case final g?) fmtGrams(g),
    ];
    return ControllerCard.single(
      title: l10n.controllerPrintJob,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(DashSpace.md),
                child: QueueThumbnail(item: _source, size: _thumbSize),
              ),
              const SizedBox(width: DashSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _source.displayName,
                      style: t.titleSm,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: DashSpace.xs),
                      Text(
                        meta.join(' · '),
                        style: t.monoLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          if (plates.isMultiPlate) ...[
            PrintStepper(
              id: 'controller.print.plate',
              label: l10n.queueEditPlate,
              value: plates.byIndex(_plate)?.name ?? '$_plate',
              // Stepped through the list, not by arithmetic on the numbers.
              onLess: position <= 0 ? null : () => _stepPlate(-1),
              onMore: position >= plates.plates.length - 1
                  ? null
                  : () => _stepPlate(1),
            ),
            const SizedBox(height: DashSpace.sm),
          ],
          if (copiesOffered)
            PrintStepper(
              id: 'controller.print.copies',
              label: l10n.queueEditCopies,
              value: '$_copies',
              lessTooltip: l10n.copiesLess,
              moreTooltip: l10n.copiesMore,
              onLess: _copies <= 1 ? null : () => setState(() => _copies--),
              onMore: _copies >= _maxCopies
                  ? null
                  : () => setState(() => _copies++),
            ),
        ],
      ),
    );
  }

  /// Another plate asks for other filaments, so the hand-picked slots and the
  /// rack positions made for the old one mean nothing now.
  /// Read when tapped, not when built: a second tap before the frame lands
  /// must go one further, not repeat the first.
  void _stepPlate(int by) {
    final list = _plates.plates;
    final next = list.indexWhere((p) => p.index == _plate) + by;
    if (next >= 0 && next < list.length) _setPlate(list[next].index);
  }

  void _setPlate(int plate) => setState(() {
    _plateId = plate;
    _manualMapping = null;
    _rack.clear();
  });

  // --- Filament ---

  Widget _filamentCard(AppLocalizations l10n) {
    final t = DashTokens.of(context);
    final reqs = ref.watch(printRequirementsProvider(_plateSource));
    final status = ref.watch(mappingStatusProvider(_printer.id));
    final remain = ref
        .watch(mappingInventoryRemainProvider(_printer.id))
        .valueOrNull;
    final preferLowest = ref.watch(preferLowestFilamentProvider).valueOrNull;
    final catalog =
        ref.watch(mappingColorCatalogProvider).valueOrNull ??
        ColorCatalog.empty;
    final comparison = queueMappingComparison(
      requirements: reqs.valueOrNull ?? const [],
      status: status.valueOrNull,
      startFrom: _manualMapping,
      remain: remain?.grams,
      preferLowestSetting: preferLowest,
    );
    final waiting =
        (!reqs.hasValue && reqs.isLoading) ||
        (!status.hasValue && status.isLoading);
    return ControllerCard.single(
      title: l10n.queueFilamentMapping,
      trailing: _manualMapping == null
          ? null
          : logTag(
              'controller.print.reset_mapping',
              TextButton(
                onPressed: () => setState(() {
                  _manualMapping = null;
                  _rack.clear();
                }),
                child: Text(l10n.controllerPrintResetMapping),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _manualMapping == null
                ? l10n.controllerPrintAutoMatched(_printer.name)
                : l10n.controllerPrintManualMapping,
            style: t.labelSoft,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: DashSpace.sm),
          Expanded(
            child: waiting
                ? const Center(child: CircularProgressIndicator())
                : comparison.isEmpty
                ? Center(child: Text('—', style: t.bodySoft))
                : ListView.separated(
                    itemCount: comparison.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: DashSpace.sm),
                    itemBuilder: (context, i) => _FilamentRow(
                      comparison: comparison[i],
                      catalog: catalog,
                      dualExternal:
                          (status.valueOrNull?.vtTray?.length ?? 0) > 1,
                      onTap: () => _editMapping(),
                    ),
                  ),
          ),
          ?_costFooter(l10n, t),
        ],
      ),
    );
  }

  /// The job's estimated cost and, while billing is on, the centre it is booked
  /// to. A tap on the centre opens the dialog where it is changed.
  Widget? _costFooter(AppLocalizations l10n, DashTokens t) {
    final cost = ref.watch(jobCostProvider(_costKey)).valueOrNull;
    final billing = costCenterStateOf(ref.watch);
    final selected = billing.step == CostCenterStep.pick
        ? selectedCostCenter(billing.centers, _extras.costCenterId)
        : null;
    final lines = <Widget>[
      if (cost != null)
        Text(
          jobCostText(l10n, ref.watch(currencySymbolProvider), cost, _copies),
          style: t.labelSoft,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      if (selected != null)
        logTag(
          'controller.print.cost_center',
          InkWell(
            onTap: _openMore,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: DashSpace.xs),
              child: Text(
                l10n.controllerPrintCostCenter(
                  selected.isPrivate
                      ? l10n.queueCostCenterPersonal(selected.name)
                      : selected.name,
                ),
                style: t.bodyBold,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      if (jobExceedsBudget(cost, selected, _copies))
        Text(
          l10n.queueInsufficientBudget,
          style: t.labelSoft.copyWith(color: t.dangerInk),
          // The one line that says why the server will refuse the job.
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      if (billing.step == CostCenterStep.failed)
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.queueCostCenterLoadFailed,
                style: t.labelSoft.copyWith(color: t.warningInk),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            logTag(
              'controller.print.cost_center_retry',
              TextButton(
                onPressed: () => ref.invalidate(printableCostCentersProvider),
                child: Text(l10n.retry),
              ),
            ),
          ],
        ),
    ];
    if (lines.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.only(top: DashSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: lines,
      ),
    );
  }

  Future<void> _editMapping() async {
    final l10n = AppLocalizations.of(context);
    // The sheet writes rack picks back while it is open, so a sheet dismissed
    // without saving has to take them back, as it does its slot picks.
    final rackBefore = {..._rack};
    final mapping = await showQueueMappingSheet(
      context,
      item: _draft,
      printerId: _printer.id,
      printerName: _printer.name,
      confirmLabel: l10n.fmSave,
      plateId: _plateToSend,
      startFrom: _manualMapping ?? const [],
      rackChoice: _rack,
      onRackChoice: (choice) => setState(
        () => _rack
          ..clear()
          ..addAll(choice),
      ),
      dialogScale: _scale,
    );
    if (!mounted) return;
    if (mapping == null) {
      setState(
        () => _rack
          ..clear()
          ..addAll(rackBefore),
      );
    } else if (mapping.isNotEmpty) {
      // Empty: the printer reported nothing to map to, and none is sent then.
      setState(() => _manualMapping = mapping);
    }
  }

  QueueItem get _draft => QueueItem.draft(
    archiveId: _source.archiveId,
    libraryFileId: _isArchive ? null : _source.libraryFileId,
    name: _source.displayName,
    thumbnail: _source.archiveThumbnail ?? _source.libraryFileThumbnail,
    printerId: _printer.id,
    printerName: _printer.name,
    slicedForModel: _source.slicedForModel,
  );

  // --- When and options ---

  bool get _triState => ref.watch(triStateCalibrationProvider).orFalse;

  Widget _optionsCard(AppLocalizations l10n) {
    final triState = _triState;
    return ControllerCard.single(
      title: l10n.controllerPrintOptions,
      trailing: logTag(
        'controller.print.more',
        TextButton(onPressed: _openMore, child: Text(l10n.controllerPrintMore)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PrintOptionRow(
            id: 'controller.print.bed_levelling',
            label: l10n.queueOptBedLevelling,
            value: calibrationLabel(l10n, _options.bedLevelling, triState),
            onTap: () => setState(
              () => _options = _options.copyWith(
                bedLevelling: nextCalibration(_options.bedLevelling, triState),
              ),
            ),
          ),
          const SizedBox(height: DashSpace.xs),
          PrintOptionRow(
            id: 'controller.print.flow_cali',
            label: l10n.queueOptFlowCali,
            value: calibrationLabel(l10n, _options.flowCali, triState),
            onTap: () => setState(
              () => _options = _options.copyWith(
                flowCali: nextCalibration(_options.flowCali, triState),
              ),
            ),
          ),
          const SizedBox(height: DashSpace.xs),
          PrintOptionRow(
            id: 'controller.print.timelapse',
            label: l10n.queueOptTimelapse,
            value: _options.timelapse ? l10n.commonOn : l10n.commonOff,
            on: _options.timelapse,
            onTap: () => setState(
              () =>
                  _options = _options.copyWith(timelapse: !_options.timelapse),
            ),
          ),
          if (_when == QueueScheduleType.scheduled) ...[
            const SizedBox(height: DashSpace.xs),
            PrintOptionRow(
              id: 'controller.print.pick_time',
              label: l10n.queueEditPickTime,
              value: _scheduledTime == null
                  ? '—'
                  : DateTimeFormats.of(context).dateTime(_scheduledTime!),
              on: _scheduledTime != null,
              onTap: _pickTime,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openMore() => showControllerMoreOptions(
    context,
    scale: _scale,
    printer: _printer,
    options: _options,
    extras: _extras,
    when: _when,
    copies: _copies,
    costKey: _costKey,
    confirmOutcomeSticky: _confirmOutcomeSticky,
    onOptions: (next) => setState(() => _options = next),
    onExtras: (next) => setState(() => _extras = next),
  );

  // --- Bottom bar ---

  Widget _bottomBar(AppLocalizations l10n) {
    final t = DashTokens.of(context);
    final item = ref.watch(controllerPrinterProvider(_printer.id)).item;
    final status = item?.status;
    final held = ref.watch(awaitingReviewProvider);
    final compatible = isGcodeCompatible(
      _source.slicedForModel,
      _printer.model,
    );
    final reqs = ref.watch(printRequirementsProvider(_plateSource)).valueOrNull;
    final comparison = queueMappingComparison(
      requirements: reqs ?? const [],
      status: ref.watch(mappingStatusProvider(_printer.id)).valueOrNull,
      startFrom: _manualMapping,
    );
    final unmapped = comparison.where((c) => c.loaded == null).length;
    final billing = costCenterStateOf(ref.watch).step;
    // What `POST /queue/` would refuse this account, judged again here as the
    // dialog that opened the screen judged it: rights change while it is open.
    final refused = _isArchive
        ? ref.watch(archiveReprintBlockProvider(_source.createdById))
        : ref.watch(permissionProvider(Permissions.queueCreate))
        ? null
        : ArchiveReprintBlock.noQueue;
    final String note;
    var warn = true;
    if (item == null) {
      note = l10n.controllerPrinterGone;
    } else if (refused != null) {
      note = refused.reason(l10n);
    } else if (!compatible) {
      note = l10n.controllerPrintWrongModel(
        '${_source.slicedForModel}',
        _printer.model ?? _printer.name,
      );
    } else if (unmapped > 0) {
      note = l10n.controllerPrintUnmapped(unmapped);
    } else if (billing == CostCenterStep.none) {
      note = l10n.controllerPrintNoCostCenter;
    } else if (billing == CostCenterStep.refused) {
      note = l10n.controllerPrintCostCentersRefused;
    } else {
      warn = false;
      note = status?.connected == false
          ? l10n.controllerPrintOffline
          : (status?.isPrinting ?? false)
          ? l10n.controllerPrintBusy
          : held
          ? l10n.queueEditAwaitingReviewNote
          : '';
    }
    final canPrint =
        !_saving &&
        item != null &&
        refused == null &&
        compatible &&
        reqs != null &&
        costCenterAllowsCreate(billing);
    return SizedBox(
      height: controllerButtonHeight,
      child: Row(
        children: [
          Expanded(
            child: Text(
              note,
              style: t.bodySoft.copyWith(color: warn ? t.warningInk : null),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: DashSpace.md),
          _WhenChoices(
            labels: [
              l10n.controllerPrintNow,
              l10n.queueScheduleQueue,
              l10n.queueScheduleSchedule,
            ],
            selected: _when.index,
            onChanged: (i) => setState(() {
              _when = QueueScheduleType.values[i];
              // Staged for a manual start only in Queue, as the form has it.
              if (_when != QueueScheduleType.queue) {
                _extras = _extras.copyWith(requireManualStart: false);
              }
            }),
          ),
          const SizedBox(width: DashSpace.md),
          logTag(
            'controller.print.submit',
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(_submitWidth, controllerButtonHeight),
              ),
              onPressed: !canPrint || _awaitingTime ? null : _submit,
              child: Text(switch (_when) {
                QueueScheduleType.asap => l10n.controllerPrintNowAction,
                QueueScheduleType.queue => l10n.fmAddToQueue,
                QueueScheduleType.scheduled => l10n.queueScheduleSchedule,
              }),
            ),
          ),
        ],
      ),
    );
  }

  /// A reprint of an archive that already asks, as the phone's print form reads
  /// it (`queue_edit_screen.dart`, `_confirmOutcomeSticky`).
  bool get _confirmOutcomeSticky => _isArchive && _source.confirmOutcome;

  /// A scheduled job with no time yet has nothing to be scheduled for.
  bool get _awaitingTime =>
      _when == QueueScheduleType.scheduled && _scheduledTime == null;

  Future<void> _pickTime() async {
    final picked = await pickDateTime(
      context,
      initial: _scheduledTime,
      firstDate: clock.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => _scheduledTime = picked);
  }

  // --- Submit ---

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final providers = ProviderScope.containerOf(context, listen: false);
    final held = ref.read(awaitingReviewProvider);
    setState(() => _saving = true);

    final mapping = await _matchMapping();
    final outcome = await ref
        .read(queueProvider.notifier)
        .runOnRepository(
          (repo) => createQueueJobs(
            repo: repo,
            providers: providers,
            archiveId: _source.archiveId,
            libraryFileId: _isArchive ? null : _source.libraryFileId,
            sourceName: _source.displayName,
            printerId: _printer.id,
            copies: _copies,
            insertAtTop: _when == QueueScheduleType.asap,
            plateId: _plateToSend,
            confirmOutcomeChoice: _extras.confirmOutcome,
            confirmOutcomeSticky: _confirmOutcomeSticky,
            buildOptions: () => QueueCreateOptions(
              amsMapping: mapping,
              scheduledTime: _when == QueueScheduleType.scheduled
                  ? _scheduledTime?.toUtc().toIso8601String()
                  : null,
              requirePreviousSuccess: _extras.requirePreviousSuccess,
              autoOffAfter: _extras.autoOffAfter,
              // A user held for review always waits, whatever they chose.
              manualStart: held || _extras.requireManualStart,
              bedLevelling: _options.bedLevelling,
              flowCali: _options.flowCali,
              vibrationCali: _options.vibrationCali,
              layerInspect: _options.layerInspect,
              timelapse: _options.timelapse,
              nozzleOffsetCali: _dualNozzle ? _options.nozzleOffsetCali : null,
              gcodeInjection: _injectionPayload,
              preheatOverride: _extras.preheatOverride,
              preheatChamberTargetOverride: _chamberPayload,
              costCenterId: _costCenterPayload,
              nozzleRackChoice: _rack,
            ),
          ),
          'controller_print.create',
        );

    // Remembered only once a job was really created with them.
    if (outcome.isOk) {
      await ref.read(settingsRepositoryProvider).savePrintOptions(_options);
    }
    if (!mounted) return;
    setState(() => _saving = false);
    messenger.snack(queueWriteMessage(l10n, outcome) ?? l10n.queueCreateAdded);
    if (outcome.isOk) navigator.pop(true);
  }

  /// Off sends no target; otherwise the stepper's, within what the server takes.
  int? get _chamberPayload {
    final target = _extras.chamberTarget;
    if (_extras.preheatOverride == 'off' || target == null) return null;
    return target.clamp(0, ref.read(chamberMaxTargetProvider));
  }

  /// The centre the job is booked to; null leaves the key out, as on a server
  /// without billing.
  int? get _costCenterPayload => selectedCostCenter(
    costCenterStateOf(ref.read).centers,
    _extras.costCenterId,
  )?.id;

  bool get _dualNozzle =>
      queueDualNozzleModels.contains(_printer.model?.toUpperCase());

  /// Only while the server holds snippets: the flag does nothing without them.
  bool? get _injectionPayload =>
      (ref.read(gcodeSnippetModelsProvider).valueOrNull ?? const {}).isEmpty
      ? null
      : _options.gcodeInjection;

  /// The mapping sent with the job: matched afresh against the printer as it
  /// is now, starting from the slots picked by hand. Null when the printer
  /// reports nothing loaded, which leaves the choice to the server.
  Future<List<int>?> _matchMapping() async {
    try {
      return await queueMappingToSend(
        requirements: await ref.read(
          printRequirementsProvider(_plateSource).future,
        ),
        printers: ref.read(printersRepositoryProvider),
        printerId: _printer.id,
        startFrom: _manualMapping ?? const [],
        preferLowestSetting: ref.read(preferLowestFilamentProvider).valueOrNull,
      );
    } on Object {
      // A lost session surfaces on the write itself; the mapping only rides
      // along with it.
      return null;
    }
  }
}

const _thumbSize = 76.0;
const _submitWidth = 220.0;
const _swatch = 24.0;

/// A bar button's own height, as the controller's top bar has it.
const _barHeight = 44.0;
const _lockHeight = 36.0;

/// What the screen's bar shows: exit, what is being printed, and the printer it
/// is locked to.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.printer,
    required this.name,
    required this.title,
  });

  final Printer printer;
  final String name;
  final String title;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    // A minimum, not a size: a larger system font makes the two lines taller.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _barHeight),
      child: Row(
        children: [
          logTag(
            'controller.print.close',
            IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              color: t.textPrimary,
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          const SizedBox(width: DashSpace.sm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.titleMd, maxLines: 1),
                Text(
                  name,
                  style: t.monoLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: DashSpace.md),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: DashSpace.md),
            height: _lockHeight,
            decoration: BoxDecoration(
              color: t.subCard,
              borderRadius: BorderRadius.circular(DashSpace.md),
              border: Border.all(color: t.subCardBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: DashSpace.lg,
                  color: t.textSecondary,
                ),
                const SizedBox(width: DashSpace.sm),
                Text(printer.name, style: t.bodyBold, maxLines: 1),
                if (printer.model != null) ...[
                  const SizedBox(width: DashSpace.sm),
                  Text(printer.model!, style: t.labelSoft, maxLines: 1),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Now, Queue or Schedule: three choices at their own widths, since the
/// longest label of one language is a good deal longer than the shortest of
/// another and equal thirds would cut it.
class _WhenChoices extends StatelessWidget {
  const _WhenChoices({
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final radius = BorderRadius.circular(DashSpace.md);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, label) in labels.indexed) ...[
          if (i > 0) const SizedBox(width: DashSpace.sm),
          logTag(
            'controller.print.when',
            Material(
              color: i == selected
                  ? t.accent.withValues(alpha: 0.16)
                  : t.subCard,
              shape: RoundedRectangleBorder(
                borderRadius: radius,
                side: BorderSide(
                  color: i == selected
                      ? t.accent.withValues(alpha: 0.4)
                      : t.subCardBorder,
                ),
              ),
              child: InkWell(
                borderRadius: radius,
                onTap: () => onChanged(i),
                child: Container(
                  height: controllerButtonHeight,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: DashSpace.md),
                  child: Text(
                    label,
                    maxLines: 1,
                    style: i == selected
                        ? t.monoValue.copyWith(color: t.accentInk)
                        : t.monoValue,
                  ),
                ),
              ),
            ),
            selected: i == selected,
          ),
        ],
      ],
    );
  }
}

/// One filament of the file against the slot it takes on this printer.
class _FilamentRow extends StatelessWidget {
  const _FilamentRow({
    required this.comparison,
    required this.catalog,
    required this.dualExternal,
    required this.onTap,
  });

  final FilamentComparison comparison;
  final ColorCatalog catalog;
  final bool dualExternal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final req = comparison.requirement;
    final loaded = comparison.loaded;
    final unmatched =
        loaded == null || comparison.status != FilamentMatch.match;
    final radius = BorderRadius.circular(DashSpace.md);
    return logTag(
      'controller.print.filament',
      Material(
        color: unmatched ? t.warning.withValues(alpha: 0.10) : t.subCard,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: unmatched
                ? t.warning.withValues(alpha: 0.5)
                : t.subCardBorder,
          ),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: SizedBox(
            height: controllerButtonHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: DashSpace.md),
              child: Row(
                children: [
                  Expanded(
                    child: _Slot(
                      colour: req.color,
                      title: req.type ?? '',
                      subtitle: mappingColorName(
                        l10n,
                        catalog,
                        req.color ?? '',
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: DashSpace.lg,
                    color: t.textTertiary,
                  ),
                  Expanded(
                    child: loaded == null
                        ? _Slot(
                            colour: null,
                            title: l10n.controllerPrintNotLoaded,
                            subtitle: '',
                            warn: true,
                          )
                        : _Slot(
                            colour: loaded.color,
                            title:
                                '${_slotName(l10n, loaded)} · ${loaded.type}',
                            subtitle: loaded.remain >= 0
                                ? '${loaded.remain}%'
                                : '',
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _slotName(AppLocalizations l10n, LoadedFilament f) {
    if (f.isExternal) {
      if (!dualExternal) return l10n.mappingExternalSpool;
      return f.globalTrayId == externalTrayIdBase ? 'Ext-L' : 'Ext-R';
    }
    return formatSlotLabel(f.amsId, f.trayId, isHt: f.isHt);
  }
}

class _Slot extends StatelessWidget {
  const _Slot({
    required this.colour,
    required this.title,
    required this.subtitle,
    this.warn = false,
  });

  final String? colour;
  final String title;
  final String subtitle;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final hex = sixHexDigits(colour);
    return Row(
      children: [
        Container(
          width: _swatch,
          height: _swatch,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hex == null
                ? null
                : Color(0xFF000000 | int.parse(hex, radix: 16)),
            border: Border.all(color: t.textPrimary.withValues(alpha: 0.3)),
          ),
          child: hex == null
              ? Icon(
                  Icons.help_outline_rounded,
                  size: DashSpace.lg,
                  color: t.textTertiary,
                )
              : null,
        ),
        const SizedBox(width: DashSpace.sm),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: t.titleSm.copyWith(color: warn ? t.warningInk : null),
                // A flag may take two lines where a slot's name takes one.
                maxLines: warn ? 2 : 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  style: t.monoLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
