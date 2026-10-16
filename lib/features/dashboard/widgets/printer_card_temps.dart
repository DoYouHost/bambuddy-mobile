part of 'printer_card.dart';

/// Temperature gauge tile (design "gauge card"): a circular gauge in the
/// top-right, sensor label, and the current value in large mono type. The ring
/// center shows the setpoint ("-" when unset). Chamber prefixes the value with
/// its air-duct glyph (flame = heating/orange, snowflake = cooling/blue).
///
/// Editable sensors (nozzle/bed always; chamber only when the model has an
/// active heater) are tappable and open [_TempControlSheet]. Setpoint and
/// airduct glyph overlay the optimistic override from [controlsProvider] so a
/// just-sent change shows instantly. Read-only when control is forbidden.
///
/// Sensors the server keeps history for also carry a chart glyph next to the
/// label, opening [showHeaterHistorySheet] — the tile's own tap is taken by the
/// setpoint sheet, and history stays reachable on read-only tiles too.
class _GaugeTile extends ConsumerWidget {
  const _GaugeTile({
    required this.reading,
    required this.printerId,
    required this.model,
    required this.nozzleIndex,
    required this.dualNozzle,
    required this.activeExtruder,
    required this.printing,
    required this.historyKinds,
  });

  final TempReading reading;
  final int printerId;
  final String? model;

  /// Every sensor on this printer the history sheet can switch between; empty
  /// when none of them is recorded (then no tile shows the chart glyph).
  final List<HeaterKindOption> historyKinds;

  /// Hardware nozzle index (0=right/default, 1=left) for nozzle tiles; null for
  /// non-nozzle sensors.
  final int? nozzleIndex;

  /// True on dual-head printers — enables the nozzle switch in the sheet.
  final bool dualNozzle;

  /// Currently active extruder (0/1); drives the switch state in the sheet.
  final int? activeExtruder;

  /// Whether a print is active — the nozzle switch is disabled mid-print.
  final bool printing;

  bool get _isEditable => switch (reading.kind) {
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
    final forbidden = ref.watch(
      controlRefusedProvider(ControlPermission.control),
    );
    // Only the chamber gauge scales against the ceiling, so watching it on every
    // tile rebuilds nozzle and bed for nothing when the probe answers. 60 until
    // the server's version is known — see [chamberMaxTargetProvider].
    final chamberMax = reading.kind != TempKind.chamber
        ? 60
        : ref.watch(chamberMaxTargetProvider);

    final actual = reading.actual;
    // Optimistic overlay: setpoint and airduct glyph reflect a just-sent command
    // until real status catches up (see ControlsNotifier.optimisticHold).
    final target = reading.kind == TempKind.unknown
        ? reading.target
        : (pending.tempTarget(reading.raw)?.toDouble() ?? reading.target);
    final hasTarget = target != null && target > 0;
    // One thermal-state color drives the whole tile — ring, setpoint and the
    // chamber's air-duct glyph all use [accent] (orange = heating/holding,
    // blue = cooling/idle). The ring center shows the setpoint ("-" when unset).
    final accent = reading.gaugeColor(t, target: target);
    final airduct = reading.kind == TempKind.chamber
        ? (pending.airductHeating ?? reading.airductIsHeating)
        : reading.airductIsHeating;
    final airductIcon = airduct == null
        ? null
        : (airduct ? Icons.local_fire_department : Icons.ac_unit);

    final editable = _isEditable && !forbidden;
    // Shown until the server says otherwise (see the latch): a glyph that
    // appeared once the version landed shifted the label beside it.
    final hasHistory =
        historyKinds.any((k) => k.kind == reading.raw) &&
        ref.watch(heaterHistorySupportedProvider).orFalse;

    // The sensor label, preceded by the chart glyph when this sensor is
    // recorded. The whole strip is the history button, not just the glyph: a
    // 14 px icon is a 22 px target sitting inside the tile's own InkWell, so a
    // near-miss opened the setpoint sheet instead of the chart. Taking the
    // label's full width and the 8 px gap below it costs no tile height — the
    // strip ends up exactly as tall as a label with no glyph at all.
    Widget labelStrip = Row(
      children: [
        if (hasHistory) ...[
          Icon(Icons.show_chart, size: 14, color: t.textSecondary),
          const SizedBox(width: DashSpace.xs),
        ],
        Flexible(
          child: Text(
            reading.label(l10n).toUpperCase(),
            style: t.micro.copyWith(color: t.textSecondary, letterSpacing: 0.3),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    if (hasHistory) {
      labelStrip = _HistoryButton(
        logId: reading.historyLogId,
        onTap: () => showHeaterHistorySheet(
          context,
          printerId: printerId,
          kinds: historyKinds,
          initialKind: reading.raw,
        ),
        child: labelStrip,
      );
    }

    final tile = Container(
      padding: const EdgeInsets.all(DashSpace.md),
      decoration: BoxDecoration(
        color: t.subCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.subCardBorder),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            right: 0,
            child: TempGauge(
              fraction: actual == null
                  ? 0
                  : actual / reading.gaugeMax(chamberMax),
              color: accent,
              trackColor: t.gaugeTrack,
              centerText: hasTarget ? '${target.toStringAsFixed(0)}°' : '-',
              centerColor: hasTarget ? accent : t.textTertiary,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Reserve the gauge's corner: pad the label so it never collides.
              Padding(
                padding: const EdgeInsets.only(
                  right: TempGauge.defaultSize + DashSpace.xs,
                ),
                child: labelStrip,
              ),
              // With the glyph the gap belongs to the button (see [labelStrip]).
              if (!hasHistory) const SizedBox(height: DashSpace.sm),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (airductIcon != null) ...[
                    Icon(airductIcon, size: 20, color: accent),
                    const SizedBox(width: DashSpace.xs),
                  ],
                  Text(
                    actual == null ? '—' : '${actual.toStringAsFixed(0)}°',
                    style: t.monoDisplay.copyWith(height: 1.0),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    if (!editable) return tile;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: logTag(
        // Per sensor, under the same name the WebSocket frame uses for it
        // (`nozzle_2`, `bed`, …): one shared tag could not say which tile was
        // tapped, and on a dual-head printer that is the whole question.
        reading.logId,
        InkWell(
          onTap: () => _openSheet(context, target?.round() ?? 0),
          child: tile,
        ),
      ),
    );
  }

  void _openSheet(BuildContext context, int initialTarget) {
    dashSurfaceSheet<void>(
      context,
      builder: (_) => _TempControlSheet(
        printerId: printerId,
        reading: reading,
        model: model,
        nozzleIndex: nozzleIndex ?? 0,
        initialTarget: initialTarget,
        dualNozzle: dualNozzle,
        activeExtruder: activeExtruder,
        printing: printing,
      ),
    );
  }
}

/// The tile's label strip turned into a button that opens the heater history
/// sheet. Brings its own [Material] because read-only tiles are not wrapped in
/// one, and the ink would have nowhere to draw. The 8 px of air above the
/// temperature reading is the button's own padding: it is hit area the tile
/// cannot spare in height, since the big number owns the rest of it.
class _HistoryButton extends StatelessWidget {
  const _HistoryButton({
    required this.logId,
    required this.onTap,
    required this.child,
  });

  final String logId;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return logTag(
      logId,
      Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Tooltip(
            message: AppLocalizations.of(context).heaterHistoryOpen,
            child: Padding(
              padding: const EdgeInsets.only(bottom: DashSpace.sm),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Sensor keys the server records history for — bambuddy's own `VALID_KINDS`
/// (`printer_sensor_history.py`). A key outside this set gets no chart glyph:
/// the endpoint would answer with an empty series for it.
const _heaterHistoryKinds = {'nozzle', 'nozzle_2', 'bed', 'chamber'};

/// The sensors of one printer the history sheet can switch between, labelled
/// exactly as their tiles are.
List<HeaterKindOption> _heaterKindOptions(
  List<TempReading> readings,
  AppLocalizations l10n,
) => [
  for (final r in readings)
    if (_heaterHistoryKinds.contains(r.raw))
      (kind: r.raw, label: r.label(l10n)),
];

/// What the status pill says for a printer the card does not show as offline:
/// the server's own state, or a word for its absence.
String _stateChipLabel(AppLocalizations l10n, PrinterStatus? status) {
  if (status == null) return l10n.statusUnavailable;
  return status.state ??
      ((status.connected ?? false) ? l10n.online : l10n.offline);
}

/// Status pill in the card header ("IDLE", "RUNNING", "OFFLINE"). Connected →
/// green; offline → red tinted with a vivid border.
///
/// [offline] is the only thing that decides the paint, so it must be passed
/// wherever the printer is unreachable — including the window in which the card
/// still shows its body (see the grace period in `PrinterCard`). A chip that
/// took "connected" as a hint and painted green anyway is how an OFFLINE label
/// ended up in the green pill.
class _StateChip extends StatelessWidget {
  const _StateChip({required this.label, this.offline = false});

  final String label;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final Color bg;
    final Color fg;
    final BoxBorder? border;
    if (offline) {
      bg = scheme.error.withValues(alpha: 0.14);
      fg = scheme.error;
      border = Border.all(color: scheme.error, width: 1.5);
    } else {
      bg = t.accentGreen.withValues(alpha: 0.16);
      fg = t.accentGreenInk;
      border = null;
    }
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DashSpace.md,
        vertical: DashSpace.sm,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: border,
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: t.micro.copyWith(color: fg, letterSpacing: 0.4),
      ),
    );
  }
}

/// ETA as a clock reading = now + remaining minutes.
String _etaTime(DateTimeFormats fmt, int remainingMinutes) =>
    fmt.time(DateTime.now().add(Duration(minutes: remainingMinutes)));

/// Bottom sheet to set a sensor's target temperature: a slider with fine −/+
/// steppers, plus Off/Set. For the chamber on airduct-capable models it also
/// exposes a cooling/heating flap toggle, applied immediately (its own command).
/// Applying a target closes the sheet — the optimistic setpoint shows on the
/// gauge right away (see [_GaugeTile]).
class _TempControlSheet extends ConsumerStatefulWidget {
  const _TempControlSheet({
    required this.printerId,
    required this.reading,
    required this.model,
    required this.nozzleIndex,
    required this.initialTarget,
    required this.dualNozzle,
    required this.activeExtruder,
    required this.printing,
  });

  final int printerId;
  final TempReading reading;
  final String? model;
  final int nozzleIndex;
  final int initialTarget;
  final bool dualNozzle;
  final int? activeExtruder;
  final bool printing;

  @override
  ConsumerState<_TempControlSheet> createState() => _TempControlSheetState();
}

class _TempControlSheetState extends ConsumerState<_TempControlSheet> {
  /// The server's chamber ceiling — 60 until the version is known, so it is
  /// watched: a sheet opened in the first moments of a cold start would
  /// otherwise keep the lower ceiling for its whole life.
  int get _chamberMax => ref.watch(chamberMaxTargetProvider);

  /// Not clamped: a target set elsewhere above this sheet's range (65 °C while
  /// the ceiling still reads 60, a nozzle above 300) is the printer's current
  /// setting, and applying the sheet untouched must not lower it.
  late int _target = widget.initialTarget;
  late bool? _airductHeating = widget.reading.airductIsHeating;
  bool _busy = false;

  /// Nozzle we're switching to, until the live status confirms it. While set
  /// (and not yet reflected) the switch shows a spinner and is locked.
  int? _switchingTo;

  TempReading get _reading => widget.reading;

  void _bump(int delta) => setState(
    () => _target = (_target + delta)
        .clamp(0, _reading.maxTarget(ref.read(chamberMaxTargetProvider)))
        .toInt(),
  );

  Future<void> _apply(int target) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final notifier = ref.read(controlsProvider.notifier);
    final result = switch (_reading.kind) {
      TempKind.nozzle => await notifier.setNozzleTemp(
        widget.printerId,
        _reading.raw,
        target,
        nozzle: widget.nozzleIndex,
      ),
      TempKind.bed => await notifier.setBedTemp(widget.printerId, target),
      TempKind.chamber => await notifier.setChamberTemp(
        widget.printerId,
        target,
      ),
      TempKind.unknown => ActionOutcome.ok,
    };
    if (!mounted) return;
    navigator.pop();
    final msg = result.messageFor(l10n);
    if (msg != null) {
      messenger.snack(msg, clearQueue: true);
    }
  }

  Future<void> _setAirduct(bool heating) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final previous = _airductHeating;
    setState(() => _airductHeating = heating);
    final result = await ref
        .read(controlsProvider.notifier)
        .setAirduct(widget.printerId, heating: heating);
    if (!mounted) return;
    final failure = result.messageFor(l10n);
    if (failure != null) {
      setState(() => _airductHeating = previous); // revert on failure
      messenger.snack(failure, clearQueue: true);
    }
  }

  /// Make this nozzle the active extruder (dual-head only). Keeps the sheet
  /// open so the user can also set its temperature; state is optimistic.
  Future<void> _switchNozzle() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    setState(() => _switchingTo = widget.nozzleIndex);
    final result = await ref
        .read(controlsProvider.notifier)
        .setExtruder(widget.printerId, widget.nozzleIndex);
    if (!mounted) return;
    final failure = result.messageFor(l10n);
    if (failure == null) return; // keep locked until live confirms
    setState(() => _switchingTo = null); // command failed — release the lock
    messenger.snack(failure, clearQueue: true);
  }

  /// Active-extruder control shown in the nozzle sheet on dual-head printers:
  /// a compact tag when this nozzle is already active, else an "Activate"
  /// button that selects it.
  Widget _nozzleSwitch(
    DashTokens t,
    AppLocalizations l10n, {
    required bool isActive,
    required bool busy,
    required bool enabled,
  }) {
    if (isActive) {
      return logTag(
        'sheet.temperature',
        Row(
          children: [
            Icon(Icons.check_circle, size: 15, color: t.accentGreenInk),
            const SizedBox(width: DashSpace.sm),
            Text(
              l10n.ctrlNozzleActive,
              style: t.label.copyWith(color: t.accentGreenInk),
            ),
          ],
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: t.subCard,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? _switchNozzle : null,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DashSpace.md,
              vertical: DashSpace.sm,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: t.subCardBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                busy
                    ? const DashSpinner(size: 16)
                    : Icon(
                        Icons.swap_horiz,
                        size: 16,
                        color: enabled ? t.textPrimary : t.textTertiary,
                      ),
                const SizedBox(width: DashSpace.sm),
                Text(
                  l10n.ctrlActivate,
                  style: t.bodyBold.copyWith(
                    color: enabled ? t.textPrimary : t.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ).tagged('printer.switch_nozzle'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final max = _reading.maxTarget(_chamberMax);
    final step = _reading.targetStep;
    final accent = _reading.gaugeColor(t, target: _target.toDouble());
    final showAirduct =
        _reading.kind == TempKind.chamber && supportsAirduct(widget.model);
    // Nozzle switch (dual-head only): the active extruder comes from LIVE
    // status (poll/WS), so the lock persists through the physical switch.
    final showNozzleSwitch =
        _reading.kind == TempKind.nozzle && widget.dualNozzle;
    final liveExtruder =
        ref.watch(
          printerStatusesProvider.select(
            (m) => m[widget.printerId]?.activeExtruder,
          ),
        ) ??
        widget.activeExtruder;
    // Confirmed once live status reports the requested nozzle — release the
    // lock (post-frame to avoid setState during build).
    if (_switchingTo != null && liveExtruder == _switchingTo) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _switchingTo = null);
      });
    }
    final switching =
        _switchingTo == widget.nozzleIndex &&
        liveExtruder != widget.nozzleIndex;
    final isActiveNozzle = liveExtruder == widget.nozzleIndex;
    // With the airduct in Cooling, M141 does nothing, so a chamber target can
    // only be set once the flap is switched to Heating.
    final chamberGated = _reading.kind == TempKind.chamber && showAirduct;
    final tempEnabled = !chamberGated || (_airductHeating ?? false);

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
                Text(_reading.label(l10n), style: t.titleLg),
                const Spacer(),
                Text(
                  _reading.actual == null
                      ? '—'
                      : '${_reading.actual!.toStringAsFixed(0)}°',
                  style: t.monoTitle.copyWith(
                    fontWeight: FontWeight.w400,
                    color: t.textSecondary,
                  ),
                ),
              ],
            ),
            if (showNozzleSwitch) ...[
              const SizedBox(height: DashSpace.md),
              _nozzleSwitch(
                t,
                l10n,
                isActive: isActiveNozzle,
                busy: switching,
                enabled: !widget.printing && !switching,
              ),
            ],
            const SizedBox(height: DashSpace.lg),
            // Dim + block the target editor when a chamber target can't
            // take effect (airduct not in Heating).
            Opacity(
              opacity: tempEnabled ? 1 : 0.35,
              child: IgnorePointer(
                ignoring: !tempEnabled,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Text(
                        _target == 0 ? l10n.ctrlOff : '$_target°',
                        style: TextStyle(
                          fontFamily: DashTokens.fontMono,
                          fontSize: 44,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: DashSpace.sm),
                    Row(
                      children: [
                        _StepButton(
                          icon: Icons.remove,
                          id: 'temperature.step_down',
                          onTap: () => _bump(-step),
                        ),
                        Expanded(
                          // No `divisions`: tick marks would be far denser
                          // on the wide nozzle range (0–300) than the bed
                          // (0–120) and look inconsistent. The slider stays
                          // smooth and the value snaps to `step` here.
                          child: Slider(
                            value: _target.clamp(0, max).toDouble(),
                            max: max.toDouble(),
                            activeColor: accent,
                            onChanged: (v) => setState(
                              () => _target = ((v / step).round() * step).clamp(
                                0,
                                max,
                              ),
                            ),
                          ).tagged('temperature.slider'),
                        ),
                        _StepButton(
                          icon: Icons.add,
                          id: 'temperature.step_up',
                          onTap: () => _bump(step),
                        ),
                      ],
                    ),
                    const SizedBox(height: DashSpace.md),
                    // Quick-pick presets — tapping one moves the slider;
                    // the change is committed with the Set button below.
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: DashSpace.sm,
                      runSpacing: DashSpace.sm,
                      children: [
                        for (final p in _reading.presets(_chamberMax))
                          _PresetChip(
                            label: '$p°',
                            id: 'temperature.preset',
                            selected: _target == p,
                            onTap: () => setState(() => _target = p),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (showAirduct) ...[
              const SizedBox(height: DashSpace.md),
              _AirductToggle(
                heating: _airductHeating,
                onChanged: _busy ? null : _setAirduct,
              ),
            ],
            const SizedBox(height: DashSpace.xl),
            Row(
              children: [
                Expanded(
                  child: _SheetButton(
                    label: l10n.ctrlOff,
                    id: 'temperature.off',
                    onTap: _busy ? null : () => _apply(0),
                  ),
                ),
                const SizedBox(width: DashSpace.md),
                Expanded(
                  child: _SheetButton(
                    label: l10n.ctrlSet,
                    id: 'temperature.set',
                    filled: true,
                    busy: _busy,
                    onTap: (_busy || !tempEnabled)
                        ? null
                        : () => _apply(_target),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Quick-pick temperature preset pill. Selected when it matches the current
/// slider target — highlighted with the accent green, otherwise a dark pill.
class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.id,
    required this.onTap,
  });

  final String label;

  /// Diagnostic identifier — see [_SheetButton.id]. The chips of the
  /// temperature, fan, drying and movement sheets are the same widget.
  final String id;

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final fg = selected ? t.accentGreenInk : t.textPrimary;
    return Material(
      color: selected ? t.accentGreen.withValues(alpha: 0.16) : t.subCard,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: DashSpace.lg,
            vertical: DashSpace.md,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? t.accentGreen.withValues(alpha: 0.5)
                  : t.subCardBorder,
            ),
          ),
          child: Text(label, style: t.monoValue.copyWith(color: fg)),
        ),
        // Which chip is the current one is otherwise painted and nothing else:
        // a reader would announce seven identical buttons.
      ).tagged(id, selected: selected),
    );
  }
}

/// Round −/+ button flanking the target slider.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.id,
    required this.onTap,
  });

  final IconData icon;

  /// Diagnostic identifier. Required for the same reason as on [_SheetButton]:
  /// this button is shared by the temperature, fan and drying sheets, and a tag
  /// baked into the widget made every one of them log as the temperature's.
  final String id;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Material(
      color: t.subCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: t.subCardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 20, color: t.textPrimary),
        ),
      ).tagged(id),
    );
  }
}

/// Cooling/Heating segmented toggle for the chamber airduct flap.
class _AirductToggle extends StatelessWidget {
  const _AirductToggle({required this.heating, required this.onChanged});

  final bool? heating;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Icon(Icons.air, size: 16, color: t.textSecondary),
        const SizedBox(width: DashSpace.sm),
        Text(l10n.ctrlAirduct, style: t.body.copyWith(color: t.textSecondary)),
        const Spacer(),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: false,
              icon: const Icon(Icons.ac_unit, size: 16),
              label: Text(l10n.ctrlAirductCooling),
            ),
            ButtonSegment(
              value: true,
              icon: const Icon(Icons.local_fire_department, size: 16),
              label: Text(l10n.ctrlAirductHeating),
            ),
          ],
          selected: {heating ?? false},
          onSelectionChanged: onChanged == null
              ? null
              : (s) => onChanged!(s.first),
        ).tagged('controls.airduct'),
      ],
    );
  }
}

/// Filled (primary) or outlined (secondary) action button in the temp sheet.
class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.id,
    required this.onTap,
    this.filled = false,
    this.busy = false,
  });

  final String label;

  /// Diagnostic identifier, per button rather than per widget: "Off" and "Set"
  /// sit side by side and do opposite things, and a shared tag made the log
  /// claim a cancelled heat-up was the user applying a temperature.
  final String id;

  final VoidCallback? onTap;
  final bool filled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final fg = filled ? t.accentGreenInk : t.textPrimary;
    return Material(
      color: filled ? t.accentGreen.withValues(alpha: 0.16) : t.subCard,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: DashSpace.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: filled
                  ? t.accentGreen.withValues(alpha: 0.5)
                  : t.subCardBorder,
            ),
          ),
          alignment: Alignment.center,
          child: busy
              ? const DashSpinner()
              : Text(label, style: t.titleSm.copyWith(color: fg)),
        ),
      ).tagged(id),
    );
  }
}
