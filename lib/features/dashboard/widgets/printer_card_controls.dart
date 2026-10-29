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

    final forbidden = ref.watch(
      controlRefusedProvider(ControlPermission.control),
    );
    if (forbidden) {
      // API key lacks `can_control_printer`—show clear reason instead of dead buttons.
      return Padding(
        padding: const EdgeInsets.only(top: DashSpace.md),
        child: Row(
          children: [
            Icon(Icons.lock_outline, size: DashIcon.sm, color: t.textSecondary),
            const SizedBox(width: DashSpace.sm),
            Flexible(
              child: Text(
                l10n.ctrlForbidden,
                style: t.labelSoft.copyWith(color: t.textSecondary),
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
    final labels = [
      if (activePrint) l10n.ctrlPause,
      if (paused) l10n.ctrlResume,
      if (printing) l10n.ctrlStop,
    ];
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
      padding: const EdgeInsets.only(top: DashSpace.md),
      child: _ControlsGrid(buttons: buttons, labels: labels),
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    ControlAction action,
  ) => runPrintAction(context, ref, printerId, action);

  Future<void> _confirmStop(BuildContext context, WidgetRef ref) =>
      stopPrintConfirmed(
        context,
        ref,
        printerId,
        confirmId: 'controls.stop_confirm',
      );
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
    final forbidden = ref.watch(
      controlRefusedProvider(ControlPermission.control),
    );
    if (!connected || forbidden) return const SizedBox.shrink();

    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final pending = ref.watch(
      controlsProvider.select((s) => s.pendingFor(printerId)),
    );
    final on = pending.light ?? status.chamberLight ?? false;
    final busy = pending.isBusy(ControlAction.light);

    return Padding(
      padding: const EdgeInsets.only(top: DashSpace.md),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(DashRadius.xl),
        clipBehavior: Clip.antiAlias,
        child: logTag(
          'controls.light',
          InkWell(
            onTap: busy ? null : () => _toggle(context, ref, on: !on),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: DashSpace.lg,
                vertical: DashSpace.lg,
              ),
              decoration: BoxDecoration(
                color: t.accentGreen.withValues(alpha: DashAlpha.faint),
                borderRadius: BorderRadius.circular(DashRadius.xl),
                border: Border.all(
                  color: t.accentGreen.withValues(alpha: DashAlpha.soft),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Flexible so a long label wraps at a large text size instead
                  // of pushing the switch off the card.
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          on ? Icons.lightbulb : Icons.lightbulb_outline,
                          size: DashIcon.md,
                          color: t.accentGreenInk,
                        ),
                        const SizedBox(width: DashSpace.sm),
                        Flexible(
                          child: Text(
                            l10n.ctrlLight,
                            style: t.titleSm.copyWith(color: t.accentGreenInk),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: DashSpace.md),
                  busy
                      ? const DashSpinner(size: DashSize.d20)
                      : PillSwitch(on: on, tokens: t),
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
    final result = await ref
        .read(controlsProvider.notifier)
        .setLight(printerId, on: on);
    if (!context.mounted) return;
    final msg = result.messageFor(l10n);
    if (msg != null) {
      ScaffoldMessenger.of(context).snack(msg, clearQueue: true);
    }
  }
}

/// Smart plug control (M7)—compact ghost icon button in the card header. Plug
/// symbol shows state (`power` on / `power_off` off); power draw + state in
/// tooltip. Grayed out during print and for a monitor-only (MQTT) plug, which
/// the server refuses to switch; every change needs confirmation. Optimistic
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

    final canControl =
        !plug.isMonitorOnly && !busy && !forbidden && reachable && !printing;

    final stateLabel = on && power != null
        ? l10n.powerWatts(power.round())
        : (on ? l10n.smartPlugOn : l10n.smartPlugOff);
    final tip = plug.isMonitorOnly
        // The reading is all such a plug can offer, so it stays next to the
        // reason the button is dead.
        ? '$stateLabel · ${l10n.smartPlugMonitorOnly}'
        : printing
        ? l10n.smartPlugCantPowerOff
        : !reachable
        ? l10n.smartPlugUnreachable
        : stateLabel;

    final fg = !reachable
        ? scheme.error
        : (on ? t.accentGreenInk : t.textSecondary);

    return _HeaderIconButton(
      id: 'printer.smart_plug',
      tooltip: tip,
      icon: on ? Icons.power : Icons.power_off,
      color: fg,
      borderColor: on
          ? t.accentGreen.withValues(alpha: DashAlpha.scrim)
          : t.subCardBorder,
      onPressed: canControl ? () => _onToggle(context, ref, plug, !on) : null,
    );
  }

  Future<void> _onToggle(
    BuildContext context,
    WidgetRef ref,
    SmartPlug plug,
    bool want,
  ) => confirmAndSwitchPlug(context, ref, plug, want, confirmId: 'smart_plug');
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
        icon: Icon(icon, size: DashIcon.md),
        // The 34 dp box is the look; the target around it is Material's 48.
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.padded,
          backgroundColor: t.subCard,
          foregroundColor: fg,
          disabledForegroundColor: fg.withValues(alpha: DashAlpha.outline),
          fixedSize: const Size(34, 34),
          minimumSize: const Size(34, 34),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DashRadius.md),
            side: BorderSide(color: borderColor ?? t.subCardBorder),
          ),
        ),
      ),
    );
  }
}

const _btnSpinner = DashSpinner(size: DashIcon.md);

/// Arranges control buttons in a 2-column grid; solo button takes full width.
class _ControlsGrid extends StatelessWidget {
  const _ControlsGrid({required this.buttons, required this.labels});

  final List<Widget> buttons;

  /// What each button paints, for the measurement that decides the columns.
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final style = DashTokens.of(context).bodyBold;
    // Side by side only while the widest label fits its button on one line;
    // otherwise one per row, as wide as the card. A label that wraps inside half
    // a card breaks mid-word, and an Expanded pair overflowed at 200 % text.
    final widest = labels
        .map((label) => textWidth(context, label, style))
        .fold<double>(0, max);
    return ContentGrid(
      minTileWidth: widest + _LifecycleButton.chrome,
      maxColumns: buttons.length,
      children: buttons,
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

  /// Width the button spends besides its label: the padding, the 1 dp border,
  /// the icon and the gap after it.
  static const chrome =
      2 * DashSpace.md + 2 * _borderWidth + DashIcon.md + DashSpace.sm;

  static const _borderWidth = 1.0;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final fg = danger ? scheme.error : t.textPrimary;
    final border = danger
        ? scheme.error.withValues(alpha: DashAlpha.scrim)
        : t.subCardBorder;
    return Material(
      color: t.subCard,
      borderRadius: BorderRadius.circular(DashRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: logTag(
        id,
        InkWell(
          onTap: busy ? null : onPressed,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: kMinInteractiveDimension,
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(
              vertical: DashSpace.md,
              horizontal: DashSpace.md,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DashRadius.lg),
              border: Border.all(color: border, width: _borderWidth),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                busy ? _btnSpinner : Icon(icon, size: DashIcon.md, color: fg),
                const SizedBox(width: DashSpace.sm),
                Text(label, style: t.bodyBold.copyWith(color: fg)),
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
    final forbidden = ref.watch(
      controlRefusedProvider(ControlPermission.control),
    );
    if (forbidden) return const SizedBox.shrink();

    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final pending = ref.watch(
      controlsProvider.select((s) => s.pendingFor(printerId)),
    );
    final speedLevel = pending.speedLevel ?? status.speedLevel;

    return Padding(
      padding: const EdgeInsets.only(top: DashSpace.md),
      child: BesideOrBelow(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.speed, size: DashIcon.sm, color: t.textSecondary),
            const SizedBox(width: DashSpace.sm),
            Text(
              l10n.ctrlSpeed,
              style: t.body.copyWith(color: t.textSecondary),
            ),
          ],
        ),
        control: _SpeedControl(
          level: speedLevel,
          busy: pending.isBusy(ControlAction.speed),
          onSelected: (mode) => _setSpeed(context, ref, mode),
        ),
      ),
    );
  }

  Future<void> _setSpeed(BuildContext context, WidgetRef ref, int mode) async {
    final l10n = AppLocalizations.of(context);
    final result = await ref
        .read(controlsProvider.notifier)
        .setSpeed(printerId, mode);
    if (!context.mounted) return;
    final msg = result.messageFor(l10n);
    if (msg != null) {
      ScaffoldMessenger.of(context).snack(msg, clearQueue: true);
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
        constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(
          horizontal: DashSpace.md,
          vertical: DashSpace.md,
        ),
        decoration: BoxDecoration(
          color: t.subCard,
          borderRadius: BorderRadius.circular(DashRadius.lg),
          border: Border.all(color: t.subCardBorder),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            busy
                ? _btnSpinner
                : Icon(Icons.speed, size: DashIcon.md, color: t.textSecondary),
            const SizedBox(width: DashSpace.sm),
            Text(label, style: t.bodyBold.copyWith(color: t.textPrimary)),
            Icon(
              Icons.arrow_drop_down,
              size: DashIcon.md,
              color: t.textSecondary,
            ),
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
