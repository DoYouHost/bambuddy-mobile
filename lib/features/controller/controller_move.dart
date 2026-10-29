import 'scale_to_fit.dart';
import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/action_outcome.dart';
import '../../core/models/printer_status.dart';
import '../../core/printers/bed_jog.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../dashboard/controls_providers.dart';
import 'controller_controls.dart';
import 'controller_providers.dart';

/// The Move tab: the X/Y pad, Z, extrude and retract, the step and home
/// ([docs/single-printer-controller.md] §2). The rules are the printer card's
/// movement sheet's — the same steps, the same Z direction logic, the same
/// `G28` for home — in a layout that shares the height between its cards and
/// never scrolls. Locked while a print is running, and says so.
class ControllerMove extends ConsumerStatefulWidget {
  const ControllerMove({super.key, required this.printerId});

  final int printerId;

  @override
  ConsumerState<ControllerMove> createState() => _ControllerMoveState();
}

class _ControllerMoveState extends ConsumerState<ControllerMove> {
  /// Shared X/Y/Z jog step (mm).
  static const _stepPresets = [1, 10, 50];

  /// Extrude/retract length (mm), smaller than the jog steps.
  static const _lengthPresets = [5, 10, 25];

  int _step = 10;
  int _length = 10;

  /// Id of the button currently sending, so only it shows a spinner and the rest
  /// of the pad waits. Null when nothing is in flight.
  String? _spin;

  bool get _busy => _spin != null;

  ControlsNotifier get _notifier => ref.read(controlsProvider.notifier);

  Future<void> _send(
    String button,
    Future<ActionOutcome> Function() action, {
    String? successMessage,
  }) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    setState(() => _spin = button);
    final result = await action();
    if (!mounted) return;
    setState(() => _spin = null);
    final msg = result.messageFor(l10n) ?? successMessage;
    if (msg != null) messenger.snack(msg, clearQueue: true);
  }

  @override
  Widget build(BuildContext context) {
    final item = ref.watch(controllerPrinterProvider(widget.printerId)).item;
    final status = item?.status;
    if (item == null || status == null) return const SizedBox.shrink();
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final refused = ref.watch(
      controlRefusedProvider(ControlPermission.control),
    );
    final printing = status.isPrinting;
    final connected = status.connected ?? false;
    final enabled = connected && !printing && !refused && !_busy;
    final model = item.printer.model;
    final dual = status.isDualNozzle(item.printer.nozzleCount);
    final page = controllerPaged(context);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (printing) ...[
          Row(
            children: [
              Icon(
                Icons.lock_outline,
                size: controllerIconSize(context, DashSpace.lg),
                color: t.warningInk,
              ),
              const SizedBox(width: DashSpace.sm),
              Expanded(
                child: Text(
                  l10n.controllerMoveLocked,
                  style: t.bodyBold.copyWith(color: t.warningInk),
                ),
              ),
            ],
          ),
          const SizedBox(height: DashSpace.sm),
        ] else if (refused) ...[
          const ControllerForbidden(),
          const SizedBox(height: DashSpace.sm),
        ],
        if (page)
          _cards(status, model, dual, enabled, l10n, page: true)
        else
          Expanded(child: _cards(status, model, dual, enabled, l10n)),
      ],
    );
    return page ? ControllerPage(child: body) : body;
  }

  Widget _cards(
    PrinterStatus status,
    String? model,
    bool dual,
    bool enabled,
    AppLocalizations l10n, {
    bool page = false,
  }) {
    final cards = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Each card's share of the width is its design width, so both
        // cards are scaled by the same factor and the buttons match.
        Expanded(
          flex: (_padSide + _zWidth).round(),
          child: ControllerCard(
            sections: [
              ControllerSection(
                title: 'X / Y',
                flex: _padSide.round(),
                shrink: page,
                child: _xyPad(enabled, page: page),
              ),
              ControllerSection(
                title: 'Z',
                flex: _zWidth.round(),
                shrink: page,
                child: _zPair(model, enabled, l10n, page: page),
              ),
            ],
            // The step is the pad's and Z's, so it sits under them.
            footer: _stepAndHome(enabled, l10n),
          ),
        ),
        const SizedBox(width: DashSpace.md),
        Expanded(
          flex: _sideWidth.round(),
          child: ControllerCard.single(
            title: l10n.controllerExtruder,
            shrink: page,
            child: _extruder(status, dual, enabled, l10n, page: page),
          ),
        ),
      ],
    );
    // On a page the two cards are as tall as the taller of them.
    return page ? IntrinsicHeight(child: cards) : cards;
  }

  /// Directional X/Y pad: a three-by-three grid filling its section, the
  /// arrows in the cross and the step in use, for feedback, in the middle.
  Widget _xyPad(bool enabled, {bool page = false}) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    Widget arrow(
      String id,
      IconData icon,
      String description, {
      double x = 0,
      double y = 0,
    }) => Expanded(
      child: _JogButton(
        id: 'controller.jog_$id',
        icon: icon,
        description: description,
        tone: t.accent,
        ink: t.accentInk,
        width: double.infinity,
        height: double.infinity,
        busy: _spin == id,
        onTap: enabled
            ? () =>
                  _send(id, () => _notifier.xyJog(widget.printerId, x: x, y: y))
            : null,
      ),
    );
    const gap = SizedBox(width: DashSpace.sm, height: DashSpace.sm);
    const blank = Expanded(child: SizedBox.shrink());
    final step = _step.toDouble();
    Widget row(List<Widget> cells) {
      final line = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [cells[0], gap, cells[1], gap, cells[2]],
      );
      // On a page nothing hands the pad a height: a row is a button tall.
      return page
          ? SizedBox(height: _JogButton.size, child: line)
          : Expanded(child: line);
    }

    return Column(
      children: [
        row([
          blank,
          arrow(
            'y_plus',
            Icons.arrow_upward_rounded,
            l10n.ctrlMoveAxisPlus('Y'),
            y: step,
          ),
          blank,
        ]),
        gap,
        row([
          arrow(
            'x_minus',
            Icons.arrow_back_rounded,
            l10n.ctrlMoveAxisMinus('X'),
            x: -step,
          ),
          Expanded(
            child: Center(
              child: Text(
                '$_step',
                style: t.monoTitle.copyWith(color: t.textTertiary),
              ),
            ),
          ),
          arrow(
            'x_plus',
            Icons.arrow_forward_rounded,
            l10n.ctrlMoveAxisPlus('X'),
            x: step,
          ),
        ]),
        gap,
        row([
          blank,
          arrow(
            'y_minus',
            Icons.arrow_downward_rounded,
            l10n.ctrlMoveAxisMinus('Y'),
            y: -step,
          ),
          blank,
        ]),
      ],
    );
  }

  /// Z up and down. The sign each arrow sends is [bedJogDistance]'s; where it
  /// cannot be known the pair is replaced by a note, never guessed — a wrong
  /// sign drives the plate into the nozzle.
  Widget _zPair(
    String? model,
    bool enabled,
    AppLocalizations l10n, {
    bool page = false,
  }) {
    final t = DashTokens.of(context);
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
        : convention.value;
    double? distance(bool up) => settled == null
        ? null
        : bedJogDistance(
            up: up,
            step: _step.toDouble(),
            model: model,
            convention: settled,
          );
    if (settled != null && distance(true) == null) {
      return Text(
        model == null || model.trim().isEmpty
            ? l10n.ctrlMoveZNoModel
            : l10n.ctrlMoveZUnknownDirection,
        style: t.bodyPlain.copyWith(color: t.textTertiary),
        maxLines: 12,
        overflow: TextOverflow.ellipsis,
      );
    }
    Widget button(String id, IconData icon, String label, bool up) {
      final d = distance(up);
      return _JogButton(
        id: 'controller.jog_$id',
        icon: icon,
        label: label,
        tone: t.accent,
        ink: t.accentInk,
        width: double.infinity,
        height: double.infinity,
        busy: _spin == id,
        onTap: enabled && d != null
            ? () => _send(id, () => _notifier.bedJog(widget.printerId, d))
            : null,
      );
    }

    // On a page the pair is as tall as the pad beside it.
    Widget tall(Widget child) => page
        ? SizedBox(height: _zHeight, child: child)
        : Expanded(child: child);
    return Column(
      children: [
        tall(
          button(
            'z_up',
            Icons.vertical_align_top_rounded,
            l10n.ctrlMoveZUp,
            true,
          ),
        ),
        const SizedBox(height: DashSpace.sm),
        tall(
          button(
            'z_down',
            Icons.vertical_align_bottom_rounded,
            l10n.ctrlMoveZDown,
            false,
          ),
        ),
      ],
    );
  }

  /// Extrude and retract. Neither takes a nozzle: the server sends the move to
  /// whichever extruder is active, so on two heads the choice of nozzle is made
  /// first (`select-extruder`) and the jog follows it.
  Widget _extruder(
    PrinterStatus status,
    bool dual,
    bool enabled,
    AppLocalizations l10n, {
    bool page = false,
  }) {
    final t = DashTokens.of(context);
    Widget tall(Widget child) => page
        ? SizedBox(height: _JogButton.size, child: child)
        : Expanded(child: child);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (dual) ...[
          _NozzleChoice(
            printerId: widget.printerId,
            status: status,
            enabled: enabled,
          ),
          const SizedBox(height: DashSpace.sm),
        ],
        ControllerChoices(
          id: 'controller.length_preset',
          selectLabel: l10n.ctrlMoveLength,
          labels: [for (final p in _lengthPresets) l10n.ctrlMoveMm(p)],
          selected: _lengthPresets.indexOf(_length),
          enabled: enabled,
          onChanged: (i) => setState(() => _length = _lengthPresets[i]),
        ),
        const SizedBox(height: DashSpace.md),
        tall(
          _JogButton(
            id: 'controller.jog_extrude',
            icon: Icons.arrow_downward_rounded,
            label: l10n.ctrlMoveExtrude,
            tone: t.accent,
            ink: t.accentInk,
            width: double.infinity,
            height: double.infinity,
            busy: _spin == 'extrude',
            onTap: enabled
                ? () => _send(
                    'extrude',
                    () => _notifier.extruderJog(
                      widget.printerId,
                      _length.toDouble(),
                    ),
                  )
                : null,
          ),
        ),
        const SizedBox(height: DashSpace.sm),
        tall(
          _JogButton(
            id: 'controller.jog_retract',
            icon: Icons.arrow_upward_rounded,
            label: l10n.ctrlMoveRetract,
            tone: t.accent,
            ink: t.accentInk,
            width: double.infinity,
            height: double.infinity,
            busy: _spin == 'retract',
            onTap: enabled
                ? () => _send(
                    'retract',
                    () => _notifier.extruderJog(
                      widget.printerId,
                      -_length.toDouble(),
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }

  /// The step presets and Home, in one row across the axes card, split the way
  /// the sections above it are: the presets under the pad, Home under Z, so
  /// their edges line up with the pad's and Z's.
  Widget _stepAndHome(bool enabled, AppLocalizations l10n) {
    final t = DashTokens.of(context);
    return SizedBox(
      height: _JogButton.size,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: _padSide.round(),
            child: ControllerChoices(
              id: 'controller.step_preset',
              selectLabel: l10n.ctrlMoveStep,
              labels: [for (final p in _stepPresets) l10n.ctrlMoveMm(p)],
              selected: _stepPresets.indexOf(_step),
              enabled: enabled,
              onChanged: (i) => setState(() => _step = _stepPresets[i]),
            ),
          ),
          // The gap the card puts between its sections.
          const SizedBox(width: DashSpace.xl),
          Expanded(
            flex: _zWidth.round(),
            child: _JogButton(
              id: 'controller.home',
              icon: Icons.home_rounded,
              label: l10n.ctrlMoveHome,
              tone: t.accent,
              ink: t.accentInk,
              busy: _spin == 'home',
              // A home has no reliable "done" signal (the web is
              // fire-and-forget too), so the answer is a toast, not a lock
              // waiting on it.
              onTap: enabled
                  ? () => _send(
                      'home',
                      () => _notifier.homeAxes(widget.printerId),
                      successMessage: l10n.ctrlMoveHomeStarted,
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  /// The sizes each card's content is laid out at before it is scaled to fit its
  /// room — up on a big screen, down on a small one.
  static const _padSide = 184.0;
  static const _zWidth = 136.0;

  /// The pad on a page: three buttons and the gaps between them; Z's two buttons
  /// share the same height.
  static const _padHeight = 3 * _JogButton.size + 2 * DashSpace.sm;
  static const _zHeight = (_padHeight - DashSpace.sm) / 2;

  /// The extruder and step cards: three mm presets side by side.
  static const _sideWidth = 168.0;
}

/// A jog or action button: icon only for the pad, icon and label otherwise. A
/// null [onTap] leaves it disabled; the spinner shows while it is the one in
/// flight.
class _JogButton extends StatelessWidget {
  const _JogButton({
    required this.id,
    required this.icon,
    required this.busy,
    required this.onTap,
    this.label,
    this.description,
    this.width,
    this.height,
    this.tone,
    this.ink,
  });

  static const size = controllerButtonHeight;

  final String id;
  final IconData icon;
  final String? label;

  /// What an icon alone does, for a screen reader: a `FilledButton` takes its
  /// name from its child, not from a `Tooltip` around it.
  final String? description;
  final bool busy;
  final VoidCallback? onTap;

  /// Defaults to a square, for an icon alone.
  final double? width;

  /// Defaults to [size].
  final double? height;

  /// What the button moves, as a colour ([controllerButtonStyle]).
  final Color? tone;
  final Color? ink;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return logTag(
      id,
      FilledButton(
        style: controllerButtonStyle(
          t,
          minimumSize: Size(width ?? size, height ?? size),
          padding: EdgeInsets.zero,
          tone: tone,
          ink: ink,
        ),
        onPressed: busy ? null : onTap,
        child: busy
            ? const DashSpinner()
            : label == null
            ? Icon(icon, size: DashIcon.xl, semanticLabel: description)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 24),
                  const SizedBox(width: DashSpace.sm),
                  Flexible(
                    child: Text(
                      label!,
                      style: t.bodyBold,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Which nozzle Extrude and Retract act on, on a printer with two. Plain `nozzle`
/// is the left head (hardware index 1) and `nozzle_2` the right (0), numbered 1
/// and 2 as on the Heat tab.
class _NozzleChoice extends ConsumerWidget {
  const _NozzleChoice({
    required this.printerId,
    required this.status,
    required this.enabled,
  });

  final int printerId;
  final PrinterStatus status;
  final bool enabled;

  static const _width = _ControllerMoveState._sideWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final active = status.activeExtruder ?? 0;
    final busy = ref.watch(
      controlsProvider.select(
        (s) => s.pendingFor(printerId).isBusy(ControlAction.extruder),
      ),
    );
    final radius = BorderRadius.circular(DashSpace.md);
    // (label number, hardware index)
    const heads = [('1', 1), ('2', 0)];
    return SizedBox(
      width: _width,
      child: Row(
        children: [
          for (final (i, head) in heads.indexed) ...[
            if (i > 0) const SizedBox(width: DashSpace.sm),
            Expanded(
              child: logTag(
                'controller.jog_nozzle',
                Material(
                  color: active == head.$2
                      ? t.accent.withValues(alpha: 0.16)
                      : t.subCard,
                  shape: RoundedRectangleBorder(
                    borderRadius: radius,
                    side: BorderSide(
                      color: active == head.$2
                          ? t.accent.withValues(alpha: 0.4)
                          : t.subCardBorder,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: radius,
                    onTap: enabled && !busy && active != head.$2
                        ? () => _select(context, ref, head.$2)
                        : null,
                    child: Container(
                      height: _JogButton.size,
                      alignment: Alignment.center,
                      child: Text(
                        l10n.tempNozzleNumbered(head.$1),
                        style: active == head.$2
                            ? t.bodyBold.copyWith(color: t.accentInk)
                            : t.bodyBold,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),
                selected: active == head.$2,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _select(BuildContext context, WidgetRef ref, int index) async {
    final result = await ref
        .read(controlsProvider.notifier)
        .setExtruder(printerId, index);
    if (!context.mounted) return;
    final msg = result.messageFor(AppLocalizations.of(context));
    if (msg != null) {
      ScaffoldMessenger.of(context).snack(msg, clearQueue: true);
    }
  }
}
