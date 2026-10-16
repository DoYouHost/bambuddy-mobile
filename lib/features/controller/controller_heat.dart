import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/action_outcome.dart';
import '../../core/models/printer_capabilities.dart';
import '../../core/models/printer_status.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../dashboard/controls_providers.dart';
import '../dashboard/temp_readings.dart';
import 'controller_controls.dart';
import 'controller_providers.dart';

/// The Heat tab: every heater with its target, and the fans
/// ([docs/single-printer-controller.md] §2). Reads its printer through
/// [controllerPrinterProvider] only, and shares the height between the two rows
/// like the Overview does, so it fills the screen and never scrolls.
class ControllerHeat extends ConsumerWidget {
  const ControllerHeat({super.key, required this.printerId});

  final int printerId;

  // Heights of the design (188 / 100 dp), used as shares.
  static const _heatersShare = 188;
  static const _fansShare = 100;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(controllerPrinterProvider(printerId)).item;
    final status = item?.status;
    if (item == null || status == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final refused = ref.watch(
      controlRefusedProvider(ControlPermission.control),
    );
    final readings = controllerReadings(status);
    // A second nozzle key is what says the printer has two heads.
    final dual = readings.any(
      (r) => r.kind == TempKind.nozzle && r.index != null,
    );
    final fans = _fansOf(status, l10n);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (refused) ...[
          const ControllerForbidden(),
          const SizedBox(height: DashSpace.sm),
        ],
        if (readings.isNotEmpty)
          Expanded(
            flex: _heatersShare,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, r) in readings.indexed) ...[
                  if (i > 0) const SizedBox(width: DashSpace.md),
                  Expanded(
                    child: _HeaterCard(
                      printerId: printerId,
                      status: status,
                      model: item.printer.model,
                      reading: r,
                      dual: dual,
                      refused: refused,
                    ),
                  ),
                ],
              ],
            ),
          ),
        if (readings.isNotEmpty && fans.isNotEmpty)
          const SizedBox(height: DashSpace.md),
        if (fans.isNotEmpty)
          Expanded(
            flex: _fansShare,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, fan) in fans.indexed) ...[
                  if (i > 0) const SizedBox(width: DashSpace.md),
                  Expanded(
                    child: _FanCard(
                      printerId: printerId,
                      fan: fan.key,
                      label: fan.label,
                      value: fan.value,
                      refused: refused,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// The fans the printer reports, in the order the card lists them. The server
  /// key is what the fan route takes: part = cooling, aux2 = left aux, aux = big
  /// fan 1, chamber = big fan 2.
  static List<({String key, String label, int value})> _fansOf(
    PrinterStatus status,
    AppLocalizations l10n,
  ) {
    final exhaust = status.usesExhaustFanLabel;
    return [
      if (status.coolingFanSpeed != null)
        (key: 'part', label: l10n.ctrlFanPart, value: status.coolingFanSpeed!),
      if (status.leftAuxFanSpeed != null)
        (key: 'aux2', label: l10n.ctrlFanAux2, value: status.leftAuxFanSpeed!),
      if (status.bigFan1Speed != null)
        (key: 'aux', label: l10n.ctrlFanAux, value: status.bigFan1Speed!),
      if (status.chamberFanAvailable)
        (
          key: 'chamber',
          label: exhaust ? l10n.ctrlFanExhaust : l10n.ctrlFanChamber,
          value: status.bigFan2Speed!,
        ),
    ];
  }
}

class _HeaterCard extends ConsumerWidget {
  const _HeaterCard({
    required this.printerId,
    required this.status,
    required this.model,
    required this.reading,
    required this.dual,
    required this.refused,
  });

  final int printerId;
  final PrinterStatus status;
  final String? model;
  final TempReading reading;
  final bool dual;
  final bool refused;

  /// How far one tap of − or + moves the target.
  static const _step = 5;
  static const _buttonSize = 44.0;
  static const _ringSize = 64.0;
  static const _ringStroke = 6.0;

  /// The server's hardware index of a nozzle: `nozzle_2` is the right head (0),
  /// the plain key the left one (1) on two heads, and 0 on one.
  int get _hardwareIndex =>
      reading.kind != TempKind.nozzle || reading.index != null
      ? 0
      : (dual ? 1 : 0);

  bool get _editable => switch (reading.kind) {
    TempKind.nozzle || TempKind.bed => true,
    TempKind.chamber => supportsChamberHeater(model),
    TempKind.unknown => false,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final pending = ref.watch(
      controlsProvider.select((s) => s.pendingFor(printerId)),
    );
    final chamberMax = ref.watch(chamberMaxTargetProvider);
    final max = reading.maxTarget(chamberMax);
    final target = pending.tempTarget(reading.raw) ?? reading.target?.round();
    final shown = target ?? 0;
    final actual = reading.actual;
    final busy = pending.isBusy(ControlAction.temp);
    final canSet = _editable && !refused && !busy;
    final label = dual && reading.kind == TempKind.nozzle
        ? l10n.tempNozzleNumbered(reading.index == null ? '1' : '2')
        : reading.label(l10n);
    final color = reading.gaugeColor(t, target: shown.toDouble());
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DashSpace.md,
        vertical: DashSpace.sm,
      ),
      decoration: t.cardBox,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _buttonSize,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: t.bodyBold.copyWith(color: t.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (dual && reading.kind == TempKind.nozzle)
                  _NozzleSwitch(
                    printerId: printerId,
                    hardwareIndex: _hardwareIndex,
                    status: status,
                    pending: pending,
                    refused: refused,
                  )
                else if (reading.kind == TempKind.chamber &&
                    supportsAirduct(model))
                  _AirductSwitch(
                    printerId: printerId,
                    heating: pending.airductHeating ?? reading.airductIsHeating,
                    busy: pending.isBusy(ControlAction.airduct),
                    refused: refused,
                  ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExcludeSemantics(
                      child: SizedBox(
                        width: _ringSize,
                        height: _ringSize,
                        child: CircularProgressIndicator(
                          value: actual == null
                              ? 0
                              : (actual / reading.gaugeMax(chamberMax)).clamp(
                                  0.0,
                                  1.0,
                                ),
                          strokeWidth: _ringStroke,
                          backgroundColor: t.gaugeTrack,
                          valueColor: AlwaysStoppedAnimation(color),
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                    ),
                    const SizedBox(width: DashSpace.md),
                    Text(
                      actual == null ? '—' : '${actual.round()}°',
                      style: t.monoValue.copyWith(
                        fontSize: _ringSize * 0.45,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_editable)
            Row(
              children: [
                _StepButton(
                  id: 'controller.heat_minus',
                  tooltip: '−$_step°',
                  icon: Icons.remove,
                  onPressed: canSet && shown > 0
                      ? () => _set(context, ref, (shown - _step).clamp(0, max))
                      : null,
                ),
                const SizedBox(width: DashSpace.sm),
                Expanded(
                  child: logTag(
                    'controller.heat_target',
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(_buttonSize),
                      ),
                      onPressed: canSet
                          ? () => _typeTarget(context, ref, shown, max, label)
                          : null,
                      child: Text(shown > 0 ? '$shown°' : l10n.ctrlOff),
                    ),
                  ),
                ),
                const SizedBox(width: DashSpace.sm),
                _StepButton(
                  id: 'controller.heat_plus',
                  tooltip: '+$_step°',
                  icon: Icons.add,
                  onPressed: canSet && shown < max
                      ? () => _set(context, ref, (shown + _step).clamp(0, max))
                      : null,
                ),
              ],
            )
          else
            SizedBox(
              height: _buttonSize,
              child: Row(
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: DashSpace.lg,
                    color: t.textTertiary,
                  ),
                  const SizedBox(width: DashSpace.sm),
                  Expanded(
                    child: Text(
                      l10n.controllerNoChamberHeater,
                      style: t.labelSoft,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _set(BuildContext context, WidgetRef ref, int next) async {
    final notifier = ref.read(controlsProvider.notifier);
    final result = switch (reading.kind) {
      TempKind.nozzle => await notifier.setNozzleTemp(
        printerId,
        reading.raw,
        next,
        nozzle: _hardwareIndex,
      ),
      TempKind.bed => await notifier.setBedTemp(printerId, next),
      TempKind.chamber => await notifier.setChamberTemp(printerId, next),
      TempKind.unknown => ActionOutcome.ok,
    };
    if (!context.mounted) return;
    final msg = result.messageFor(AppLocalizations.of(context));
    if (msg != null) {
      ScaffoldMessenger.of(context).snack(msg, clearQueue: true);
    }
  }

  Future<void> _typeTarget(
    BuildContext context,
    WidgetRef ref,
    int current,
    int max,
    String label,
  ) async {
    final typed = await showDialog<int>(
      context: context,
      builder: (_) => _TargetDialog(title: label, current: current, max: max),
    );
    if (typed == null || !context.mounted) return;
    await _set(context, ref, typed.clamp(0, max));
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.id,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String id;
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return logTag(
      id,
      IconButton.outlined(
        tooltip: tooltip,
        constraints: const BoxConstraints.tightFor(
          width: _HeaterCard._buttonSize,
          height: _HeaterCard._buttonSize,
        ),
        color: t.textPrimary,
        icon: Icon(icon),
        onPressed: onPressed,
      ),
    );
  }
}

/// Whether this nozzle is the active one, or a button to make it so. Locked
/// while printing, as the dashboard's nozzle sheet is: the printer picks its own
/// nozzle for the job.
class _NozzleSwitch extends ConsumerWidget {
  const _NozzleSwitch({
    required this.printerId,
    required this.hardwareIndex,
    required this.status,
    required this.pending,
    required this.refused,
  });

  final int printerId;
  final int hardwareIndex;
  final PrinterStatus status;
  final PendingControls pending;
  final bool refused;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    if ((status.activeExtruder ?? 0) == hardwareIndex) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: DashSpace.lg, color: t.accentInk),
          const SizedBox(width: DashSpace.xs),
          Text(
            l10n.ctrlNozzleActive,
            style: t.label.copyWith(color: t.accentInk),
          ),
        ],
      );
    }
    final locked = status.isPrinting;
    final busy = pending.isBusy(ControlAction.extruder);
    return logTag(
      'controller.activate_nozzle',
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, _HeaterCard._buttonSize),
        ),
        icon: Icon(locked ? Icons.lock_outline : Icons.swap_horiz, size: 16),
        label: Text(l10n.ctrlActivate),
        onPressed: locked || busy || refused
            ? null
            : () => _activate(context, ref),
      ),
    );
  }

  Future<void> _activate(BuildContext context, WidgetRef ref) async {
    final result = await ref
        .read(controlsProvider.notifier)
        .setExtruder(printerId, hardwareIndex);
    if (!context.mounted) return;
    final msg = result.messageFor(AppLocalizations.of(context));
    if (msg != null) {
      ScaffoldMessenger.of(context).snack(msg, clearQueue: true);
    }
  }
}

/// The chamber's airduct flap, as a button that shows its mode and flips it.
class _AirductSwitch extends ConsumerWidget {
  const _AirductSwitch({
    required this.printerId,
    required this.heating,
    required this.busy,
    required this.refused,
  });

  final int printerId;

  /// Null while the printer has not said which way the flap is.
  final bool? heating;
  final bool busy;
  final bool refused;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = heating;
    return logTag(
      'controller.airduct',
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, _HeaterCard._buttonSize),
        ),
        icon: Icon(
          current == true ? Icons.whatshot_outlined : Icons.ac_unit,
          size: 16,
        ),
        label: Text(
          current == null
              ? l10n.ctrlAirduct
              : current
              ? l10n.ctrlAirductHeating
              : l10n.ctrlAirductCooling,
        ),
        onPressed: current == null || busy || refused
            ? null
            : () => _flip(context, ref, !current),
      ),
    );
  }

  Future<void> _flip(BuildContext context, WidgetRef ref, bool heating) async {
    final result = await ref
        .read(controlsProvider.notifier)
        .setAirduct(printerId, heating: heating);
    if (!context.mounted) return;
    final msg = result.messageFor(AppLocalizations.of(context));
    if (msg != null) {
      ScaffoldMessenger.of(context).snack(msg, clearQueue: true);
    }
  }
}

/// A number to type in, for a target the − and + would take a long time to
/// reach. A form, not a question, so it is a dialog of its own and not
/// `confirmDialog`.
class _TargetDialog extends StatefulWidget {
  const _TargetDialog({
    required this.title,
    required this.current,
    required this.max,
  });

  final String title;
  final int current;
  final int max;

  @override
  State<_TargetDialog> createState() => _TargetDialogState();
}

class _TargetDialogState extends State<_TargetDialog> {
  late final _field = TextEditingController(
    text: widget.current > 0 ? '${widget.current}' : '',
  );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _set() {
    final value = int.tryParse(_field.text);
    if (value == null) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: logTag(
        'controller.heat_target_field',
        TextField(
          controller: _field,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(suffixText: '° / ${widget.max}°'),
          onSubmitted: (_) => _set(),
        ),
      ),
      actions: [
        logTag(
          'controller.heat_target_off',
          TextButton(
            onPressed: () => Navigator.of(context).pop(0),
            child: Text(l10n.ctrlOff),
          ),
        ),
        logTag(
          'controller.heat_target_cancel',
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
        ),
        logTag(
          'controller.heat_target_set',
          FilledButton(onPressed: _set, child: Text(l10n.ctrlSet)),
        ),
      ],
    );
  }
}

class _FanCard extends ConsumerStatefulWidget {
  const _FanCard({
    required this.printerId,
    required this.fan,
    required this.label,
    required this.value,
    required this.refused,
  });

  final int printerId;

  /// The id the fan route takes ('part', 'aux', 'aux2', 'chamber').
  final String fan;
  final String label;
  final int value;
  final bool refused;

  @override
  ConsumerState<_FanCard> createState() => _FanCardState();
}

class _FanCardState extends ConsumerState<_FanCard> {
  /// Where the thumb is while it is being dragged; null the rest of the time,
  /// when the sent value (or the printer's own) is what is shown.
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final pending = ref.watch(
      controlsProvider.select((s) => s.pendingFor(widget.printerId)),
    );
    final shown =
        _drag ?? (pending.fanSpeed(widget.fan) ?? widget.value).toDouble();
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DashSpace.md,
        vertical: DashSpace.sm,
      ),
      decoration: t.cardBox,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.air, size: DashSpace.lg, color: t.textSecondary),
              const SizedBox(width: DashSpace.sm),
              Expanded(
                child: Text(
                  widget.label,
                  style: t.bodyBold.copyWith(color: t.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                shown > 0
                    ? '${shown.round()}%'
                    : AppLocalizations.of(context).ctrlOff,
                style: t.monoValue.copyWith(
                  color: shown > 0 ? t.accentBlue : t.textTertiary,
                ),
              ),
            ],
          ),
          logTag(
            'controller.fan.${widget.fan}',
            Slider(
              value: shown,
              max: 100,
              divisions: 20,
              onChanged: widget.refused
                  ? null
                  : (v) => setState(() => _drag = v),
              onChangeEnd: widget.refused ? null : _send,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _send(double value) async {
    setState(() => _drag = null);
    final result = await ref
        .read(controlsProvider.notifier)
        .setFanSpeed(widget.printerId, widget.fan, value.round());
    if (!mounted) return;
    final msg = result.messageFor(AppLocalizations.of(context));
    if (msg != null) {
      ScaffoldMessenger.of(context).snack(msg, clearQueue: true);
    }
  }
}
