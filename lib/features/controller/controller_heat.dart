import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';
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
  static const _buttonSize = controllerButtonHeight;
  static const _ringSize = 72.0;
  static const _ringStroke = 7.0;
  static const _readingFont = 36.0;

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
    final state = _editable
        ? reading.heatState(target: shown.toDouble())
        : null;
    return ControllerCard.single(
      title: label,
      trailing: dual && reading.kind == TempKind.nozzle
          ? _NozzleSwitch(
              printerId: printerId,
              hardwareIndex: _hardwareIndex,
              status: status,
              pending: pending,
              refused: refused,
            )
          : reading.kind == TempKind.chamber && supportsAirduct(model)
          ? _AirductSwitch(
              printerId: printerId,
              heating: pending.airductHeating ?? reading.airductIsHeating,
              busy: pending.isBusy(ControlAction.airduct),
              refused: refused,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            // Shrinks on a narrow card (four heaters on two nozzles) or a short
            // one, never grows on its own: its size is the body's scale.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(
                    child: SizedBox.square(
                      dimension: _ringSize,
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
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        actual == null ? '—' : '${actual.round()}°',
                        style: t.monoDisplay.copyWith(
                          fontSize: _readingFont,
                          color: color,
                        ),
                      ),
                      if (state != null && state != HeatState.off)
                        ControllerHeatPill(state: state),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: DashSpace.sm),
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
                  child: _TargetField(
                    text: shown > 0
                        ? l10n.controllerTarget('$shown°')
                        : l10n.ctrlOff,
                    enabled: canSet,
                    onSet: (typed) => _set(context, ref, typed.clamp(0, max)),
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
                      style: t.bodySoft,
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
          minimumSize: const Size(0, ControllerSection.headerHeight),
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
          minimumSize: const Size(0, ControllerSection.headerHeight),
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

/// The target button of a heater: a tap opens a keypad beside it and what is
/// typed shows up here as it is typed. A keypad of its own, because the system
/// keyboard resizes a screen that has no room to spare.
class _TargetField extends StatefulWidget {
  const _TargetField({
    required this.text,
    required this.enabled,
    required this.onSet,
  });

  /// What the button says when nothing is being typed.
  final String text;
  final bool enabled;
  final ValueChanged<int> onSet;

  @override
  State<_TargetField> createState() => _TargetFieldState();
}

class _TargetFieldState extends State<_TargetField> {
  /// The digits typed so far; null until the first one, so what the button
  /// said stays up and the first digit replaces it.
  final _draft = ValueNotifier<String?>(null);

  /// The keypad is open and this is the number it types into.
  bool _editing = false;

  static const _activeBorder = 2.0;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    // The keypad goes to the half of the screen this button is not in, so it
    // never covers the number being typed.
    final box = context.findRenderObject()! as RenderBox;
    final centre = box.localToGlobal(box.size.center(Offset.zero)).dx;
    final onLeft = centre < MediaQuery.sizeOf(context).width / 2;
    setState(() => _editing = true);
    final confirmed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      pageBuilder: (_, _, _) => _Numpad(
        draft: _draft,
        alignment: onLeft ? Alignment.centerRight : Alignment.centerLeft,
      ),
    );
    final typed = _draft.value;
    _draft.value = null;
    if (mounted) setState(() => _editing = false);
    if (confirmed != true || typed == null || !mounted) return;
    widget.onSet(int.parse(typed));
  }

  @override
  Widget build(BuildContext context) => logTag(
    'controller.heat_target',
    OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(controllerButtonHeight),
        side: _editing
            ? BorderSide(
                color: DashTokens.of(context).accent,
                width: _activeBorder,
              )
            : null,
      ),
      onPressed: widget.enabled ? _open : null,
      child: ValueListenableBuilder<String?>(
        valueListenable: _draft,
        builder: (_, typed, _) => Text(
          typed == null ? widget.text : '$typed°',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ),
  );
}

/// Digits only, no title and no labels: 1–9 in three rows, ✕ 0 ✓ under them,
/// and a handle above them to drag the whole pad out of the way.
/// A 0 on its own is a target of 0, which is "off".
class _Numpad extends StatefulWidget {
  const _Numpad({required this.draft, required this.alignment});

  final ValueNotifier<String?> draft;
  final Alignment alignment;

  @override
  State<_Numpad> createState() => _NumpadState();
}

class _NumpadState extends State<_Numpad> {
  static const _keySize = 56.0;
  static const _maxDigits = 3;
  static const _handleHeight = 24.0;
  static const _gripSize = Size(40, 4);
  static const _panelRadius = 22.0;

  Offset _moved = Offset.zero;

  void _type(int digit) {
    // A 0 is not the start of a longer number.
    final draft = widget.draft;
    final base = draft.value == '0' ? '' : draft.value ?? '';
    if (base.length < _maxDigits) draft.value = '$base$digit';
  }

  Widget _handle(DashTokens t) => logTag(
    'controller.heat_target_handle',
    GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) => setState(() => _moved += d.delta),
      child: SizedBox(
        height: _handleHeight,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: t.textTertiary,
              borderRadius: BorderRadius.circular(_gripSize.height),
            ),
            child: SizedBox.fromSize(size: _gripSize),
          ),
        ),
      ),
    ),
  );

  Widget _digit(DashTokens t, int digit) => SizedBox.square(
    dimension: _keySize,
    child: logTag(
      'controller.heat_target_key.$digit',
      FilledButton.tonal(
        style: FilledButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: t.subCard,
          foregroundColor: t.textPrimary,
          side: BorderSide(color: t.subCardBorder),
        ),
        onPressed: () => _type(digit),
        child: Text('$digit'),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    const rows = [
      [1, 2, 3],
      [4, 5, 6],
      [7, 8, 9],
    ];
    return Align(
      alignment: widget.alignment,
      child: Transform.translate(
        offset: _moved,
        child: Padding(
          padding: const EdgeInsets.all(DashSpace.lg),
          child: Material(
            type: MaterialType.transparency,
            child: DecoratedBox(
              // Solid, unlike the translucent cards: it floats over them.
              decoration: BoxDecoration(
                color: t.overlaySurface,
                border: Border.all(color: t.overlayBorder),
                borderRadius: BorderRadius.circular(_panelRadius),
              ),
              child: Padding(
                padding: const EdgeInsets.all(DashSpace.md),
                // As wide as the keys, not the handle's full-width strip.
                child: IntrinsicWidth(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _handle(t),
                      for (final row in rows) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final (i, digit) in row.indexed) ...[
                              if (i > 0) const SizedBox(width: DashSpace.sm),
                              _digit(t, digit),
                            ],
                          ],
                        ),
                        const SizedBox(height: DashSpace.sm),
                      ],
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox.square(
                            dimension: _keySize,
                            child: logTag(
                              'controller.heat_target_cancel',
                              IconButton.filled(
                                style: IconButton.styleFrom(
                                  backgroundColor: t.dangerInk,
                                  foregroundColor: t.onDanger,
                                ),
                                tooltip: l10n.cancel,
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                icon: const Icon(Icons.close),
                              ),
                            ),
                          ),
                          const SizedBox(width: DashSpace.sm),
                          _digit(t, 0),
                          const SizedBox(width: DashSpace.sm),
                          SizedBox.square(
                            dimension: _keySize,
                            child: logTag(
                              'controller.heat_target_set',
                              IconButton.filled(
                                style: IconButton.styleFrom(
                                  backgroundColor: t.accent,
                                  foregroundColor: t.onAccent,
                                ),
                                tooltip: l10n.ctrlSet,
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                icon: const Icon(Icons.check),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
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
    // The server's number is passed on unchecked, and a Slider asserts on a
    // value outside its range — the card's fan sheet clamps the same way.
    final shown = (_drag ?? (pending.fanSpeed(widget.fan) ?? widget.value))
        .toDouble()
        .clamp(0.0, 100.0);
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
              Icon(Icons.air, size: DashSpace.xl, color: t.textSecondary),
              const SizedBox(width: DashSpace.sm),
              Expanded(
                child: Text(
                  widget.label,
                  style: t.titleMd,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                shown > 0
                    ? '${shown.round()}%'
                    : AppLocalizations.of(context).ctrlOff,
                style: t.monoHeadline.copyWith(
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
