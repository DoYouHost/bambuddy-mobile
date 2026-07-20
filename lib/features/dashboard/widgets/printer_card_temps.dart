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
class _GaugeTile extends ConsumerWidget {
  const _GaugeTile({
    required this.reading,
    required this.printerId,
    required this.model,
    required this.nozzleIndex,
  });

  final _TempReading reading;
  final int printerId;
  final String? model;

  /// Hardware nozzle index (0=right/default, 1=left) for nozzle tiles; null for
  /// non-nozzle sensors.
  final int? nozzleIndex;

  bool get _isEditable => switch (reading.kind) {
        _TempKind.nozzle || _TempKind.bed => true,
        _TempKind.chamber => supportsChamberHeater(model),
        _TempKind.unknown => false,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final pending =
        ref.watch(controlsProvider.select((s) => s.pendingFor(printerId)));
    final forbidden = ref.watch(controlsProvider.select((s) => s.forbidden));

    final actual = reading.actual;
    // Optimistic overlay: setpoint and airduct glyph reflect a just-sent command
    // until real status catches up (see ControlsNotifier.optimisticHold).
    final target = reading.kind == _TempKind.unknown
        ? reading.target
        : (pending.tempTarget(reading.raw)?.toDouble() ?? reading.target);
    final hasTarget = target != null && target > 0;
    // One thermal-state color drives the whole tile — ring, setpoint and the
    // chamber's air-duct glyph all use [accent] (orange = heating/holding,
    // blue = cooling/idle). The ring center shows the setpoint ("-" when unset).
    final accent = reading.gaugeColor(t, target: target);
    final airduct = reading.kind == _TempKind.chamber
        ? (pending.airductHeating ?? reading.airductIsHeating)
        : reading.airductIsHeating;
    final airductIcon = airduct == null
        ? null
        : (airduct ? Icons.local_fire_department : Icons.ac_unit);

    final editable = _isEditable && !forbidden;

    final tile = Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
              fraction: actual == null ? 0 : actual / reading.gaugeMax,
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
                padding: const EdgeInsets.only(right: 40),
                child: Text(
                  reading.label(l10n).toUpperCase(),
                  style: TextStyle(
                    fontFamily: DashTokens.fontUi,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    color: t.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (airductIcon != null) ...[
                    Icon(airductIcon, size: 20, color: accent),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    actual == null ? '—' : '${actual.toStringAsFixed(0)}°',
                    style: TextStyle(
                      fontFamily: DashTokens.fontMono,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                      color: t.textPrimary,
                    ),
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
      child: InkWell(
        onTap: () => _openSheet(context, target?.round() ?? 0),
        child: tile,
      ),
    );
  }

  void _openSheet(BuildContext context, int initialTarget) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TempControlSheet(
        printerId: printerId,
        reading: reading,
        model: model,
        nozzleIndex: nozzleIndex ?? 0,
        initialTarget: initialTarget,
      ),
    );
  }
}

/// Status pill in the card header ("IDLE", "RUNNING", "OFFLINE"). Connected →
/// green; offline → red tinted with a vivid border.
class _StateChip extends StatelessWidget {
  const _StateChip({
    required this.label,
    required this.connected,
    this.active = false,
    this.offline = false,
  });

  final String label;
  final bool connected;
  final bool active;
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
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: border,
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontFamily: DashTokens.fontUi,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: fg,
        ),
      ),
    );
  }
}

enum _TempKind { nozzle, bed, chamber, unknown }

/// Pair of readings (current + target) for one sensor. Label is translated
/// at render time (with [BuildContext]).
class _TempReading {
  const _TempReading({
    required this.kind,
    required this.raw,
    required this.actual,
    required this.target,
    this.index,
    this.airductIsHeating,
  });

  final _TempKind kind;
  final String raw; // raw key—shown for unknown sensor
  final int? index; // nozzle number (e.g., 2) or null
  final double? actual;
  final double? target;

  /// Chamber air duct mode (heating/cooling); set ONLY for chamber tile where we
  /// show it instead of the setpoint. null = unknown/n.a.
  final bool? airductIsHeating;

  String label(AppLocalizations l10n) => switch (kind) {
        _TempKind.nozzle =>
          index == null ? l10n.tempNozzle : l10n.tempNozzleNumbered('$index'),
        _TempKind.bed => l10n.tempBed,
        _TempKind.chamber => l10n.tempChamber,
        _TempKind.unknown => raw,
      };

  /// Upper bound of the gauge sweep per sensor (approx working range).
  double get gaugeMax => switch (kind) {
        _TempKind.nozzle => 300,
        _TempKind.bed => 120,
        _TempKind.chamber => 60,
        _TempKind.unknown => 300,
      };

  /// Gauge/value color by thermal state (same for every sensor): heating or
  /// holding at the setpoint → orange; already above the setpoint (cooling) or
  /// no setpoint → blue. A small tolerance avoids color flicker around target.
  /// [target] overrides the reading's own setpoint (for optimistic overlay).
  Color gaugeColor(DashTokens t, {double? target}) {
    final tgt = target ?? this.target;
    const tolerance = 2.0;
    if (tgt == null || tgt <= 0) return t.accentBlue;
    if (actual != null && actual! > tgt + tolerance) return t.accentBlue;
    return t.accentOrange;
  }

  /// Upper bound the target slider allows. Slightly under the server's hard
  /// caps (nozzle 320 / bed 140) to a sane working range; chamber = server max.
  int get maxTarget => switch (kind) {
        _TempKind.nozzle => 300,
        _TempKind.bed => 120,
        _TempKind.chamber => 60,
        _TempKind.unknown => 300,
      };

  /// Slider/stepper granularity: 1° everywhere for smooth fine control.
  int get targetStep => 1;

  /// Common quick-pick targets shown as chips in the sheet (Off has its own
  /// button, so it's not listed here).
  List<int> get presets => switch (kind) {
        _TempKind.nozzle => const [200, 220, 240, 260],
        _TempKind.bed => const [50, 60, 80, 100],
        _TempKind.chamber => const [30, 40, 50, 60],
        _TempKind.unknown => const [],
      };
}

/// Group raw temperature keys into current/target pairs and order known sensors
/// (nozzle, bed, chamber) before unknown ones.
List<_TempReading> _buildReadings(
  Map<String, double>? temps,
  bool? airductIsHeating,
) {
  if (temps == null || temps.isEmpty) return const [];

  final actuals = <String, double>{};
  final targets = <String, double>{};
  for (final entry in temps.entries) {
    var base = entry.key;
    final isTarget = base.endsWith('_target');
    if (isTarget) base = base.substring(0, base.length - '_target'.length);
    if (base.endsWith('_temper')) {
      base = base.substring(0, base.length - '_temper'.length);
    }
    (isTarget ? targets : actuals)[base] = entry.value;
  }

  const orderHint = ['nozzle', 'bed', 'chamber'];
  int rank(String base) {
    final stem = RegExp(r'^([a-z]+)').firstMatch(base)?.group(1) ?? base;
    final i = orderHint.indexOf(stem);
    return i == -1 ? orderHint.length : i;
  }

  final bases = {...actuals.keys, ...targets.keys}.toList()
    ..sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.compareTo(b);
    });

  return [
    for (final base in bases)
      _readingFor(base, actuals[base], targets[base], airductIsHeating),
  ];
}

_TempReading _readingFor(
  String base,
  double? actual,
  double? target,
  bool? airductIsHeating,
) {
  final numbered = RegExp(r'^([a-z]+)_(\d+)$').firstMatch(base);
  final stem = numbered?.group(1) ?? base;
  final index = numbered == null ? null : int.tryParse(numbered.group(2)!);

  final kind = switch (stem) {
    'nozzle' => _TempKind.nozzle,
    'bed' => _TempKind.bed,
    'chamber' => _TempKind.chamber,
    _ => _TempKind.unknown,
  };

  return _TempReading(
    kind: kind,
    raw: base,
    index: kind == _TempKind.nozzle ? index : null,
    actual: actual,
    target: target,
    // Air duct applies to chamber only.
    airductIsHeating: kind == _TempKind.chamber ? airductIsHeating : null,
  );
}

String _durationText(AppLocalizations l10n, int minutes) => minutes < 60
    ? l10n.durationMinutes(minutes)
    : l10n.durationHoursMinutes(minutes ~/ 60, minutes % 60);

/// ETA as HH:mm = now + remaining minutes.
String _etaTime(int remainingMinutes) {
  final eta = DateTime.now().add(Duration(minutes: remainingMinutes));
  final hh = eta.hour.toString().padLeft(2, '0');
  final mm = eta.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

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
  });

  final int printerId;
  final _TempReading reading;
  final String? model;
  final int nozzleIndex;
  final int initialTarget;

  @override
  ConsumerState<_TempControlSheet> createState() => _TempControlSheetState();
}

class _TempControlSheetState extends ConsumerState<_TempControlSheet> {
  late int _target =
      widget.initialTarget.clamp(0, widget.reading.maxTarget).toInt();
  late bool? _airductHeating = widget.reading.airductIsHeating;
  bool _busy = false;

  _TempReading get _reading => widget.reading;

  void _bump(int delta) => setState(
      () => _target = (_target + delta).clamp(0, _reading.maxTarget).toInt());

  Future<void> _apply(int target) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final notifier = ref.read(controlsProvider.notifier);
    final result = switch (_reading.kind) {
      _TempKind.nozzle => await notifier.setNozzleTemp(
          widget.printerId, _reading.raw, target,
          nozzle: widget.nozzleIndex),
      _TempKind.bed => await notifier.setBedTemp(widget.printerId, target),
      _TempKind.chamber =>
        await notifier.setChamberTemp(widget.printerId, target),
      _TempKind.unknown => ControlResult.ok,
    };
    if (!mounted) return;
    navigator.pop();
    final msg = switch (result) {
      ControlResult.ok => null,
      ControlResult.forbidden => l10n.ctrlForbidden,
      ControlResult.error => l10n.ctrlFailed,
    };
    if (msg != null) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(msg)));
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
    if (result != ControlResult.ok) {
      setState(() => _airductHeating = previous); // revert on failure
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(result == ControlResult.forbidden
              ? l10n.ctrlForbidden
              : l10n.ctrlFailed),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final max = _reading.maxTarget;
    final step = _reading.targetStep;
    final accent = _reading.gaugeColor(t, target: _target.toDouble());
    final showAirduct =
        _reading.kind == _TempKind.chamber && supportsAirduct(widget.model);
    // With the airduct in Cooling, M141 does nothing, so a chamber target can
    // only be set once the flap is switched to Heating.
    final chamberGated = _reading.kind == _TempKind.chamber && showAirduct;
    final tempEnabled = !chamberGated || (_airductHeating ?? false);

    return SafeArea(
      top: false,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: t.overlaySurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: t.subCardBorder)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: t.textTertiary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        _reading.label(l10n),
                        style: TextStyle(
                          fontFamily: DashTokens.fontUi,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: t.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _reading.actual == null
                            ? '—'
                            : '${_reading.actual!.toStringAsFixed(0)}°',
                        style: TextStyle(
                          fontFamily: DashTokens.fontMono,
                          fontSize: 16,
                          color: t.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
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
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _StepButton(
                                  icon: Icons.remove, onTap: () => _bump(-step)),
                              Expanded(
                                // No `divisions`: tick marks would be far denser
                                // on the wide nozzle range (0–300) than the bed
                                // (0–120) and look inconsistent. The slider stays
                                // smooth and the value snaps to `step` here.
                                child: Slider(
                                  value: _target.clamp(0, max).toDouble(),
                                  max: max.toDouble(),
                                  activeColor: accent,
                                  onChanged: (v) => setState(() =>
                                      _target = ((v / step).round() * step)
                                          .clamp(0, max)),
                                ),
                              ),
                              _StepButton(
                                  icon: Icons.add, onTap: () => _bump(step)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Quick-pick presets — tapping one moves the slider;
                          // the change is committed with the Set button below.
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final p in _reading.presets)
                                _PresetChip(
                                  label: '$p°',
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
                    const SizedBox(height: 12),
                    _AirductToggle(
                      heating: _airductHeating,
                      onChanged: _busy ? null : _setAirduct,
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _SheetButton(
                          label: l10n.ctrlOff,
                          onTap: _busy ? null : () => _apply(0),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SheetButton(
                          label: l10n.ctrlSet,
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
    required this.onTap,
  });

  final String label;
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
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? t.accentGreen.withValues(alpha: 0.5)
                  : t.subCardBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: DashTokens.fontMono,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

/// Round −/+ button flanking the target slider.
class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
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
      ),
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
        const SizedBox(width: 8),
        Text(
          l10n.ctrlAirduct,
          style: TextStyle(
            fontFamily: DashTokens.fontUi,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: t.textSecondary,
          ),
        ),
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
        ),
      ],
    );
  }
}

/// Filled (primary) or outlined (secondary) action button in the temp sheet.
class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.onTap,
    this.filled = false,
    this.busy = false,
  });

  final String label;
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
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: filled ? t.accentGreen.withValues(alpha: 0.5) : t.subCardBorder,
            ),
          ),
          alignment: Alignment.center,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  label,
                  style: TextStyle(
                    fontFamily: DashTokens.fontUi,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
        ),
      ),
    );
  }
}
