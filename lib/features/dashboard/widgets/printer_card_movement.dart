part of 'printer_card.dart';

/// Entry point for manual axis movement, shown in the collapsible Details when
/// the printer is idle. Opens [_MovementSheet]. Self-hides when control is
/// forbidden (API key lacks `can_control_printer`).
class _MovementTile extends ConsumerWidget {
  const _MovementTile({required this.printerId});

  final int printerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forbidden = ref.watch(
      controlRefusedProvider(ControlPermission.control),
    );
    if (forbidden) return const SizedBox.shrink();

    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: logTag(
          'printer.move',
          InkWell(
            onTap: () => dashSurfaceSheet<void>(
              context,
              builder: (_) => _MovementSheet(printerId: printerId),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: t.subCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: t.subCardBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.open_with, size: 18, color: t.textSecondary),
                  const SizedBox(width: 10),
                  Text(l10n.ctrlMove, style: t.titleSm),
                  const Spacer(),
                  Icon(Icons.chevron_right, size: 18, color: t.textTertiary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Manual movement panel: home, an X/Y jog pad, a Z (bed-gap) up/down pair and
/// extrude/retract — all relative jogs. Unlike the temp/fan sheets it stays open
/// (you jog repeatedly). Commands are momentary (no optimistic overlay); while
/// one is in flight the whole pad locks and the pressed button spins.
class _MovementSheet extends ConsumerStatefulWidget {
  const _MovementSheet({required this.printerId});

  final int printerId;

  @override
  ConsumerState<_MovementSheet> createState() => _MovementSheetState();
}

class _MovementSheetState extends ConsumerState<_MovementSheet> {
  /// Shared X/Y/Z jog step (mm).
  static const _stepPresets = [1, 10, 50];

  /// Extrude/retract length (mm) — smaller than the XY/Z steps.
  static const _lengthPresets = [5, 10, 25];

  int _step = 10;
  int _length = 10;
  bool _busy = false;

  /// Id of the button currently sending, so only it shows a spinner.
  String? _spin;

  Future<void> _send(
    String btn,
    Future<ActionOutcome> Function() action,
  ) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _spin = btn;
    });
    final result = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _spin = null;
    });
    final msg = result.messageFor(l10n);
    if (msg != null) {
      messenger.snack(msg, clearQueue: true);
    }
  }

  ControlsNotifier get _notifier => ref.read(controlsProvider.notifier);

  /// Fire the full auto-home (`G28`) and confirm with a toast. A manual home has
  /// no reliable "done" signal — bambuddy's own web UI is fire-and-forget too, so
  /// we don't lock the button waiting on completion (see the release-notes note).
  Future<void> _home() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _spin = 'home';
    });
    final result = await _notifier.homeAxes(widget.printerId);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _spin = null;
    });
    final msg = result.messageFor(l10n) ?? l10n.ctrlMoveHomeStarted;
    messenger.snack(msg, clearQueue: true);
  }

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final locked = _busy;

    return logTag(
      'sheet.movement',
      SafeArea(
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
                        Text(l10n.ctrlMove, style: t.titleLg),
                        const Spacer(),
                        _JogAction(
                          icon: Icons.home_outlined,
                          label: l10n.ctrlMoveHome,
                          busy: _spin == 'home',
                          enabled: !locked,
                          onTap: _home,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _StepSelector(
                      id: 'movement.step',
                      label: l10n.ctrlMoveStep,
                      presets: _stepPresets,
                      value: _step,
                      onChanged: (v) => setState(() => _step = v),
                    ),
                    const SizedBox(height: 18),
                    _buildXyPad(t, locked),
                    const SizedBox(height: 20),
                    _buildZRow(t, l10n, locked),
                    const SizedBox(height: 20),
                    Divider(color: t.subCardBorder, height: 1),
                    const SizedBox(height: 20),
                    _StepSelector(
                      id: 'movement.length',
                      label: l10n.ctrlMoveLength,
                      presets: _lengthPresets,
                      value: _length,
                      onChanged: (v) => setState(() => _length = v),
                    ),
                    const SizedBox(height: 14),
                    _buildExtruderRow(t, l10n, locked),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Directional X/Y pad. The center cell shows the active step for feedback.
  Widget _buildXyPad(DashTokens t, bool locked) {
    Widget spacer() => const SizedBox(width: 56, height: 56);

    Widget center() => SizedBox(
      width: 56,
      height: 56,
      child: Center(
        child: Text(
          '$_step',
          style: t.monoTitle.copyWith(color: t.textTertiary),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            spacer(),
            _JogButton(
              icon: Icons.keyboard_arrow_up,
              busy: _spin == 'y+',
              enabled: !locked,
              onTap: () => _send(
                'y+',
                () => _notifier.xyJog(widget.printerId, y: _step.toDouble()),
              ),
            ),
            spacer(),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _JogButton(
              icon: Icons.keyboard_arrow_left,
              busy: _spin == 'x-',
              enabled: !locked,
              onTap: () => _send(
                'x-',
                () => _notifier.xyJog(widget.printerId, x: -_step.toDouble()),
              ),
            ),
            const SizedBox(width: 8),
            center(),
            const SizedBox(width: 8),
            _JogButton(
              icon: Icons.keyboard_arrow_right,
              busy: _spin == 'x+',
              enabled: !locked,
              onTap: () => _send(
                'x+',
                () => _notifier.xyJog(widget.printerId, x: _step.toDouble()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            spacer(),
            _JogButton(
              icon: Icons.keyboard_arrow_down,
              busy: _spin == 'y-',
              enabled: !locked,
              onTap: () => _send(
                'y-',
                () => _notifier.xyJog(widget.printerId, y: -_step.toDouble()),
              ),
            ),
            spacer(),
          ],
        ),
      ],
    );
  }

  /// Z (bed-gap) up/down pair. "Up" decreases the gap → negative distance; the
  /// server flips the sign per model so the direction stays intuitive.
  Widget _buildZRow(DashTokens t, AppLocalizations l10n, bool locked) {
    return Row(
      children: [
        Icon(Icons.height, size: 16, color: t.textSecondary),
        const SizedBox(width: 8),
        Text(l10n.ctrlMoveZ, style: t.body.copyWith(color: t.textSecondary)),
        const Spacer(),
        _JogAction(
          icon: Icons.keyboard_arrow_up,
          label: l10n.ctrlMoveZUp,
          busy: _spin == 'z+',
          enabled: !locked,
          onTap: () => _send(
            'z+',
            () => _notifier.bedJog(widget.printerId, -_step.toDouble()),
          ),
        ),
        const SizedBox(width: 8),
        _JogAction(
          icon: Icons.keyboard_arrow_down,
          label: l10n.ctrlMoveZDown,
          busy: _spin == 'z-',
          enabled: !locked,
          onTap: () => _send(
            'z-',
            () => _notifier.bedJog(widget.printerId, _step.toDouble()),
          ),
        ),
      ],
    );
  }

  Widget _buildExtruderRow(DashTokens t, AppLocalizations l10n, bool locked) {
    return Row(
      children: [
        Expanded(
          child: _JogWideButton(
            icon: Icons.arrow_upward,
            label: l10n.ctrlMoveRetract,
            busy: _spin == 'retract',
            enabled: !locked,
            onTap: () => _send(
              'retract',
              () =>
                  _notifier.extruderJog(widget.printerId, -_length.toDouble()),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _JogWideButton(
            icon: Icons.arrow_downward,
            label: l10n.ctrlMoveExtrude,
            busy: _spin == 'extrude',
            enabled: !locked,
            onTap: () => _send(
              'extrude',
              () => _notifier.extruderJog(widget.printerId, _length.toDouble()),
            ),
          ),
        ),
      ],
    );
  }
}

/// Horizontal preset selector ("Step"/"Length": label + mm chips).
class _StepSelector extends StatelessWidget {
  const _StepSelector({
    required this.id,
    required this.label,
    required this.presets,
    required this.value,
    required this.onChanged,
  });

  /// Diagnostic identifier for this row's chips. The movement sheet builds two
  /// of these — the move step and the extrude length — and one shared tag could
  /// not say which of them the user changed.
  final String id;

  final String label;
  final List<int> presets;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    return Row(
      children: [
        Text(label, style: t.body.copyWith(color: t.textSecondary)),
        const Spacer(),
        Wrap(
          spacing: 8,
          children: [
            for (final p in presets)
              _PresetChip(
                label: l10n.ctrlMoveMm(p),
                id: '${id}_preset',
                selected: value == p,
                onTap: () => onChanged(p),
              ),
          ],
        ),
      ],
    );
  }
}

/// Square jog button for the X/Y pad (icon only). Spinner + lock when busy.
class _JogButton extends StatelessWidget {
  const _JogButton({
    required this.icon,
    required this.busy,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final fg = enabled ? t.textPrimary : t.textTertiary;
    return Material(
      color: t.subCard,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.subCardBorder),
          ),
          alignment: Alignment.center,
          child: busy ? const DashSpinner() : Icon(icon, size: 26, color: fg),
        ),
      ),
    );
  }
}

/// Compact labeled jog button (home, Z up/down): icon + short label pill.
class _JogAction extends StatelessWidget {
  const _JogAction({
    required this.icon,
    required this.label,
    required this.busy,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final fg = enabled ? t.textPrimary : t.textTertiary;
    return Material(
      color: t.subCard,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.subCardBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              busy
                  ? const DashSpinner(size: 16)
                  : Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(label, style: t.bodyBold.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-width jog button used for extrude/retract: centered icon + label.
class _JogWideButton extends StatelessWidget {
  const _JogWideButton({
    required this.icon,
    required this.label,
    required this.busy,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final fg = enabled ? t.textPrimary : t.textTertiary;
    return Material(
      color: t.subCard,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.subCardBorder),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              busy
                  ? const DashSpinner(size: 16)
                  : Icon(icon, size: 18, color: fg),
              const SizedBox(width: 8),
              Text(label, style: t.bodyBold.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
