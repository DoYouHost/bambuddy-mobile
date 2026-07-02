part of 'printer_card.dart';

/// Interactive control bar (M4): pause/resume/stop (stop always behind confirmation),
/// chamber light, speed. Optimistic state + rollback held by [controlsProvider];
/// here: render, send action, show result snackbar. Hides when disconnected.
class _ControlsActions extends ConsumerWidget {
  const _ControlsActions({required this.printerId, required this.status});

  final int printerId;
  final PrinterStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final connected = status.connected ?? false;
    if (!connected) return const SizedBox.shrink();

    final forbidden = ref.watch(controlsProvider.select((s) => s.forbidden));
    if (forbidden) {
      // API key lacks `can_control_printer`—show clear reason instead of dead buttons.
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: [
            Icon(
              Icons.lock_outline,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                l10n.ctrlForbidden,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final pending = ref.watch(
      controlsProvider.select((s) => s.pendingFor(printerId)),
    );
    final light = pending.light ?? status.chamberLight ?? false;
    final speedLevel = pending.speedLevel ?? status.speedLevel;

    final printing = status.isPrinting;
    final paused = status.isPaused;
    final activePrint = printing && !paused;

    final buttons = <Widget>[
      if (activePrint)
        _LifecycleButton(
          icon: Icons.pause,
          label: l10n.ctrlPause,
          busy: pending.isBusy(ControlAction.pause),
          onPressed: () => _run(context, ref, ControlAction.pause),
        ),
      if (paused)
        _LifecycleButton(
          icon: Icons.play_arrow,
          label: l10n.ctrlResume,
          busy: pending.isBusy(ControlAction.resume),
          onPressed: () => _run(context, ref, ControlAction.resume),
        ),
      if (printing)
        _LifecycleButton(
          icon: Icons.stop,
          label: l10n.ctrlStop,
          danger: true,
          busy: pending.isBusy(ControlAction.stop),
          onPressed: () => _confirmStop(context, ref),
        ),
      _LightToggle(
        on: light,
        busy: pending.isBusy(ControlAction.light),
        onPressed: () => _toggleLight(context, ref, on: !light),
      ),
      if (printing)
        _SpeedControl(
          level: speedLevel,
          busy: pending.isBusy(ControlAction.speed),
          onSelected: (mode) => _setSpeed(context, ref, mode),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: _ControlsGrid(buttons: buttons),
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    ControlAction action,
  ) async {
    final notifier = ref.read(controlsProvider.notifier);
    final result = switch (action) {
      ControlAction.pause => await notifier.pause(printerId),
      ControlAction.resume => await notifier.resume(printerId),
      ControlAction.stop => await notifier.stop(printerId),
      _ => ControlResult.ok,
    };
    if (context.mounted) _showResult(context, result);
  }

  Future<void> _toggleLight(
    BuildContext context,
    WidgetRef ref, {
    required bool on,
  }) async {
    final result = await ref
        .read(controlsProvider.notifier)
        .setLight(printerId, on: on);
    if (context.mounted) _showResult(context, result);
  }

  Future<void> _setSpeed(BuildContext context, WidgetRef ref, int mode) async {
    final result = await ref
        .read(controlsProvider.notifier)
        .setSpeed(printerId, mode);
    if (context.mounted) _showResult(context, result);
  }

  /// Stop always behind confirmation—deliverable requirement, not polish: easy to kill
  /// a multi-hour print with one tap.
  Future<void> _confirmStop(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.ctrlStopConfirmTitle),
        content: Text(l10n.ctrlStopConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.ctrlStop),
          ),
        ],
      ),
    );
    if ((confirmed ?? false) && context.mounted) {
      await _run(context, ref, ControlAction.stop);
    }
  }

  void _showResult(BuildContext context, ControlResult result) {
    final l10n = AppLocalizations.of(context);
    final msg = switch (result) {
      ControlResult.ok => null,
      ControlResult.forbidden => l10n.ctrlForbidden,
      ControlResult.error => l10n.ctrlFailed,
    };
    if (msg == null) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// Smart plug control for printer (M7)—square icon button in card header, inline
/// with printer name. Plug symbol shows state: `power` = on, `power_off` (crossed)
/// = off; power draw and state in tooltip. Tap toggles. Auto-hides if none assigned.
/// Key rules: **button grayed out during print** (no power changes to active machine)
/// and **every change (ON/OFF) needs confirmation** dialog. Optimistic state + rollback
/// held by [smartPlugsProvider].
class _SmartPlugButton extends ConsumerWidget {
  const _SmartPlugButton({required this.printerId, required this.printing});

  final int printerId;
  final bool printing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plug = ref.watch(
      smartPlugsProvider.select((s) => s.plugForPrinterCard(printerId)),
    );
    if (plug == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    final state = ref.watch(smartPlugsProvider);
    final status = state.statusFor(plug.id);
    final on = state.effectiveOn(plug) ?? false;
    final busy = state.isBusy(plug.id);
    final forbidden = state.forbidden;
    final reachable = status?.isReachable ?? true;
    final power = status?.powerW;

    // During print button is fully grayed out—don't change power on active machine.
    final canControl = !busy && !forbidden && reachable && !printing;

    // Tooltip carries state + power draw (button is just icon): unreachable→
    // "Unreachable"; on with measurement→"X W"; otherwise raw state On/Off.
    final tip = printing
        ? l10n.smartPlugCantPowerOff
        : !reachable
        ? l10n.smartPlugUnreachable
        : (on && power != null
              ? l10n.powerWatts(power.round())
              : (on ? l10n.smartPlugOn : l10n.smartPlugOff));

    final fg = !reachable
        ? scheme.error
        : (on ? scheme.primary : scheme.onSurfaceVariant);

    return IconButton(
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      onPressed: canControl ? () => _onToggle(context, ref, plug, !on) : null,
      icon: Icon(on ? Icons.power : Icons.power_off),
      style: IconButton.styleFrom(
        foregroundColor: fg,
        // Square (slightly rounded) with border—distinguishes power toggle from
        // round camera button next to it.
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: on ? scheme.primary : scheme.outlineVariant),
      ),
    );
  }

  Future<void> _onToggle(
    BuildContext context,
    WidgetRef ref,
    SmartPlug plug,
    bool want,
  ) async {
    final l10n = AppLocalizations.of(context);

    // Every power change needs confirmation—easy to kill the machine with one tap.
    // OFF (power cut) highlighted in error color; ON is neutral.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          want ? l10n.smartPlugOnConfirmTitle : l10n.smartPlugOffConfirmTitle,
        ),
        content: Text(
          want ? l10n.smartPlugOnConfirmBody : l10n.smartPlugOffConfirmBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: want
                ? null
                : FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                  ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(want ? l10n.smartPlugTurnOn : l10n.smartPlugTurnOff),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !context.mounted) return;

    final result = await ref
        .read(smartPlugsProvider.notifier)
        .control(plug.id, want ? SmartPlugAction.on : SmartPlugAction.off);
    if (!context.mounted) return;
    final msg = switch (result) {
      ControlResult.ok => null,
      ControlResult.forbidden => l10n.ctrlForbidden,
      ControlResult.error => l10n.ctrlFailed,
    };
    if (msg != null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}

const _btnSpinner = SizedBox(
  width: 16,
  height: 16,
  child: CircularProgressIndicator(strokeWidth: 2),
);

/// Arranges control buttons in 2-column grid, in [buttons] order (pause/resume,
/// stop, light, speed). Each cell stretches to equal width; solo button (e.g.,
/// light only when idle) takes full row width.
class _ControlsGrid extends StatelessWidget {
  const _ControlsGrid({required this.buttons});

  final List<Widget> buttons;

  @override
  Widget build(BuildContext context) {
    const gap = 8.0;
    final rows = <Widget>[];
    for (var i = 0; i < buttons.length; i += 2) {
      final end = i + 2 > buttons.length ? buttons.length : i + 2;
      final pair = buttons.sublist(i, end);
      rows.add(
        Row(
          children: [
            for (var j = 0; j < pair.length; j++) ...[
              if (j > 0) const SizedBox(width: gap),
              Expanded(child: pair[j]),
            ],
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: gap),
          rows[i],
        ],
      ],
    );
  }
}

/// Print lifecycle action button (pause/resume/stop). Shows spinner and locks when
/// busy; `danger` colors stop red.
class _LifecycleButton extends StatelessWidget {
  const _LifecycleButton({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = danger ? scheme.error : null;
    return OutlinedButton.icon(
      onPressed: busy ? null : onPressed,
      icon: busy ? _btnSpinner : Icon(icon, size: 18, color: fg),
      label: Text(label, style: fg == null ? null : TextStyle(color: fg)),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        side: danger
            ? BorderSide(color: scheme.error.withValues(alpha: 0.5))
            : null,
      ),
    );
  }
}

/// Chamber light toggle. Shows current (optimistic) state; yellow bulb = on.
class _LightToggle extends StatelessWidget {
  const _LightToggle({
    required this.on,
    required this.busy,
    required this.onPressed,
  });

  final bool on;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const amber = Color(0xFFFFC107);
    return OutlinedButton.icon(
      onPressed: busy ? null : onPressed,
      icon: busy
          ? _btnSpinner
          : Icon(
              on ? Icons.lightbulb : Icons.lightbulb_outline,
              size: 18,
              color: on ? amber : null,
            ),
      label: Text(on ? l10n.ctrlLightOn : l10n.ctrlLightOff),
      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
    );
  }
}

/// Print speed picker (1–4). Tap opens menu with four levels; current is checked.
/// Locked with spinner when busy.
class _SpeedControl extends StatelessWidget {
  const _SpeedControl({
    required this.level,
    required this.busy,
    required this.onSelected,
  });

  final int? level;
  final bool busy;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final label = _speedName(l10n, level) ?? l10n.ctrlSpeed;

    return PopupMenuButton<int>(
      enabled: !busy,
      tooltip: l10n.ctrlSpeed,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (var m = 1; m <= 4; m++)
          CheckedPopupMenuItem<int>(
            value: m,
            checked: level == m,
            child: Text(_speedName(l10n, m)!),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: scheme.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            busy
                ? _btnSpinner
                : Icon(Icons.speed, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(label, style: theme.textTheme.labelLarge),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

String? _speedName(AppLocalizations l10n, int? level) => switch (level) {
  1 => l10n.speedSilent,
  2 => l10n.speedStandard,
  3 => l10n.speedSport,
  4 => l10n.speedLudicrous,
  _ => null,
};

/// Read-only chip bar for sensor state (fans, chamber air duct). Controllable
/// values (light, speed) in [_ControlsActions]. Renders only if server provides any value.
class _ControlsRow extends StatelessWidget {
  const _ControlsRow({required this.status});

  final PrinterStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fanColor = _fanColor(context);

    // `valueAlternatives` reserves width for widest possible value so chip
    // size doesn't change during polling (e.g., 53% → 100%).
    // Fans 0–100%, speed up to 166% (Ludicrous)→3 digits.
    final chips = <Widget>[
      if (status.coolingFanSpeed != null)
        _ControlChip(
          icon: Icons.air,
          label: l10n.ctrlFanPart,
          caption: l10n.ctrlFanPartShort,
          value: '${status.coolingFanSpeed}%',
          valueAlternatives: const ['100%'],
          color: fanColor(status.coolingFanSpeed!),
        ),
      if (status.bigFan1Speed != null)
        _ControlChip(
          icon: Icons.air,
          label: l10n.ctrlFanAux,
          caption: l10n.ctrlFanAuxShort,
          value: '${status.bigFan1Speed}%',
          valueAlternatives: const ['100%'],
          color: fanColor(status.bigFan1Speed!),
        ),
      if (status.bigFan2Speed != null)
        _ControlChip(
          icon: Icons.air,
          label: l10n.ctrlFanChamber,
          caption: l10n.ctrlFanChamberShort,
          value: '${status.bigFan2Speed}%',
          valueAlternatives: const ['100%'],
          color: fanColor(status.bigFan2Speed!),
        ),
      // Chamber air duct (heating/cooling) moved to chamber temp tile—
      // see _AirductBadge in _TempTile.
    ];

    if (chips.isEmpty) return const SizedBox.shrink();

    // Chips evenly distributed across card width—each in `Expanded`, so they
    // divide the row equally regardless of count.
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: chips[i]),
          ],
        ],
      ),
    );
  }

  // Fan: idle (0%)→dimmed, spinning→cool accent.
  Color Function(int) _fanColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return (speed) =>
        speed > 0 ? const Color(0xFF4FC3F7) : scheme.onSurfaceVariant;
  }
}

/// Single control chip: icon + short caption + value. [label] is full name in
/// tooltip; [caption] is visible shorthand (e.g., "Chamber") so icon alone needn't
/// explain which fan the reading is for.
class _ControlChip extends StatelessWidget {
  const _ControlChip({
    required this.icon,
    required this.label,
    required this.value,
    this.caption,
    this.valueAlternatives = const [],
    this.color,
  });

  final IconData icon;
  final String label;

  /// Visible shorthand next to icon (optional). When null—chip shows icon and
  /// value only (legacy behavior).
  final String? caption;

  final String value;

  /// All possible values this chip can display. Value slot reserves width for
  /// widest, so chip maintains constant size regardless of current value
  /// (e.g., "53%" vs "100%").
  final List<String> valueAlternatives;

  /// Icon/value accent color; null = neutral theme color.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = color ?? scheme.onSurfaceVariant;
    // Tabular figures: all digits same width—no jitter when swapping same-length
    // digits (e.g., 53% → 67%).
    final valueStyle = (theme.textTheme.labelMedium ?? const TextStyle())
        .copyWith(
          color: accent,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        );

    // Slot width = widest possible value (measured, not guessed)→chip stays
    // constant size despite polling changes. Measurement respects text scaling.
    final scaler = MediaQuery.textScalerOf(context);
    final dir = Directionality.of(context);
    var slotWidth = 0.0;
    for (final v in [value, ...valueAlternatives]) {
      final tp = TextPainter(
        text: TextSpan(text: v, style: valueStyle),
        textDirection: dir,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      if (tp.width > slotWidth) slotWidth = tp.width;
    }

    return Tooltip(
      message: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: 6),
            if (caption != null) ...[
              Flexible(
                child: Text(
                  caption!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            SizedBox(
              width: slotWidth.ceilToDouble(),
              child: Text(value, style: valueStyle, maxLines: 1),
            ),
          ],
        ),
      ),
    );
  }
}
