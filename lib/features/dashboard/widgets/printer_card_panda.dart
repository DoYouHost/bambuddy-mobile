part of 'printer_card.dart';

/// The heater's readings as a [TempReading], for the thermal colours every
/// other tile uses: a target only counts while the heater is switched on.
TempReading _pandaReading(PandaBreathState p) => TempReading(
  kind: TempKind.unknown,
  raw: 'panda_breath',
  actual: p.usable ? p.chamberTemp : null,
  // The server keeps the last target of a heater it lost; it is not today's.
  target: p.usable && p.workOn == true ? p.targetTemp : null,
);

/// The web's tile title (`PandaBreathTile`): the mode, then the drying time
/// left while a drying cycle runs. Null when the heater has said neither.
String? _pandaStatusLine(AppLocalizations l10n, PandaBreathState p) {
  final mode = switch (p.knownMode) {
    PandaBreathMode.auto => l10n.commonAuto,
    PandaBreathMode.alwaysOn => l10n.pandaBreathModeOn,
    PandaBreathMode.drying => l10n.pandaBreathModeDrying,
    null => p.mode,
  };
  final left = p.dryingRunning == true && p.dryingRemainingMin != null
      ? l10n.pandaBreathDryingLeft(p.dryingRemainingMin!.round())
      : null;
  final parts = [?mode, ?left];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Whether the heater can be driven from this session: it is reachable, and
/// the key may control printers (the route is `PRINTERS_CONTROL`).
bool _pandaControllable(WidgetRef ref, PandaBreathState p) =>
    p.usable && !ref.watch(controlRefusedProvider(ControlPermission.control));

void _openPandaBreathSheet(BuildContext context, int printerId) =>
    dashSurfaceSheet<void>(
      context,
      builder: (_) => _PandaBreathSheet(printerId: printerId),
    );

/// The BIQU Panda Breath bound to a connected printer, as one more tile of the
/// temperature grid (#1466). Read-only for a key that may not control, and for
/// a heater the server cannot reach.
class _PandaBreathTile extends ConsumerWidget {
  const _PandaBreathTile({required this.printerId, required this.panda});

  final int printerId;
  final PandaBreathState panda;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final reading = _pandaReading(panda);
    final face = _TempTileFace(
      label: l10n.pandaBreath,
      target: reading.target,
      accent: reading.gaugeColor(t),
      targetInk: reading.gaugeInk(t),
      actual: reading.actual,
      fraction: (reading.actual ?? 0) / pandaBreathMaxTargetC,
      glyph: panda.usable ? null : Icons.cloud_off,
      glyphColor: t.textTertiary,
      glyphLabel: l10n.pandaBreathOffline,
    );
    if (!_pandaControllable(ref, panda)) return face;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(DashRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: logTag(
        'printer.panda_breath',
        InkWell(
          onTap: () => _openPandaBreathSheet(context, printerId),
          child: face,
        ),
      ),
    );
  }
}

/// The same heater on the card of a printer that is offline, where the
/// temperature grid is gone: the heater keeps running without the printer, so
/// it stays reachable. The row opens the sheet, the switch turns it on or off.
class _PandaBreathRow extends ConsumerWidget {
  const _PandaBreathRow({required this.printerId, required this.panda});

  final int printerId;
  final PandaBreathState panda;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final controllable = _pandaControllable(ref, panda);
    final busy = ref.watch(
      controlsProvider.select(
        (s) => s.pendingFor(printerId).isBusy(ControlAction.pandaBreath),
      ),
    );
    final on = panda.workOn ?? false;
    final reading = _pandaReading(panda);
    final temps = [
      reading.actual == null ? '—' : '${reading.actual!.round()}°',
      if (reading.target case final target? when target > 0)
        '→ ${target.round()}°',
    ].join(' ');
    final subtitle = panda.usable
        ? [temps, ?_pandaStatusLine(l10n, panda)].join(' · ')
        : l10n.pandaBreathOffline;

    final body = Container(
      padding: const EdgeInsets.only(left: DashSpace.lg, right: DashSpace.xs),
      constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
      decoration: BoxDecoration(
        color: t.accentGreen.withValues(alpha: DashAlpha.faint),
        borderRadius: BorderRadius.circular(DashRadius.xl),
        border: Border.all(
          color: t.accentGreen.withValues(alpha: DashAlpha.soft),
        ),
      ),
      child: Row(
        children: [
          Icon(
            panda.usable ? Icons.heat_pump_outlined : Icons.cloud_off,
            size: DashIcon.md,
            color: t.accentGreenInk,
          ),
          const SizedBox(width: DashSpace.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: DashSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.pandaBreath,
                    style: t.titleSm.copyWith(color: t.accentGreenInk),
                  ),
                  Text(
                    subtitle,
                    style: t.label.copyWith(
                      color: t.textSecondary,
                      fontFamily: DashTokens.fontMono,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (controllable)
            _PandaPowerSwitch(printerId: printerId, on: on, busy: busy),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: DashSpace.md),
      child: !controllable
          ? body
          : Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(DashRadius.xl),
              clipBehavior: Clip.antiAlias,
              child: logTag(
                'printer.panda_breath',
                InkWell(
                  onTap: () => _openPandaBreathSheet(context, printerId),
                  child: body,
                ),
              ),
            ),
    );
  }
}

/// The row's own tap target: a second one inside the row, so the commonest
/// change needs no sheet.
class _PandaPowerSwitch extends ConsumerWidget {
  const _PandaPowerSwitch({
    required this.printerId,
    required this.on,
    required this.busy,
  });

  final int printerId;
  final bool on;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Semantics(
      toggled: on,
      label: l10n.pandaBreath,
      // While busy the switch is disabled, and this catcher swallows the tap:
      // without it the tap falls through to the row, which opens the sheet
      // under a request still in flight.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: busy ? () {} : null,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: busy
              ? null
              : () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final result = await ref
                      .read(controlsProvider.notifier)
                      .setPandaBreathOn(printerId, on: !on);
                  if (!context.mounted) return;
                  snackOutcome(
                    messenger,
                    result,
                    l10n,
                    fallback: l10n.pandaBreathSent,
                  );
                },
          child: SizedBox(
            width: kMinInteractiveDimension + DashSpace.md,
            height: kMinInteractiveDimension,
            child: Center(
              child: busy
                  ? const DashSpinner(size: DashSize.d20)
                  : PillSwitch(on: on, tokens: t),
            ),
          ),
        ).tagged('panda_breath.power'),
      ),
    );
  }
}

/// On/off, mode and target for the printer's Panda Breath, one command each
/// as the route takes them. Follows the web: a change that went through closes
/// the sheet with "Sent", and the heater's new state arrives with the next
/// status frame; a refused one keeps the sheet open under its message.
///
/// Reads the heater live, so a change made elsewhere shows while it is open.
class _PandaBreathSheet extends ConsumerStatefulWidget {
  const _PandaBreathSheet({required this.printerId});

  final int printerId;

  @override
  ConsumerState<_PandaBreathSheet> createState() => _PandaBreathSheetState();
}

class _PandaBreathSheetState extends ConsumerState<_PandaBreathSheet> {
  static const _presets = [35, 45, 55, pandaBreathMaxTargetC];

  /// What the user picked, null until they touch the editor.
  int? _target;

  /// The heater's own target, last seen: kept when the heater goes away.
  int? _heaterTarget;

  Future<void> _send(
    Future<ActionOutcome> Function(ControlsNotifier n, int id) command,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final l10n = AppLocalizations.of(context);
    final result = await command(
      ref.read(controlsProvider.notifier),
      widget.printerId,
    );
    if (!mounted) return;
    if (result.isOk) navigator.pop();
    snackOutcome(messenger, result, l10n, fallback: l10n.pandaBreathSent);
  }

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final panda = ref.watch(
      printerStatusesProvider.select((m) => m[widget.printerId]?.pandaBreath),
    );
    final busy = ref.watch(
      controlsProvider.select(
        (s) => s.pendingFor(widget.printerId).isBusy(ControlAction.pandaBreath),
      ),
    );
    // Unbound or unreachable while open: the controls would only be refused.
    final enabled = !busy && panda != null && panda.usable;
    // Follows the heater until the user edits it, and keeps the last value
    // when the heater goes away instead of dropping to 0.
    if (panda?.targetTemp case final live?) {
      _heaterTarget = live.round().clamp(0, pandaBreathMaxTargetC);
    }
    final target = _target ?? _heaterTarget ?? 0;
    final reading = panda == null ? null : _pandaReading(panda);
    final status = panda == null ? null : _pandaStatusLine(l10n, panda);
    final on = panda?.workOn ?? false;

    Widget section(String text) => Padding(
      padding: const EdgeInsets.only(top: DashSpace.lg, bottom: DashSpace.sm),
      child: Text(
        text.toUpperCase(),
        style: t.micro.copyWith(
          color: t.textSecondary,
          letterSpacing: DashTracking.label,
        ),
      ),
    );

    return FittedSheetSurface(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          DashSpace.gutter,
          DashSpace.lg,
          DashSpace.gutter,
          DashSpace.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: Text(l10n.pandaBreath, style: t.titleLg)),
                Text(
                  reading?.actual == null
                      ? '—'
                      : '${reading!.actual!.toStringAsFixed(0)}°',
                  style: t.monoTitle.copyWith(
                    fontWeight: DashWeight.regular,
                    color: t.textSecondary,
                  ),
                ),
              ],
            ),
            if (panda != null && !panda.usable)
              Text(
                l10n.pandaBreathOffline,
                style: t.body.copyWith(color: t.textSecondary),
              )
            else if (status != null)
              Text(status, style: t.body.copyWith(color: t.textSecondary)),
            const SizedBox(height: DashSpace.lg),
            _SheetButton(
              label: on ? l10n.pandaBreathTurnOff : l10n.pandaBreathTurnOn,
              id: 'panda_breath.power',
              onTap: enabled
                  ? () => _send((n, id) => n.setPandaBreathOn(id, on: !on))
                  : null,
            ),
            section(l10n.pandaBreathMode),
            Wrap(
              spacing: DashSpace.sm,
              runSpacing: DashSpace.sm,
              children: [
                for (final mode in PandaBreathMode.values)
                  _PresetChip(
                    label: switch (mode) {
                      PandaBreathMode.auto => l10n.commonAuto,
                      PandaBreathMode.alwaysOn => l10n.pandaBreathModeOn,
                      PandaBreathMode.drying => l10n.pandaBreathModeDrying,
                    },
                    id: 'panda_breath.mode',
                    mono: false,
                    selected: panda?.knownMode == mode,
                    onTap: enabled
                        ? () => _send((n, id) => n.setPandaBreathMode(id, mode))
                        : null,
                  ),
              ],
            ),
            section(l10n.pandaBreathTarget(pandaBreathMaxTargetC)),
            // Held still with the buttons: a number nobody can send would
            // only claim a change. IgnorePointer leaves the keyboard in.
            Opacity(
              opacity: enabled ? 1 : 0.35,
              child: IgnorePointer(
                ignoring: !enabled,
                child: ExcludeFocus(
                  excluding: !enabled,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Text(
                          '$target°',
                          style: TextStyle(
                            fontFamily: DashTokens.fontMono,
                            fontSize: DashFontSize.numeral,
                            fontWeight: DashWeight.bold,
                            color: t.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: DashSpace.sm),
                      Row(
                        children: [
                          _StepButton(
                            icon: Icons.remove,
                            id: 'panda_breath.step_down',
                            label: '−1°',
                            onTap: () => setState(
                              () => _target = (target - 1).clamp(
                                0,
                                pandaBreathMaxTargetC,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              value: target.toDouble(),
                              max: pandaBreathMaxTargetC.toDouble(),
                              onChanged: (v) =>
                                  setState(() => _target = v.round()),
                            ).tagged('panda_breath.slider'),
                          ),
                          _StepButton(
                            icon: Icons.add,
                            id: 'panda_breath.step_up',
                            label: '+1°',
                            onTap: () => setState(
                              () => _target = (target + 1).clamp(
                                0,
                                pandaBreathMaxTargetC,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: DashSpace.md),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: DashSpace.sm,
                        runSpacing: DashSpace.sm,
                        children: [
                          for (final p in _presets)
                            _PresetChip(
                              label: '$p°',
                              id: 'panda_breath.preset',
                              selected: target == p,
                              onTap: () => setState(() => _target = p),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: DashSpace.xl),
            _SheetButton(
              label: l10n.ctrlSet,
              id: 'panda_breath.set',
              filled: true,
              busy: busy,
              onTap: enabled
                  ? () => _send((n, id) => n.setPandaBreathTarget(id, target))
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
