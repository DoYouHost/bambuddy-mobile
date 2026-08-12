part of 'printer_card.dart';

/// Print lifecycle controls (M4): pause/resume/stop (stop always behind
/// confirmation) and speed. Chamber light lives in its own [_LightSwitchRow].
/// Optimistic state + rollback held by [controlsProvider]; here: render, send
/// action, show result snackbar. Hides when disconnected or not printing.
class _ControlsActions extends ConsumerWidget {
  const _ControlsActions({required this.printerId, required this.status});

  final int printerId;
  final PrinterStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
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
            Icon(Icons.lock_outline, size: 16, color: t.textSecondary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                l10n.ctrlForbidden,
                style: TextStyle(
                  fontFamily: DashTokens.fontUi,
                  fontSize: 12,
                  color: t.textSecondary,
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

    final printing = status.isPrinting;
    final paused = status.isPaused;
    final activePrint = printing && !paused;

    // Primary lifecycle only (pause/resume/stop); speed moved under "Details"
    // (see [_SpeedControlTile]). Idle → nothing to show → hide entirely.
    final buttons = <Widget>[
      if (activePrint)
        _LifecycleButton(
          id: 'controls.pause',
          icon: Icons.pause,
          label: l10n.ctrlPause,
          busy: pending.isBusy(ControlAction.pause),
          onPressed: () => _run(context, ref, ControlAction.pause),
        ),
      if (paused)
        _LifecycleButton(
          id: 'controls.resume',
          icon: Icons.play_arrow,
          label: l10n.ctrlResume,
          busy: pending.isBusy(ControlAction.resume),
          onPressed: () => _run(context, ref, ControlAction.resume),
        ),
      if (printing)
        _LifecycleButton(
          id: 'controls.stop',
          icon: Icons.stop,
          label: l10n.ctrlStop,
          danger: true,
          busy: pending.isBusy(ControlAction.stop),
          onPressed: () => _confirmStop(context, ref),
        ),
    ];
    if (buttons.isEmpty) return const SizedBox.shrink();

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
      _ => ActionOutcome.ok,
    };
    if (context.mounted) _showResult(context, result);
  }

  /// Stop always behind confirmation—easy to kill a multi-hour print with one tap.
  Future<void> _confirmStop(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await confirmDialog(
      context,
      title: l10n.ctrlStopConfirmTitle,
      message: l10n.ctrlStopConfirmBody,
      confirmLabel: l10n.ctrlStop,
      destructive: true,
      id: 'controls.stop_confirm',
    );
    if (confirmed && context.mounted) {
      await _run(context, ref, ControlAction.stop);
    }
  }

  void _showResult(BuildContext context, ActionOutcome result) {
    final l10n = AppLocalizations.of(context);
    final msg = result.messageFor(l10n);
    if (msg == null) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// Chamber-light row (design): bulb + label on the left, pill toggle on the
/// right, on an accent-tinted rounded panel. Optimistic state via
/// [controlsProvider]. Shown only when connected and control is permitted.
class _LightSwitchRow extends ConsumerWidget {
  const _LightSwitchRow({required this.printerId, required this.status});

  final int printerId;
  final PrinterStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = status.connected ?? false;
    final forbidden = ref.watch(controlsProvider.select((s) => s.forbidden));
    if (!connected || forbidden) return const SizedBox.shrink();

    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final pending = ref.watch(
      controlsProvider.select((s) => s.pendingFor(printerId)),
    );
    final on = pending.light ?? status.chamberLight ?? false;
    final busy = pending.isBusy(ControlAction.light);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: logTag(
          'controls.light',
          InkWell(
            onTap: busy ? null : () => _toggle(context, ref, on: !on),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              decoration: BoxDecoration(
                color: t.accentGreen.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: t.accentGreen.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(on ? Icons.lightbulb : Icons.lightbulb_outline,
                          size: 18, color: t.accentGreenInk),
                      const SizedBox(width: 8),
                      Text(
                        l10n.ctrlLight,
                        style: TextStyle(
                          fontFamily: DashTokens.fontUi,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: t.accentGreenInk,
                        ),
                      ),
                    ],
                  ),
                  busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : _PillSwitch(on: on, tokens: t),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref, {
    required bool on,
  }) async {
    final l10n = AppLocalizations.of(context);
    final result =
        await ref.read(controlsProvider.notifier).setLight(printerId, on: on);
    if (!context.mounted) return;
    final msg = result.messageFor(l10n);
    if (msg != null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}

/// Design's 42×24 pill toggle: green track when ON, neutral when OFF, with a
/// sliding knob. Animated; purely presentational (tap handled by parent).
class _PillSwitch extends StatelessWidget {
  const _PillSwitch({required this.on, required this.tokens});

  final bool on;
  final DashTokens tokens;

  @override
  Widget build(BuildContext context) {
    final knobColor = tokens.isDark
        ? const Color(0xFF0A0C08)
        : (on ? Colors.white : const Color(0xFFFFFFFF));
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      width: 42,
      height: 24,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: on ? tokens.accentGreen : tokens.gaugeTrack,
        borderRadius: BorderRadius.circular(12),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: knobColor,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

/// Smart plug control (M7)—compact ghost icon button in the card header. Plug
/// symbol shows state (`power` on / `power_off` off); power draw + state in
/// tooltip. Grayed out during print; every change needs confirmation. Optimistic
/// state + rollback via [smartPlugsProvider]. Auto-hides if none assigned.
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

    final t = DashTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    final state = ref.watch(smartPlugsProvider);
    final status = state.statusFor(plug.id);
    final on = state.effectiveOn(plug) ?? false;
    final busy = state.isBusy(plug.id);
    final forbidden = state.forbidden;
    final reachable = status?.isReachable ?? true;
    final power = status?.powerW;

    final canControl = !busy && !forbidden && reachable && !printing;

    final tip = printing
        ? l10n.smartPlugCantPowerOff
        : !reachable
            ? l10n.smartPlugUnreachable
            : (on && power != null
                ? l10n.powerWatts(power.round())
                : (on ? l10n.smartPlugOn : l10n.smartPlugOff));

    final fg = !reachable
        ? scheme.error
        : (on ? t.accentGreenInk : t.textSecondary);

    return _HeaderIconButton(
      id: 'printer.smart_plug',
      tooltip: tip,
      icon: on ? Icons.power : Icons.power_off,
      color: fg,
      borderColor: on ? t.accentGreen.withValues(alpha: 0.5) : t.subCardBorder,
      onPressed: canControl ? () => _onToggle(context, ref, plug, !on) : null,
    );
  }

  Future<void> _onToggle(
    BuildContext context,
    WidgetRef ref,
    SmartPlug plug,
    bool want,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await confirmDialog(
      context,
      title: want ? l10n.smartPlugOnConfirmTitle : l10n.smartPlugOffConfirmTitle,
      message: want ? l10n.smartPlugOnConfirmBody : l10n.smartPlugOffConfirmBody,
      confirmLabel: want ? l10n.smartPlugTurnOn : l10n.smartPlugTurnOff,
      // Cutting the power to a machine is the answer worth a red button;
      // turning it on is not.
      destructive: !want,
      id: 'smart_plug',
    );
    if (!confirmed || !context.mounted) return;

    final result = await ref
        .read(smartPlugsProvider.notifier)
        .control(plug.id, want ? SmartPlugAction.on : SmartPlugAction.off);
    if (!context.mounted) return;
    final msg = result.messageFor(l10n);
    if (msg != null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}

/// Compact square icon button used in the card header (camera, files, plug).
/// Ghost style: translucent fill + hairline border, tinted icon. Built on
/// [IconButton] so `onPressed: null` reads as disabled (grayed) consistently.
class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.id,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.color,
    this.borderColor,
  });

  /// Name for the diagnostic log; the tooltip is user-facing text and is not
  /// recorded.
  final String id;
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final fg = color ?? t.textSecondary;
    return logTag(
      id,
      IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          backgroundColor: t.subCard,
          foregroundColor: fg,
          disabledForegroundColor: fg.withValues(alpha: 0.4),
          fixedSize: const Size(34, 34),
          minimumSize: const Size(34, 34),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: borderColor ?? t.subCardBorder),
          ),
        ),
      ),
    );
  }
}

const _btnSpinner = SizedBox(
  width: 16,
  height: 16,
  child: CircularProgressIndicator(strokeWidth: 2),
);

/// Arranges control buttons in a 2-column grid; solo button takes full width.
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

/// Print lifecycle action button (pause/resume/stop). Dark-card styled: subtle
/// fill + hairline border; `danger` colors stop red. Spinner + lock when busy.
class _LifecycleButton extends StatelessWidget {
  const _LifecycleButton({
    required this.id,
    required this.icon,
    required this.label,
    required this.busy,
    required this.onPressed,
    this.danger = false,
  });

  /// Name for the diagnostic log; the visible label is localized and is not
  /// recorded.
  final String id;
  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final fg = danger ? scheme.error : t.textPrimary;
    final border = danger ? scheme.error.withValues(alpha: 0.5) : t.subCardBorder;
    return Material(
      color: t.subCard,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: logTag(
        id,
        InkWell(
          onTap: busy ? null : onPressed,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                busy ? _btnSpinner : Icon(icon, size: 18, color: fg),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: DashTokens.fontUi,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Speed selector row shown inside the collapsible "Details" section while
/// printing: a label + the speed picker. Handles the optimistic set-speed call
/// and forbidden/pending state. Hides when not printing/connected or forbidden.
class _SpeedControlTile extends ConsumerWidget {
  const _SpeedControlTile({required this.printerId, required this.status});

  final int printerId;
  final PrinterStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!(status.connected ?? false) || !status.isPrinting) {
      return const SizedBox.shrink();
    }
    final forbidden = ref.watch(controlsProvider.select((s) => s.forbidden));
    if (forbidden) return const SizedBox.shrink();

    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final pending = ref.watch(
      controlsProvider.select((s) => s.pendingFor(printerId)),
    );
    final speedLevel = pending.speedLevel ?? status.speedLevel;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(Icons.speed, size: 16, color: t.textSecondary),
          const SizedBox(width: 8),
          Text(
            l10n.ctrlSpeed,
            style: TextStyle(
              fontFamily: DashTokens.fontUi,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: t.textSecondary,
            ),
          ),
          const Spacer(),
          _SpeedControl(
            level: speedLevel,
            busy: pending.isBusy(ControlAction.speed),
            onSelected: (mode) => _setSpeed(context, ref, mode),
          ),
        ],
      ),
    );
  }

  Future<void> _setSpeed(BuildContext context, WidgetRef ref, int mode) async {
    final l10n = AppLocalizations.of(context);
    final result =
        await ref.read(controlsProvider.notifier).setSpeed(printerId, mode);
    if (!context.mounted) return;
    final msg = result.messageFor(l10n);
    if (msg != null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}

/// Print speed picker (1–4). Tap opens a menu; current is checked. Dark-card pill.
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
    final t = DashTokens.of(context);
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
            // Named by level: which speed was chosen is the record, and the
            // level is the printer's own scale, not the user's data.
            child: logTag('controls.speed.$m', Text(_speedName(l10n, m)!)),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: t.subCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.subCardBorder),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            busy ? _btnSpinner : Icon(Icons.speed, size: 18, color: t.textSecondary),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: DashTokens.fontUi,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: t.textPrimary,
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 18, color: t.textSecondary),
          ],
        ),
      ),
    ).tagged('controls.speed');
  }
}

String? _speedName(AppLocalizations l10n, int? level) => switch (level) {
      1 => l10n.speedSilent,
      2 => l10n.speedStandard,
      3 => l10n.speedSport,
      4 => l10n.speedLudicrous,
      _ => null,
    };
