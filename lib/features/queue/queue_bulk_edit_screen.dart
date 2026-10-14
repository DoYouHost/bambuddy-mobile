import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/calibration_option.dart';
import '../../core/models/current_user.dart';
import '../../core/theme/dash_theme.dart';
import '../../data/queue_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/dash_async.dart';
import 'queue_form_parts.dart';
import 'queue_providers.dart';
import 'queue_removal.dart';
import 'package:app_diagnostics/app_diagnostics.dart';

/// The one sentence a bulk edit ends with. The route answers 200 for rows it
/// left alone (`print_queue.py::bulk_update_queue_items`), so "done" has to say
/// how many were not.
String queueBulkSummary(AppLocalizations l10n, QueueBulkResult result) => [
  if (result.updated > 0)
    l10n.queueBulkUpdated(result.updated)
  else
    l10n.queueBulkNothingUpdated,
  if (result.skipped > 0) l10n.queueBulkSkipped(result.skipped),
].join('. ');

/// Opens the bulk edit for [itemIds] and says whether anything was applied, so
/// the caller drops its selection only then.
Future<bool> openQueueBulkEdit(BuildContext context, List<int> itemIds) async {
  final applied = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => QueueBulkEditScreen(itemIds: itemIds),
    ),
  );
  return applied ?? false;
}

/// What the printer select can hold: leave the printer, take the items off
/// theirs (`id` null), or put them on one.
typedef _PrinterPick = ({bool set, int? id});
const _keepPrinter = (set: false, id: null);
const _noPrinter = (set: true, id: null);

/// The web's "Edit N items" modal (`QueuePage.tsx::BulkEditModal`): the same
/// thirteen settings, each left alone until the user picks a value for it. A
/// setting nobody touched is never sent, so editing the timelapse of ten items
/// cannot rewrite their calibration.
class QueueBulkEditScreen extends ConsumerStatefulWidget {
  const QueueBulkEditScreen({super.key, required this.itemIds});

  final List<int> itemIds;

  @override
  ConsumerState<QueueBulkEditScreen> createState() =>
      _QueueBulkEditScreenState();
}

class _QueueBulkEditScreenState extends ConsumerState<QueueBulkEditScreen> {
  _PrinterPick _printer = _keepPrinter;
  bool? _manualStart;
  bool? _autoOffAfter;
  bool? _requirePreviousSuccess;
  bool? _gcodeInjection;
  CalibrationOption? _bedLevelling;
  CalibrationOption? _flowCali;
  bool? _vibrationCali;
  bool? _layerInspect;
  bool? _timelapse;
  bool? _useAms;
  bool? _confirmOutcome;
  CalibrationOption? _nozzleOffsetCali;

  bool _saving = false;

  QueueBulkChanges get _changes => QueueBulkChanges(
    printerId: _printer.set ? _printer.id : kQueueUpdateUnset,
    manualStart: _manualStart,
    autoOffAfter: _autoOffAfter,
    requirePreviousSuccess: _requirePreviousSuccess,
    gcodeInjection: _gcodeInjection,
    bedLevelling: _bedLevelling,
    flowCali: _flowCali,
    vibrationCali: _vibrationCali,
    layerInspect: _layerInspect,
    timelapse: _timelapse,
    useAms: _useAms,
    confirmOutcome: _confirmOutcome,
    nozzleOffsetCali: _nozzleOffsetCali,
  );

  Future<void> _apply() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    final (:outcome, :result) = await ref
        .read(queueProvider.notifier)
        .bulkUpdate(widget.itemIds, _changes);
    if (!mounted) return;
    setState(() => _saving = false);
    final failure = queueWriteMessage(l10n, outcome);
    if (failure != null || result == null) {
      if (failure != null) messenger.snack(failure);
      return;
    }
    messenger.snack(queueBulkSummary(l10n, result));
    navigator.pop(true);
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
          title: l10n.queueBulkTitle(widget.itemIds.length),
          actions: [
            QueueSubmitAction(
              id: 'queue_bulk.apply',
              label: l10n.queueBulkApply,
              onPressed: _saving || _changes.isEmpty ? null : _apply,
            ),
          ],
        ),
        body: AbsorbPointer(
          absorbing: _saving,
          child: ListView(
            padding: screenListPadding(context),
            children: [
              Text(l10n.queueBulkIntro, style: t.labelSoft),
              const SizedBox(height: DashSpace.lg),
              _printerSection(l10n),
              const SizedBox(height: DashSpace.lg),
              _queueOptionsSection(l10n),
              const SizedBox(height: DashSpace.lg),
              _printOptionsSection(l10n),
            ],
          ),
        ),
      ),
    );
  }

  Widget _printerSection(AppLocalizations l10n) {
    final printers = ref.watch(allPrintersProvider).valueOrNull ?? const [];
    return QueueSectionCard(
      tone: QueueSectionTone.target,
      title: l10n.queueEditPrinter,
      child: dashCombo<_PrinterPick>(
        context,
        id: 'queue_bulk.printer',
        label: Text(l10n.queueEditPrinter),
        filterable: true,
        initialSelection: _printer,
        onSelected: (pick) => setState(() => _printer = pick ?? _keepPrinter),
        entries: [
          DropdownMenuEntry(
            value: _keepPrinter,
            label: l10n.queueBulkNoChange,
            labelWidget: logTag(
              'queue_bulk.printer.keep',
              Text(l10n.queueBulkNoChange),
            ),
          ),
          DropdownMenuEntry(
            value: _noPrinter,
            label: l10n.queueBulkUnassigned,
            labelWidget: logTag(
              'queue_bulk.printer.none',
              Text(l10n.queueBulkUnassigned),
            ),
          ),
          for (final p in printers)
            DropdownMenuEntry(
              value: (set: true, id: p.id),
              label: p.name,
              labelWidget: logTag('queue_bulk.printer.option', Text(p.name)),
            ),
        ],
      ),
    );
  }

  Widget _queueOptionsSection(AppLocalizations l10n) {
    // The route does not ask for it, the web greys the row without it.
    final mayControl = ref.watch(
      permissionProvider(Permissions.printersControl),
    );
    final offersInjection =
        (ref.watch(gcodeSnippetModelsProvider).valueOrNull ?? const {})
            .isNotEmpty;
    return QueueSectionCard(
      tone: QueueSectionTone.schedule,
      title: l10n.queueBulkQueueOptions,
      child: Column(
        children: [
          _SwitchChoice(
            id: 'queue_bulk.manual_start',
            title: l10n.queueEditRequireManualStart,
            value: _manualStart,
            onChanged: (v) => setState(() => _manualStart = v),
          ),
          _SwitchChoice(
            id: 'queue_bulk.auto_off',
            title: l10n.queueEditPowerOff,
            value: _autoOffAfter,
            enabled: mayControl,
            onChanged: (v) => setState(() => _autoOffAfter = v),
          ),
          _SwitchChoice(
            id: 'queue_bulk.require_previous',
            title: l10n.queueEditRequirePrevious,
            value: _requirePreviousSuccess,
            onChanged: (v) => setState(() => _requirePreviousSuccess = v),
          ),
          // Offered only while the server holds snippets, as in the form: the
          // flag does nothing without them.
          if (offersInjection)
            _SwitchChoice(
              id: 'queue_bulk.gcode_injection',
              title: l10n.queueEditGcodeInjection,
              value: _gcodeInjection,
              onChanged: (v) => setState(() => _gcodeInjection = v),
            ),
        ],
      ),
    );
  }

  Widget _printOptionsSection(AppLocalizations l10n) {
    final triState = ref.watch(triStateCalibrationProvider).orFalse;
    // The web shows the nozzle offset when any printer has two nozzles.
    final hasDualNozzle = (ref.watch(allPrintersProvider).valueOrNull ?? [])
        .any((p) => p.nozzleCount == 2);
    return QueueSectionCard(
      tone: QueueSectionTone.options,
      title: l10n.queueEditPrintOptions,
      child: Column(
        children: [
          _CalibrationChoice(
            id: 'queue_bulk.bed_levelling',
            title: l10n.queueOptBedLevelling,
            value: _bedLevelling,
            triState: triState,
            onChanged: (v) => setState(() => _bedLevelling = v),
          ),
          _CalibrationChoice(
            id: 'queue_bulk.flow_cali',
            title: l10n.queueOptFlowCali,
            value: _flowCali,
            triState: triState,
            onChanged: (v) => setState(() => _flowCali = v),
          ),
          _SwitchChoice(
            id: 'queue_bulk.vibration_cali',
            title: l10n.queueOptVibrationCali,
            value: _vibrationCali,
            onChanged: (v) => setState(() => _vibrationCali = v),
          ),
          _SwitchChoice(
            id: 'queue_bulk.layer_inspect',
            title: l10n.queueOptLayerInspect,
            value: _layerInspect,
            onChanged: (v) => setState(() => _layerInspect = v),
          ),
          _SwitchChoice(
            id: 'queue_bulk.timelapse',
            title: l10n.queueOptTimelapse,
            value: _timelapse,
            onChanged: (v) => setState(() => _timelapse = v),
          ),
          _SwitchChoice(
            id: 'queue_bulk.use_ams',
            title: l10n.queueOptUseAms,
            value: _useAms,
            onChanged: (v) => setState(() => _useAms = v),
          ),
          // An older server drops the field without a word, so the row is
          // offered only where it is known to be read — as in the form.
          if (ref.watch(queueOutcomeProvider).orFalse)
            _SwitchChoice(
              id: 'queue_bulk.confirm_outcome',
              title: l10n.queueOptConfirmOutcome,
              value: _confirmOutcome,
              onChanged: (v) => setState(() => _confirmOutcome = v),
            ),
          if (hasDualNozzle)
            _CalibrationChoice(
              id: 'queue_bulk.nozzle_offset_cali',
              title: l10n.queueOptNozzleOffset,
              value: _nozzleOffsetCali,
              triState: triState,
              onChanged: (v) => setState(() => _nozzleOffsetCali = v),
            ),
        ],
      ),
    );
  }
}

/// One setting of the bulk edit: its name and the values it can be set to. No value picked is "leave it": tapping the picked one again puts it
/// back, so there is no segment for "no change" that would have to fit a phone's
/// width in four languages.
class _Choice<T extends Object> extends StatelessWidget {
  const _Choice({
    required this.id,
    required this.title,
    required this.value,
    required this.segments,
    required this.onChanged,
    this.enabled = true,
  });

  final String id;
  final String title;
  final T? value;
  final List<DashSegment<T?>> segments;
  final ValueChanged<T?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: DashSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: t.titleSm),
          const SizedBox(height: DashSpace.sm),
          DashSegToggle<T?>(
            id: id,
            selected: value,
            segments: segments,
            onChanged: (picked) => onChanged(picked == value ? null : picked),
          ),
        ],
      ),
    );
    return enabled
        ? row
        : Opacity(opacity: 0.5, child: IgnorePointer(child: row));
  }
}

class _SwitchChoice extends StatelessWidget {
  const _SwitchChoice({
    required this.id,
    required this.title,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String id;
  final String title;
  final bool? value;
  final ValueChanged<bool?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _Choice<bool>(
      id: id,
      title: title,
      value: value,
      enabled: enabled,
      onChanged: onChanged,
      segments: [
        (value: true, label: l10n.commonOn, icon: null),
        (value: false, label: l10n.commonOff, icon: null),
      ],
    );
  }
}

class _CalibrationChoice extends StatelessWidget {
  const _CalibrationChoice({
    required this.id,
    required this.title,
    required this.value,
    required this.triState,
    required this.onChanged,
  });

  final String id;
  final String title;
  final CalibrationOption? value;

  /// Whether the server stores `auto`. Without it the row has no such segment: a
  /// position the server cannot keep does not exist there, and the single edit
  /// makes the same call ([QueueCalibrationRow]).
  final bool triState;
  final ValueChanged<CalibrationOption?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _Choice<CalibrationOption>(
      id: id,
      title: title,
      value: value,
      onChanged: onChanged,
      // The single edit's order, so the same setting reads the same on both.
      segments: [
        if (triState)
          (value: CalibrationOption.auto, label: l10n.commonAuto, icon: null),
        (value: CalibrationOption.on, label: l10n.commonOn, icon: null),
        (value: CalibrationOption.off, label: l10n.commonOff, icon: null),
      ],
    );
  }
}
