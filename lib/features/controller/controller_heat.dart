import 'dart:math' as math;

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
import 'scale_to_fit.dart';

/// The Heat tab: every heater with its target, and the fans
/// ([docs/single-printer-controller.md] §2). Reads its printer through
/// [controllerPrinterProvider] only, and shares the height between the two rows
/// like the Overview does, so it fills the screen and never scrolls.
class ControllerHeat extends ConsumerWidget {
  const ControllerHeat({super.key, required this.printerId});

  final int printerId;

  /// The most heaters whose ring and reading still fit side by side at their
  /// natural size; with more, the reading goes under the ring.
  static const _sideBySideMax = 3;

  // Heights of the design (188 / 100 dp), used as shares. With the readings
  // under their rings the heaters need nearly the whole body, so there the fans
  // take the height they need and the heaters what is left: a fan card cannot
  // shrink, and a banner above them (a refused session) must not push it over.
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
    final stacked = readings.length > _sideBySideMax;
    final fansRow = Row(
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
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (refused) ...[
          const ControllerForbidden(),
          const SizedBox(height: DashSpace.sm),
        ],
        if (readings.isNotEmpty)
          Expanded(
            flex: stacked ? 1 : _heatersShare,
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
                      stacked: stacked,
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
          stacked
              ? IntrinsicHeight(child: fansRow)
              : Expanded(flex: _fansShare, child: fansRow),
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
    required this.stacked,
    required this.refused,
  });

  final int printerId;
  final PrinterStatus status;
  final String? model;
  final TempReading reading;
  final bool dual;

  /// The reading under the ring instead of beside it.
  final bool stacked;
  final bool refused;

  /// How far one tap of − or + moves the target.
  static const _step = 5;
  static const _buttonSize = controllerButtonHeight;

  /// The ring the stroke is drawn for; a bigger ring draws a thicker one.
  static const _ringSize = 72.0;

  /// The least a ring is: below it the reading inside no longer fits.
  static const _ringFloor = 56.0;

  /// The reading in the ring is this share of the ring's size, so the two grow
  /// together: "250°" at 0.6 em a character fills about two thirds of it.
  static const _readingShare = 0.28;

  /// The least a touch target is, so the row is no smaller than the buttons in
  /// it already lay out at: a smaller button keeps a 48 dp area around itself.
  static const _stackedButtonSize = 48.0;

  static const _ringStroke = 7.0;

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
    // Four across leave a card 169 dp inside: the buttons give up 12 dp each
    // and the gaps between them, so the number has room to be read.
    final buttonSize = stacked ? _stackedButtonSize : _buttonSize;
    final gap = stacked ? DashSpace.xs : DashSpace.sm;
    final label = dual && reading.kind == TempKind.nozzle
        ? l10n.tempNozzleNumbered(reading.index == null ? '1' : '2')
        : reading.label(l10n);
    final color = reading.gaugeColor(t, target: shown.toDouble());
    // The ring takes the room the card has, and the reading in it grows with it.
    // The target is on the button, not here.
    final readingText = actual == null ? '—' : '${actual.round()}°';
    Widget ringOf(double side) => Stack(
      alignment: Alignment.center,
      children: [
        ExcludeSemantics(
          child: SizedBox.square(
            dimension: side,
            child: CircularProgressIndicator(
              value: actual == null
                  ? 0
                  : (actual / reading.gaugeMax(chamberMax)).clamp(0.0, 1.0),
              strokeWidth: _ringStroke * side / _ringSize,
              backgroundColor: t.gaugeTrack,
              valueColor: AlwaysStoppedAnimation(color),
              strokeCap: StrokeCap.round,
            ),
          ),
        ),
        Text(
          readingText,
          // Sized by the ring, so the system font does not outgrow it.
          textScaler: TextScaler.noScaling,
          style: t.monoDisplay.copyWith(
            fontSize: side * _readingShare,
            color: color,
          ),
        ),
      ],
    );
    return ControllerCard.single(
      title: label,
      trailing: dual && reading.kind == TempKind.nozzle
          ? _NozzleSwitch(
              compact: stacked,
              printerId: printerId,
              hardwareIndex: _hardwareIndex,
              status: status,
              pending: pending,
              refused: refused,
            )
          : reading.kind == TempKind.chamber && supportsAirduct(model)
          ? _AirductSwitch(
              compact: stacked,
              printing: status.isPrinting,
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
            child: LayoutBuilder(
              builder: (context, box) => Center(
                child: ringOf(
                  math.max(
                    _ringFloor,
                    math.min(box.maxWidth, box.maxHeight) - 2 * DashSpace.sm,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: stacked ? DashSpace.xs : DashSpace.sm),
          if (_editable)
            Row(
              children: [
                _StepButton(
                  size: buttonSize,
                  id: 'controller.heat_minus',
                  tooltip: '−$_step°',
                  icon: Icons.remove,
                  onPressed: canSet && shown > 0
                      ? () => _set(context, ref, (shown - _step).clamp(0, max))
                      : null,
                ),
                SizedBox(width: gap),
                Expanded(
                  child: _TargetField(
                    height: buttonSize,
                    compact: stacked,
                    text: shown > 0 ? '$shown' : l10n.ctrlOff,
                    enabled: canSet,
                    onSet: (typed) => _set(context, ref, typed.clamp(0, max)),
                  ),
                ),
                SizedBox(width: gap),
                _StepButton(
                  size: buttonSize,
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
              height: buttonSize,
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
    required this.size,
    required this.id,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final double size;
  final String id;
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return logTag(
      id,
      IconButton(
        // The size is the style's: an IconButton keeps its own 48 dp minimum
        // under a smaller `constraints`.
        style: controllerButtonStyle(t, minimumSize: Size.square(size)),
        tooltip: tooltip,
        constraints: BoxConstraints.tightFor(width: size, height: size),
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
    required this.compact,
    required this.printerId,
    required this.hardwareIndex,
    required this.status,
    required this.pending,
    required this.refused,
  });

  /// The icon alone, for a card too narrow to give the title and a label both.
  final bool compact;
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
      if (compact) {
        return Tooltip(
          message: l10n.ctrlNozzleActive,
          child: Icon(
            Icons.check_circle,
            size: DashSpace.xl,
            color: t.accentInk,
          ),
        );
      }
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
    final activate = locked || busy || refused
        ? null
        : () => _activate(context, ref);
    if (compact) {
      return logTag(
        'controller.activate_nozzle',
        IconButton(
          style: controllerButtonStyle(
            t,
            minimumSize: const Size.square(ControllerSection.headerHeight),
          ),
          tooltip: l10n.ctrlActivate,
          constraints: const BoxConstraints.tightFor(
            width: ControllerSection.headerHeight,
            height: ControllerSection.headerHeight,
          ),
          icon: Icon(locked ? Icons.lock_outline : Icons.swap_horiz),
          onPressed: activate,
        ),
      );
    }
    return logTag(
      'controller.activate_nozzle',
      FilledButton.icon(
        style: controllerButtonStyle(
          t,
          minimumSize: const Size(0, ControllerSection.headerHeight),
        ),
        icon: Icon(locked ? Icons.lock_outline : Icons.swap_horiz, size: 16),
        label: Text(l10n.ctrlActivate),
        onPressed: activate,
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
    required this.compact,
    required this.printing,
    required this.printerId,
    required this.heating,
    required this.busy,
    required this.refused,
  });

  /// The icon alone, for a card too narrow to give the title and a label both.
  final bool compact;

  /// Switching it under a print changes the temperature the print is made at,
  /// so it is asked about first.
  final bool printing;
  final int printerId;

  /// Null while the printer has not said which way the flap is.
  final bool? heating;
  final bool busy;
  final bool refused;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = heating;
    final flip = current == null || busy || refused
        ? null
        : () => _flip(context, ref, !current);
    final icon = current == true ? Icons.whatshot_outlined : Icons.ac_unit;
    final name = current == null
        ? l10n.ctrlAirduct
        : current
        ? l10n.ctrlAirductHeating
        : l10n.ctrlAirductCooling;
    if (compact) {
      return logTag(
        'controller.airduct',
        IconButton(
          style: controllerButtonStyle(
            DashTokens.of(context),
            minimumSize: const Size.square(ControllerSection.headerHeight),
          ),
          tooltip: name,
          constraints: const BoxConstraints.tightFor(
            width: ControllerSection.headerHeight,
            height: ControllerSection.headerHeight,
          ),
          icon: Icon(icon),
          onPressed: flip,
        ),
      );
    }
    return logTag(
      'controller.airduct',
      FilledButton.icon(
        style: controllerButtonStyle(
          DashTokens.of(context),
          minimumSize: const Size(0, ControllerSection.headerHeight),
        ),
        icon: Icon(icon, size: 16),
        label: Text(name),
        onPressed: flip,
      ),
    );
  }

  Future<void> _flip(BuildContext context, WidgetRef ref, bool heating) async {
    if (printing) {
      final l10n = AppLocalizations.of(context);
      final confirmed = await confirmDialog(
        context,
        id: 'controller.airduct_print',
        title: l10n.ctrlAirductPrintTitle,
        message: l10n.ctrlAirductPrintBody,
        confirmLabel: heating
            ? l10n.ctrlAirductHeating
            : l10n.ctrlAirductCooling,
        destructive: true,
      );
      if (!confirmed || !context.mounted) return;
    }
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
    required this.height,
    required this.compact,
    required this.text,
    required this.enabled,
    required this.onSet,
  });

  final double height;

  /// Less padding, for a button that has to share a narrow card with two
  /// steppers.
  final bool compact;

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

  /// The keypad lives in a route of its own, so it can outlast this field (the
  /// printer drops off the roster under it): the notifier it types into is
  /// then disposed when it closes, not before.
  bool _keypadOpen = false;

  static const _activeBorder = 2.0;

  @override
  void dispose() {
    if (!_keypadOpen) _draft.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    // The keypad goes to the half of the screen this button is not in, so it
    // never covers the number being typed.
    final box = context.findRenderObject()! as RenderBox;
    final centre = box.localToGlobal(box.size.center(Offset.zero)).dx;
    final onLeft = centre < MediaQuery.sizeOf(context).width / 2;
    // Read here, under the body: the route below is not.
    final scale = ControllerScale.of(context);
    setState(() => _editing = true);
    _keypadOpen = true;
    final confirmed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      pageBuilder: (_, _, _) => _Numpad(
        draft: _draft,
        scale: scale,
        alignment: onLeft ? Alignment.centerRight : Alignment.centerLeft,
      ),
    );
    _keypadOpen = false;
    final typed = _draft.value;
    if (!mounted) {
      _draft.dispose();
      return;
    }
    _draft.value = null;
    setState(() => _editing = false);
    if (confirmed != true || typed == null) return;
    widget.onSet(int.parse(typed));
  }

  @override
  Widget build(BuildContext context) => logTag(
    'controller.heat_target',
    FilledButton(
      style: controllerButtonStyle(
        DashTokens.of(context),
        minimumSize: Size.fromHeight(widget.height),
        padding: widget.compact
            ? const EdgeInsets.symmetric(horizontal: DashSpace.xs)
            : null,
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
          typed ?? widget.text,
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
  const _Numpad({
    required this.draft,
    required this.scale,
    required this.alignment,
  });

  final ValueNotifier<String?> draft;

  /// The factor the screen behind it is drawn at, so the keys grow with it.
  final double scale;
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
  static const _panelBorder = 1.0;

  /// The pad at its natural size, which is then scaled whole: three keys and
  /// two gaps across, and the handle, four rows of keys and three gaps down.
  static const _panelWidth =
      2 * (DashSpace.md + _panelBorder) + 3 * _keySize + 2 * DashSpace.sm;
  static const _panelHeight =
      2 * (DashSpace.md + _panelBorder) +
      _handleHeight +
      4 * _keySize +
      3 * DashSpace.sm;

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
      // The delta arrives in the scaled panel's own units; the move is applied
      // outside it, in screen pixels.
      onPanUpdate: (d) => setState(() => _moved += d.delta * widget.scale),
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
      FilledButton(
        style: controllerButtonStyle(t, padding: EdgeInsets.zero),
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
    final panel = Material(
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
                          onPressed: () => Navigator.of(context).pop(false),
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
                          onPressed: () => Navigator.of(context).pop(true),
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
    );
    final scale = widget.scale;
    return Align(
      alignment: widget.alignment,
      child: Transform.translate(
        offset: _moved,
        child: Padding(
          padding: EdgeInsets.all(DashSpace.lg * scale),
          // Laid out at its natural size, then drawn at the screen's scale like
          // everything behind it.
          child: SizedBox(
            width: _panelWidth * scale,
            height: _panelHeight * scale,
            child: FittedBox(
              child: SizedBox(
                width: _panelWidth,
                height: _panelHeight,
                child: panel,
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
