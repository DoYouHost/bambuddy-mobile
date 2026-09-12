part of 'printer_card.dart';

/// The card reduced to one row: name, print progress, status, and the button
/// that brings the rest back.
///
/// What the full card would show in a panel of its own — an active fault, a
/// plate waiting to be cleared — takes the place of the printer glyph instead,
/// in that panel's colour. It costs the name no width, which on a 360 dp screen
/// it has little of beside the chip.
///
/// The first line is the full card's own [_HeaderLine], so toggling moves
/// nothing on it; the progress bar hangs under the name instead. A fault wins when both apply; the plate
/// prompt is still there once the card is expanded.
class _CollapsedCard extends ConsumerWidget {
  const _CollapsedCard({
    required this.name,
    required this.status,
    required this.offline,
    required this.onExpand,
  });

  final String name;
  final PrinterStatus? status;

  /// The debounced reading the full card collapses on (`PrinterCard._offline`),
  /// so both looks agree on when a printer counts as gone.
  final bool offline;

  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final status = this.status;
    final connected = status?.connected ?? false;
    final printing = !offline && (status?.isPrinting ?? false);
    final progress = status?.progress;
    final showPercent =
        printing && progress != null && _preparingStage(status!) == null;

    return _CardShell(
      tokens: t,
      child: _HeaderLine(
        leading: _leadIcon(context, ref, t, l10n),
        name: name,
        afterName: showPercent
            ? Text('${progress.toStringAsFixed(0)}%', style: t.monoValue)
            : null,
        belowName: printing
            ? Padding(
                padding: const EdgeInsets.only(top: 2),
                child: _PrintProgressBar(status: status!, height: 3),
              )
            : null,
        trailing: [
          _StateChip(
            label: offline ? l10n.statusOffline : _stateChipLabel(l10n, status),
            offline: offline || !connected,
          ),
          if (onExpand != null) ...[
            const SizedBox(width: 8),
            _CollapseToggleButton(collapsed: true, onPressed: onExpand!),
          ],
        ],
      ),
    );
  }

  Widget _leadIcon(
    BuildContext context,
    WidgetRef ref,
    DashTokens t,
    AppLocalizations l10n,
  ) {
    final status = this.status;
    // The offline card shows no fault panel either: the last frame's errors
    // are as stale as its temperatures.
    final hmsErrors = offline
        ? const <HmsError>[]
        : displayableHmsErrors(status, describe: HmsCatalog.instance.describe);
    if (hmsErrors.isNotEmpty) {
      return Tooltip(
        message: l10n.hmsErrorsCount(hmsErrors.length),
        child: _IconSquare(
          tokens: t,
          icon: Icons.warning_amber_rounded,
          tint: Theme.of(context).colorScheme.error,
        ),
      );
    }
    if (plateClearOffer(ref, status) != ControlOffer.hidden) {
      return Tooltip(
        message: l10n.plateClearBadge,
        child: _IconSquare(
          tokens: t,
          icon: Icons.layers_clear_outlined,
          tint: t.accentBlue,
        ),
      );
    }
    return _IconSquare(
      tokens: t,
      offline: offline || !(status?.connected ?? false),
    );
  }
}

/// The chevron in the card's top-right corner. It sits in the same place in
/// both looks, so the button that expanded a card is under the finger to
/// collapse it again.
class _CollapseToggleButton extends StatelessWidget {
  const _CollapseToggleButton({
    required this.collapsed,
    required this.onPressed,
  });

  final bool collapsed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _HeaderIconButton(
      id: collapsed ? 'printer.expand' : 'printer.collapse',
      icon: collapsed ? Icons.expand_more : Icons.expand_less,
      tooltip: collapsed ? l10n.printerCardExpand : l10n.printerCardCollapse,
      onPressed: onPressed,
    );
  }
}
