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
import '../../core/models/calibration_option.dart';
import '../../core/models/library_file.dart';
import '../../core/models/plate_list.dart';
import '../../core/models/printer.dart';
import '../../core/models/queue_item.dart';
import '../../core/printers/gcode_compat.dart';
import '../../core/settings/print_options.dart';
import '../../core/theme/dash_theme.dart';
import '../../data/queue_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/dash_async.dart';
import '../files/library_thumbnail.dart';
import '../queue/queue_create_service.dart';
import '../queue/queue_edit_screen.dart';
import '../queue/queue_mapping_sheet.dart';
import '../queue/queue_providers.dart';
import '../queue/queue_removal.dart';
import '../slicer/slice_providers.dart';
import '../stats/stats_common.dart';
import '../orders/orders_providers.dart';
import 'controller_controls.dart';
import 'controller_providers.dart';
import 'scale_to_fit.dart';

/// The print screen of the single-printer controller
/// ([docs/single-printer-controller.md]): a library file, aimed at the
/// controller's printer and at no other. Everything the queue form asks is here
/// or one tap away, laid out for the 800x360 body instead of a phone held
/// upright.
///
/// Pushed over the controller, never replacing it, and answers true when a job
/// was created.
Future<bool> openControllerPrint(
  BuildContext context, {
  required Printer printer,
  required LibraryFile file,
}) async {
  final created = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => ControllerPrintScreen(printer: printer, file: file),
    ),
  );
  return created ?? false;
}

class ControllerPrintScreen extends ConsumerStatefulWidget {
  const ControllerPrintScreen({
    super.key,
    required this.printer,
    required this.file,
  });

  /// The controller's printer. It is the target of the job and cannot be
  /// changed from here.
  final Printer printer;
  final LibraryFile file;

  @override
  ConsumerState<ControllerPrintScreen> createState() =>
      _ControllerPrintScreenState();
}

const _maxCopies = 999;

class _ControllerPrintScreenState extends ConsumerState<ControllerPrintScreen> {
  late PrintOptions _options = ref
      .read(settingsRepositoryProvider)
      .loadPrintOptions();

  /// Null until the user picks one: the job then prints plate 1.
  int? _plateId;
  int _copies = 1;
  QueueScheduleType _when = QueueScheduleType.asap;
  DateTime? _scheduledTime;

  /// The whole mapping as the sheet confirmed it, or null while the filament is
  /// matched automatically. Never filled from the preview: a stored mapping
  /// reads as picks made by hand, and the automatic match would stop following
  /// the AMS.
  List<int>? _manualMapping;

  /// Nozzle-rack positions by filament group, written back by the mapping
  /// sheet while it is open.
  final Map<int, int> _rack = {};

  bool _saving = false;

  Printer get _printer => widget.printer;
  LibraryFile get _file => widget.file;

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
                  file: _file,
                  title: l10n.controllerPrintTitle,
                ),
                const SizedBox(height: DashSpace.md),
                Expanded(
                  child: ScaleToFit(
                    child: Column(
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

  PlateSource get _plateSource =>
      (isArchive: false, id: _file.id, plate: _plateId ?? 1);

  Widget _jobCard(AppLocalizations l10n) {
    final t = DashTokens.of(context);
    final plates =
        ref.watch(plateListProvider((false, _file.id))).valueOrNull ??
        PlateList.none;
    final copiesOffered = ref.watch(batchListingProvider).orFalse;
    final meta = [
      if (_file.printTimeSeconds case final s?) formatSeconds(l10n, s),
      if (_file.filamentUsedGrams case final g?) fmtGrams(g),
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
                child: LibraryThumbnail(
                  fileId: _file.id,
                  hasThumbnail: _file.thumbnailPath != null,
                  size: _thumbSize,
                ),
              ),
              const SizedBox(width: DashSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _file.displayName,
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
            _Stepper(
              id: 'controller.print.plate',
              label: l10n.queueEditPlate,
              value: plates.byIndex(_plateId ?? 1)?.name ?? '${_plateId ?? 1}',
              onLess: (_plateId ?? 1) <= 1
                  ? null
                  : () => _setPlate((_plateId ?? 1) - 1),
              onMore: (_plateId ?? 1) >= plates.plates.length
                  ? null
                  : () => _setPlate((_plateId ?? 1) + 1),
            ),
            const SizedBox(height: DashSpace.sm),
          ],
          if (copiesOffered)
            _Stepper(
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
        ],
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
      plateId: _plateId,
      startFrom: _manualMapping ?? const [],
      rackChoice: _rack,
      onRackChoice: (choice) => setState(
        () => _rack
          ..clear()
          ..addAll(choice),
      ),
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
    libraryFileId: _file.id,
    name: _file.displayName,
    thumbnail: _file.thumbnailPath,
    printerId: _printer.id,
    printerName: _printer.name,
    slicedForModel: _file.slicedForModel,
  );

  // --- When and options ---

  bool get _triState => ref.watch(triStateCalibrationProvider).orFalse;

  Widget _optionsCard(AppLocalizations l10n) {
    final triState = _triState;
    return ControllerCard.single(
      title: l10n.controllerPrintOptions,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OptionRow(
            id: 'controller.print.bed_levelling',
            label: l10n.queueOptBedLevelling,
            value: _calibrationLabel(l10n, _options.bedLevelling, triState),
            onTap: () => setState(
              () => _options = _copy(
                bed: _nextCalibration(_options.bedLevelling, triState),
              ),
            ),
          ),
          const SizedBox(height: DashSpace.xs),
          _OptionRow(
            id: 'controller.print.flow_cali',
            label: l10n.queueOptFlowCali,
            value: _calibrationLabel(l10n, _options.flowCali, triState),
            onTap: () => setState(
              () => _options = _copy(
                flow: _nextCalibration(_options.flowCali, triState),
              ),
            ),
          ),
          const SizedBox(height: DashSpace.xs),
          _OptionRow(
            id: 'controller.print.timelapse',
            label: l10n.queueOptTimelapse,
            value: _options.timelapse ? l10n.commonOn : l10n.commonOff,
            on: _options.timelapse,
            onTap: () => setState(
              () => _options = _copy(timelapse: !_options.timelapse),
            ),
          ),
          if (_when == QueueScheduleType.scheduled) ...[
            const SizedBox(height: DashSpace.xs),
            _OptionRow(
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

  PrintOptions _copy({
    CalibrationOption? bed,
    CalibrationOption? flow,
    bool? timelapse,
  }) => PrintOptions(
    bedLevelling: bed ?? _options.bedLevelling,
    flowCali: flow ?? _options.flowCali,
    vibrationCali: _options.vibrationCali,
    layerInspect: _options.layerInspect,
    timelapse: timelapse ?? _options.timelapse,
    nozzleOffsetCali: _options.nozzleOffsetCali,
    gcodeInjection: _options.gcodeInjection,
  );

  /// Auto, On, Off round again where the server can keep `auto`; On and Off
  /// where it cannot, which is what the form's switch does too.
  CalibrationOption _nextCalibration(CalibrationOption now, bool triState) {
    if (!triState) {
      return now.asSwitch ? CalibrationOption.off : CalibrationOption.on;
    }
    return switch (now) {
      CalibrationOption.auto => CalibrationOption.on,
      CalibrationOption.on => CalibrationOption.off,
      CalibrationOption.off => CalibrationOption.auto,
    };
  }

  String _calibrationLabel(
    AppLocalizations l10n,
    CalibrationOption value,
    bool triState,
  ) {
    if (!triState) return value.asSwitch ? l10n.commonOn : l10n.commonOff;
    return switch (value) {
      CalibrationOption.auto => l10n.commonAuto,
      CalibrationOption.on => l10n.commonOn,
      CalibrationOption.off => l10n.commonOff,
    };
  }

  // --- Bottom bar ---

  Widget _bottomBar(AppLocalizations l10n) {
    final t = DashTokens.of(context);
    final item = ref.watch(controllerPrinterProvider(_printer.id)).item;
    final status = item?.status;
    final held = ref.watch(awaitingReviewProvider);
    final compatible = isGcodeCompatible(_file.slicedForModel, _printer.model);
    final reqs = ref.watch(printRequirementsProvider(_plateSource)).valueOrNull;
    final comparison = queueMappingComparison(
      requirements: reqs ?? const [],
      status: ref.watch(mappingStatusProvider(_printer.id)).valueOrNull,
      startFrom: _manualMapping,
    );
    final unmapped = comparison.where((c) => c.loaded == null).length;
    final String note;
    var warn = true;
    if (!compatible) {
      note = l10n.controllerPrintWrongModel(
        '${_file.slicedForModel}',
        _printer.model ?? _printer.name,
      );
    } else if (unmapped > 0) {
      note = l10n.controllerPrintUnmapped(unmapped);
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
    final canPrint = !_saving && item != null && compatible && reqs != null;
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
            onChanged: (i) =>
                setState(() => _when = QueueScheduleType.values[i]),
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
            archiveId: null,
            libraryFileId: _file.id,
            sourceName: _file.displayName,
            printerId: _printer.id,
            copies: _copies,
            insertAtTop: _when == QueueScheduleType.asap,
            plateId: _plateId,
            confirmOutcomeChoice: null,
            confirmOutcomeSticky: false,
            buildOptions: () => QueueCreateOptions(
              amsMapping: mapping,
              scheduledTime: _when == QueueScheduleType.scheduled
                  ? _scheduledTime?.toUtc().toIso8601String()
                  : null,
              requirePreviousSuccess: false,
              autoOffAfter: false,
              // A user held for review always waits, whatever they chose.
              manualStart: held,
              bedLevelling: _options.bedLevelling,
              flowCali: _options.flowCali,
              vibrationCali: _options.vibrationCali,
              layerInspect: _options.layerInspect,
              timelapse: _options.timelapse,
              nozzleOffsetCali: _dualNozzle ? _options.nozzleOffsetCali : null,
              gcodeInjection: _injectionPayload,
              preheatOverride: 'inherit',
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
    required this.file,
    required this.title,
  });

  final Printer printer;
  final LibraryFile file;
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
                  file.displayName,
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

/// A − / + row with the value between: plate and copies.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.id,
    required this.label,
    required this.value,
    required this.onLess,
    required this.onMore,
    this.lessTooltip,
    this.moreTooltip,
  });

  final String id;
  final String label;
  final String value;
  final VoidCallback? onLess;
  final VoidCallback? onMore;
  final String? lessTooltip;
  final String? moreTooltip;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    Widget button(
      String suffix,
      IconData icon,
      VoidCallback? onTap,
      String? tip,
    ) {
      final b = logTag(
        '$id.$suffix',
        FilledButton(
          style: controllerButtonStyle(
            t,
            minimumSize: const Size.square(controllerButtonHeight),
            padding: EdgeInsets.zero,
          ),
          onPressed: onTap,
          child: Icon(icon),
        ),
      );
      return tip == null ? b : Tooltip(message: tip, child: b);
    }

    return Row(
      children: [
        button('less', Icons.remove_rounded, onLess, lessTooltip),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: t.labelSoft, maxLines: 1),
              Text(
                value,
                style: t.titleSm,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        button('more', Icons.add_rounded, onMore, moreTooltip),
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

/// A print option that changes by being tapped: its name, and its value at the
/// far end.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.id,
    required this.label,
    required this.value,
    required this.onTap,
    this.on = false,
  });

  final String id;
  final String label;
  final String value;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final radius = BorderRadius.circular(DashSpace.md);
    return logTag(
      id,
      Material(
        color: on ? t.accent.withValues(alpha: 0.16) : t.subCard,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: on ? t.accent.withValues(alpha: 0.4) : t.subCardBorder,
          ),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: SizedBox(
            height: _optionHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: DashSpace.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: t.bodyPlain,
                      // Two lines where a language names the option at length.
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: DashSpace.sm),
                  Text(
                    value,
                    style: t.bodyBold.copyWith(color: on ? t.accentInk : null),
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three of these and the When switch fill the card of the 800x360 body.
const _optionHeight = 48.0;
