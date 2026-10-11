part of 'printer_card.dart';

/// Entry point for manual axis movement, shown in the collapsible Details when
/// the printer is idle. Opens [_MovementSheet]. Self-hides when control is
/// forbidden (API key lacks `can_control_printer`).
class _MovementTile extends ConsumerWidget {
  const _MovementTile({required this.printerId, required this.model});

  final int printerId;
  final String? model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forbidden = ref.watch(
      controlRefusedProvider(ControlPermission.control),
    );
    if (forbidden) return const SizedBox.shrink();

    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: DashSpace.md),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: logTag(
          'printer.move',
          InkWell(
            onTap: () => dashSurfaceSheet<void>(
              context,
              builder: (_) =>
                  _MovementSheet(printerId: printerId, model: model),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: DashSpace.lg,
                vertical: DashSpace.md,
              ),
              decoration: BoxDecoration(
                color: t.subCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: t.subCardBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.open_with, size: 18, color: t.textSecondary),
                  const SizedBox(width: DashSpace.md),
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
  const _MovementSheet({required this.printerId, required this.model});

  final int printerId;
  final String? model;

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
      FittedSheetSurface(
        // Scrolls rather than overflows on a short screen or at a large text
        // size.
        child: Flexible(
          child: SingleChildScrollView(
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
                  const SizedBox(height: DashSpace.lg),
                  _StepSelector(
                    id: 'movement.step',
                    label: l10n.ctrlMoveStep,
                    presets: _stepPresets,
                    value: _step,
                    onChanged: (v) => setState(() => _step = v),
                  ),
                  const SizedBox(height: DashSpace.lg),
                  _buildXyPad(t, locked),
                  const SizedBox(height: DashSpace.xl),
                  _buildZRow(t, l10n, locked),
                  const SizedBox(height: DashSpace.xl),
                  Divider(color: t.subCardBorder, height: 1),
                  const SizedBox(height: DashSpace.xl),
                  _StepSelector(
                    id: 'movement.length',
                    label: l10n.ctrlMoveLength,
                    presets: _lengthPresets,
                    value: _length,
                    onChanged: (v) => setState(() => _length = v),
                  ),
                  const SizedBox(height: DashSpace.lg),
                  _buildExtruderRow(t, l10n, locked),
                ],
              ),
            ),
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
        const SizedBox(height: DashSpace.sm),
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
            const SizedBox(width: DashSpace.sm),
            center(),
            const SizedBox(width: DashSpace.sm),
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
        const SizedBox(height: DashSpace.sm),
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

  /// Z up/down pair. The sign each arrow sends is [bedJogDistance]'s; where it
  /// cannot be known the pair is replaced by a note rather than guessed.
  Widget _buildZRow(DashTokens t, AppLocalizations l10n, bool locked) {
    final model = widget.model;
    // Only the A1 family's sign depends on the server, so nothing is fetched
    // for any other printer.
    final convention = bedJogDependsOnServer(model)
        ? ref.watch(bedJogConventionProvider)
        : const AsyncData(BedJogConvention.direct);
    // Null while (re)asking: a value kept from before a reconnect may belong to
    // the server as it was before an in-place upgrade.
    final settled = convention.hasError
        ? BedJogConvention.unknown
        : convention.isLoading
        ? null
        : convention.valueOrNull;
    double? distance(bool up) => settled == null
        ? null
        : bedJogDistance(
            up: up,
            step: _step.toDouble(),
            model: model,
            convention: settled,
          );

    final label = Row(
      children: [
        Icon(Icons.height, size: 16, color: t.textSecondary),
        const SizedBox(width: DashSpace.sm),
        Text(
          isBedSlinger(model) ? l10n.ctrlMoveZToolhead : l10n.ctrlMoveZ,
          style: t.body.copyWith(color: t.textSecondary),
        ),
      ],
    );

    if (settled != null && distance(true) == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label,
          const SizedBox(height: DashSpace.sm),
          Text(
            model == null || model.trim().isEmpty
                ? l10n.ctrlMoveZNoModel
                : l10n.ctrlMoveZUnknownDirection,
            style: t.bodyPlain.copyWith(color: t.textTertiary),
          ),
        ],
      );
    }

    Widget jog(String btn, IconData icon, String text, bool up) {
      final d = distance(up);
      return _JogAction(
        icon: icon,
        label: text,
        busy: _spin == btn,
        enabled: !locked && d != null,
        onTap: () => _send(btn, () => _notifier.bedJog(widget.printerId, d!)),
      );
    }

    return Row(
      children: [
        label,
        const Spacer(),
        jog('z+', Icons.keyboard_arrow_up, l10n.ctrlMoveZUp, true),
        const SizedBox(width: DashSpace.sm),
        jog('z-', Icons.keyboard_arrow_down, l10n.ctrlMoveZDown, false),
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
        const SizedBox(width: DashSpace.md),
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
          spacing: DashSpace.sm,
          runSpacing: DashSpace.sm,
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
          padding: const EdgeInsets.symmetric(
            horizontal: DashSpace.md,
            vertical: DashSpace.sm,
          ),
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
              const SizedBox(width: DashSpace.sm),
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
          padding: const EdgeInsets.symmetric(vertical: DashSpace.md),
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
              const SizedBox(width: DashSpace.sm),
              Text(label, style: t.bodyBold.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
