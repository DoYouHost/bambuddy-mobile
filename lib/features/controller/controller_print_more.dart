import 'dart:math' as math;

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:dash_kit/dash_kit.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/cost_center.dart';
import '../../core/models/printer.dart';
import '../../core/settings/print_options.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/dash_async.dart';
import '../queue/job_cost_providers.dart';
import '../queue/queue_cost_center_state.dart';
import '../queue/queue_edit_screen.dart';
import '../queue/queue_providers.dart';
import 'controller_print_parts.dart';
import 'scale_to_fit.dart';

/// What the "More options" dialog edits besides [PrintOptions]: the request's
/// other switches and the cost center. Immutable, so the print screen and the
/// dialog can each hold the value they last saw.
class ControllerJobExtras {
  const ControllerJobExtras({
    this.confirmOutcome,
    this.preheatOverride = 'inherit',
    this.chamberTarget,
    this.requirePreviousSuccess = false,
    this.autoOffAfter = false,
    this.requireManualStart = false,
    this.costCenterId,
  });

  /// Null until the user touches the switch: the server's default applies.
  final bool? confirmOutcome;

  /// `inherit`, `on` or `off`, as the queue form sends it.
  final String preheatOverride;

  /// °C; null keeps the filament's own. Meaningless while preheat is off.
  final int? chamberTarget;
  final bool requirePreviousSuccess;
  final bool autoOffAfter;
  final bool requireManualStart;

  /// Null until the user picks one: the web's default centre applies.
  final int? costCenterId;

  ControllerJobExtras copyWith({
    bool? confirmOutcome,
    String? preheatOverride,
    ValueGetter<int?>? chamberTarget,
    bool? requirePreviousSuccess,
    bool? autoOffAfter,
    bool? requireManualStart,
    int? costCenterId,
  }) => ControllerJobExtras(
    confirmOutcome: confirmOutcome ?? this.confirmOutcome,
    preheatOverride: preheatOverride ?? this.preheatOverride,
    chamberTarget: chamberTarget == null ? this.chamberTarget : chamberTarget(),
    requirePreviousSuccess:
        requirePreviousSuccess ?? this.requirePreviousSuccess,
    autoOffAfter: autoOffAfter ?? this.autoOffAfter,
    requireManualStart: requireManualStart ?? this.requireManualStart,
    costCenterId: costCenterId ?? this.costCenterId,
  );
}

/// The chamber target moves in this many degrees a tap: a keyboard would not
/// fit a screen the controller has already given to its cards.
const chamberStep = 5;

/// Opens the dialog with the options the print screen has no room for. Every
/// change reaches the screen at once through [onOptions] and [onExtras], so
/// closing the dialog by any route loses nothing.
Future<void> showControllerMoreOptions(
  BuildContext context, {
  required double scale,
  required Printer printer,
  required PrintOptions options,
  required ControllerJobExtras extras,
  required QueueScheduleType when,
  required int copies,
  required JobCostKey? costKey,
  required bool confirmOutcomeSticky,
  required ValueChanged<PrintOptions> onOptions,
  required ValueChanged<ControllerJobExtras> onExtras,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _MoreDialog(
      scale: scale,
      printer: printer,
      options: options,
      extras: extras,
      when: when,
      copies: copies,
      costKey: costKey,
      confirmOutcomeSticky: confirmOutcomeSticky,
      onOptions: onOptions,
      onExtras: onExtras,
    ),
  );
}

class _MoreDialog extends ConsumerStatefulWidget {
  const _MoreDialog({
    required this.scale,
    required this.printer,
    required this.options,
    required this.extras,
    required this.when,
    required this.copies,
    required this.costKey,
    required this.confirmOutcomeSticky,
    required this.onOptions,
    required this.onExtras,
  });

  final double scale;
  final Printer printer;
  final PrintOptions options;
  final ControllerJobExtras extras;
  final QueueScheduleType when;
  final int copies;
  final JobCostKey? costKey;

  /// A reprint of an archive that already asks: the server keeps asking
  /// whatever the switch says, so it shows on and cannot be turned off, as on
  /// the phone's print form.
  final bool confirmOutcomeSticky;
  final ValueChanged<PrintOptions> onOptions;
  final ValueChanged<ControllerJobExtras> onExtras;

  @override
  ConsumerState<_MoreDialog> createState() => _MoreDialogState();
}

class _MoreDialogState extends ConsumerState<_MoreDialog> {
  /// The size the rows are laid out for, before the whole is scaled to the
  /// room the screen gives it.
  static const _width = 560.0;
  static const _height = 300.0;

  late PrintOptions _options = widget.options;
  late ControllerJobExtras _extras = widget.extras;

  void _setOptions(PrintOptions next) {
    setState(() => _options = next);
    widget.onOptions(next);
  }

  void _setExtras(ControllerJobExtras next) {
    setState(() => _extras = next);
    widget.onExtras(next);
  }

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(DashSpace.md),
      child: LayoutBuilder(
        builder: (context, box) => SizedBox(
          width: math.min(_width * widget.scale, box.maxWidth),
          height: math.min(_height * widget.scale, box.maxHeight),
          child: ScaleToFit(
            minSize: const Size(_width, _height),
            child: Padding(
              padding: const EdgeInsets.all(DashSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.controllerPrintMoreTitle,
                          style: t.titleMd,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      logTag(
                        'controller.print.more.close',
                        IconButton(
                          tooltip: MaterialLocalizations.of(
                            context,
                          ).closeButtonTooltip,
                          color: t.textPrimary,
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: DashSpace.sm),
                  Expanded(child: _rows(l10n, t)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _rows(AppLocalizations l10n, DashTokens t) {
    final triState = ref.watch(triStateCalibrationProvider).orFalse;
    final held = ref.watch(awaitingReviewProvider);
    final snippets = ref.watch(gcodeSnippetModelsProvider).valueOrNull ?? {};
    final model = widget.printer.model;
    final dualNozzle = queueDualNozzleModels.contains(model?.toUpperCase());
    final chamberMax = ref.watch(chamberMaxTargetProvider);
    final target = _extras.chamberTarget;
    String onOff(bool v) => v ? l10n.commonOn : l10n.commonOff;

    PrintOptionRow flag(
      String id,
      String label,
      bool value,
      ValueChanged<bool> set,
    ) => PrintOptionRow(
      id: 'controller.print.more.$id',
      label: label,
      value: onOff(value),
      on: value,
      onTap: () => set(!value),
    );

    final children = <Widget>[
      ..._costCenterRows(l10n, t),
      flag(
        'vibration',
        l10n.queueOptVibrationCali,
        _options.vibrationCali,
        (v) => _setOptions(_options.copyWith(vibrationCali: v)),
      ),
      flag(
        'layer_inspect',
        l10n.queueOptLayerInspect,
        _options.layerInspect,
        (v) => _setOptions(_options.copyWith(layerInspect: v)),
      ),
      if (ref.watch(queueOutcomeProvider).orFalse) _confirmOutcomeRow(l10n),
      if (dualNozzle)
        PrintOptionRow(
          id: 'controller.print.more.nozzle_offset',
          label: l10n.queueOptNozzleOffset,
          value: calibrationLabel(l10n, _options.nozzleOffsetCali, triState),
          onTap: () => _setOptions(
            _options.copyWith(
              nozzleOffsetCali: nextCalibration(
                _options.nozzleOffsetCali,
                triState,
              ),
            ),
          ),
        ),
      if (snippets.isNotEmpty) ...[
        flag(
          'gcode_injection',
          l10n.queueEditGcodeInjection,
          _options.gcodeInjection,
          (v) => _setOptions(_options.copyWith(gcodeInjection: v)),
        ),
        // The scheduler prints a model with no snippet exactly as sliced and
        // says so only in its own log.
        if (_options.gcodeInjection && !snippets.contains(model))
          Text(
            l10n.queueEditGcodeInjectionNoSnippet(model ?? ''),
            style: t.labelSoft.copyWith(color: t.warningInk),
          ),
      ],
      Text(l10n.queueEditPreheat, style: t.labelSoft),
      DashSegToggle<String>(
        id: 'controller.print.more.preheat',
        selected: _extras.preheatOverride,
        segments: [
          (value: 'inherit', label: l10n.queuePreheatInherit, icon: null),
          (value: 'on', label: l10n.commonOn, icon: null),
          (value: 'off', label: l10n.commonOff, icon: null),
        ],
        onChanged: (v) => _setExtras(_extras.copyWith(preheatOverride: v)),
      ),
      if (_extras.preheatOverride != 'off')
        PrintStepper(
          id: 'controller.print.more.chamber',
          label: l10n.controllerPrintChamber,
          value: target == null ? '—' : '$target°',
          // Back to the filament's own below the first step.
          onLess: target == null
              ? null
              : () => _setExtras(
                  _extras.copyWith(
                    chamberTarget: () =>
                        target <= chamberStep ? null : target - chamberStep,
                  ),
                ),
          onMore: (target ?? 0) >= chamberMax
              ? null
              : () => _setExtras(
                  _extras.copyWith(
                    chamberTarget: () =>
                        math.min((target ?? 0) + chamberStep, chamberMax),
                  ),
                ),
        ),
      flag(
        'require_previous',
        l10n.queueEditRequirePrevious,
        _extras.requirePreviousSuccess,
        (v) => _setExtras(_extras.copyWith(requirePreviousSuccess: v)),
      ),
      flag(
        'power_off',
        l10n.queueEditPowerOff,
        _extras.autoOffAfter,
        (v) => _setExtras(_extras.copyWith(autoOffAfter: v)),
      ),
      // A user held for review always waits, so the switch would only mislead.
      if (widget.when == QueueScheduleType.queue && !held)
        flag(
          'manual_start',
          l10n.queueEditRequireManualStart,
          _extras.requireManualStart,
          (v) => _setExtras(_extras.copyWith(requireManualStart: v)),
        ),
    ];
    return ListView.separated(
      itemCount: children.length,
      separatorBuilder: (_, _) => const SizedBox(height: DashSpace.xs),
      itemBuilder: (_, i) => children[i],
    );
  }

  /// Hidden where the server would drop the flag; held while a new job's default
  /// is on its way, since a switch that moves by itself after the first look is
  /// one tapped wrong.
  Widget _confirmOutcomeRow(AppLocalizations l10n) {
    final server = ref.watch(defaultConfirmOutcomeProvider);
    final sticky = widget.confirmOutcomeSticky;
    final value =
        sticky || (_extras.confirmOutcome ?? server.valueOrNull ?? false);
    final unanswered = _extras.confirmOutcome == null && server.isUnanswered;
    return PrintOptionRow(
      id: 'controller.print.more.confirm_outcome',
      label: l10n.queueOptConfirmOutcome,
      value: value ? l10n.commonOn : l10n.commonOff,
      on: value,
      onTap: unanswered || sticky
          ? null
          : () => _setExtras(_extras.copyWith(confirmOutcome: !value)),
    );
  }

  /// The cost centres the job can be booked to, while billing is on: the web's
  /// select (`PrintModal/CostCenterSelect.tsx`), one row each, since a menu
  /// would open outside the scaled dialog.
  List<Widget> _costCenterRows(AppLocalizations l10n, DashTokens t) {
    final state = costCenterStateOf(ref.watch);
    switch (state.step) {
      case CostCenterStep.loading:
        return const [LinearProgressIndicator()];
      case CostCenterStep.failed:
        return [
          Row(
            children: [
              Expanded(
                child: Text(l10n.queueCostCenterLoadFailed, style: t.bodySoft),
              ),
              logTag(
                'controller.print.more.cost_center_retry',
                TextButton(
                  onPressed: () => ref.invalidate(printableCostCentersProvider),
                  child: Text(l10n.retry),
                ),
              ),
            ],
          ),
        ];
      case CostCenterStep.pick:
        final selected = selectedCostCenter(
          state.centers,
          _extras.costCenterId,
        );
        final cost = widget.costKey == null
            ? null
            : ref.watch(jobCostProvider(widget.costKey!)).valueOrNull;
        return [
          Text(l10n.queueCostCenterTitle, style: t.labelSoft),
          for (final c in state.centers)
            PrintOptionRow(
              // A centre's name is the user's own words, so every row is one id.
              id: 'controller.print.more.cost_center',
              label: c.isPrivate
                  ? l10n.queueCostCenterPersonal(c.name)
                  : c.name,
              value: c.id == selected?.id ? '✓' : '',
              on: c.id == selected?.id,
              onTap: () => _setExtras(_extras.copyWith(costCenterId: c.id)),
            ),
          if (selected?.budget == CostCenterBudget.none)
            Text(l10n.queueCostCenterUnlimited, style: t.labelSoft),
          if (jobExceedsBudget(cost, selected, widget.copies))
            Text(
              l10n.queueInsufficientBudget,
              style: t.labelSoft.copyWith(color: t.dangerInk),
            ),
        ];
      case CostCenterStep.unknown ||
          CostCenterStep.off ||
          CostCenterStep.none ||
          CostCenterStep.refused:
        return const [];
    }
  }
}
