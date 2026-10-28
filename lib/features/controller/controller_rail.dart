import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/dash_theme.dart';
import '../../data/printers_repository.dart';
import '../../l10n/app_localizations.dart';
import '../dashboard/widgets/printer_state_pill.dart';
import '../wall/wall_providers.dart';
import 'controller_faults.dart';
import 'controller_picker.dart';
import 'controller_screen.dart';
import 'scale_to_fit.dart';

/// The width of the collapsed rail: a column of 48 dp touch targets.
const controllerRailWidth = 56.0;

/// The width of the open panel, which lies over the screen instead of pushing it.
const _panelWidth = 252.0;

/// Tall enough for a finger at any text size: the rail is outside the scaled body.
const _item = 48.0;

IconData controllerTabIcon(ControllerTab tab) => switch (tab) {
  ControllerTab.overview => Icons.dashboard_outlined,
  ControllerTab.heat => Icons.thermostat_outlined,
  ControllerTab.move => Icons.open_with_rounded,
  ControllerTab.filament => Icons.album_outlined,
  ControllerTab.prints => Icons.print_outlined,
  ControllerTab.settings => Icons.settings_outlined,
};

/// The collapsed rail: the way in to the panel and one icon per tab. The way out
/// is in the open panel, and the system Back.
class ControllerRail extends StatelessWidget {
  const ControllerRail({
    super.key,
    required this.tab,
    required this.onTab,
    required this.onOpen,
  });

  final ControllerTab tab;
  final ValueChanged<ControllerTab> onTab;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    return Container(
      width: controllerRailWidth,
      decoration: BoxDecoration(
        color: t.subCard,
        borderRadius: BorderRadius.circular(DashSpace.md + DashSpace.xs),
        border: Border.all(color: t.subCardBorder),
      ),
      child: Column(
        children: [
          logTag(
            'controller.rail_open',
            Tooltip(
              message: material.openAppDrawerTooltip,
              child: InkWell(
                borderRadius: BorderRadius.circular(DashSpace.md),
                onTap: onOpen,
                child: SizedBox.square(
                  dimension: _item,
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: t.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final candidate in ControllerTab.values)
                    logTag(
                      candidate.logId,
                      Tooltip(
                        message: candidate.label(l10n),
                        child: _RailIcon(
                          icon: controllerTabIcon(candidate),
                          selected: candidate == tab,
                          onTap: () => onTab(candidate),
                        ),
                      ),
                      selected: candidate == tab,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailIcon extends StatelessWidget {
  const _RailIcon({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final radius = BorderRadius.circular(DashSpace.md);
    return Material(
      color: selected ? t.accent.withValues(alpha: 0.16) : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: selected
            ? BorderSide(color: t.accent.withValues(alpha: 0.4))
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: SizedBox.square(
          dimension: _item,
          child: Icon(icon, color: selected ? t.accentInk : t.textSecondary),
        ),
      ),
    );
  }
}

/// The open rail: the printer with its state, the tabs with their names and the
/// way out. A panel over the screen, closed by its arrow or by a touch outside it.
class ControllerRailPanel extends ConsumerWidget {
  const ControllerRailPanel({
    super.key,
    required this.item,
    required this.offline,
    required this.tab,
    required this.onTab,
    required this.onClose,
    required this.onExit,
  });

  final PrinterWithStatus item;
  final bool offline;
  final ControllerTab tab;
  final ValueChanged<ControllerTab> onTab;
  final VoidCallback onClose;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    final printer = item.printer;
    final several = ref.watch(
      wallRosterProvider.select((r) => (r?.length ?? 0) > 1),
    );
    final name = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          printer.name,
          style: t.titleMd,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (printer.model != null && !controllerLargeText(context))
          Text(
            printer.model!,
            style: t.labelSoft,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
    return Material(
      color: t.overlaySurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DashSpace.md + DashSpace.xs),
        side: BorderSide(color: t.subCardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        // Wider at a large text size, where the same words need more room.
        width: controllerLargeText(context) ? _panelWidth + 72 : _panelWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                logTag(
                  'controller.rail_close',
                  Tooltip(
                    message: material.closeButtonTooltip,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(DashSpace.md),
                      onTap: onClose,
                      child: SizedBox.square(
                        dimension: _item,
                        child: Icon(
                          Icons.chevron_left_rounded,
                          color: t.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: several
                      ? logTag(
                          'controller.switch_printer',
                          Tooltip(
                            message: l10n.controllerSwitchPrinter,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(DashSpace.md),
                              onTap: () =>
                                  openController(context, ref, replace: true),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: _item,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(child: name),
                                    Icon(
                                      Icons.expand_more_rounded,
                                      size: controllerIconSize(
                                        context,
                                        DashSpace.lg,
                                      ),
                                      color: t.textTertiary,
                                    ),
                                    const SizedBox(width: DashSpace.sm),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )
                      : ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: _item),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: name,
                          ),
                        ),
                ),
                logTag(
                  'controller.panel_exit',
                  Tooltip(
                    message: l10n.controllerExit,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(DashSpace.md),
                      onTap: onExit,
                      child: SizedBox.square(
                        dimension: _item,
                        child: Icon(Icons.logout_rounded, color: t.textPrimary),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DashSpace.md,
                0,
                DashSpace.md,
                DashSpace.sm,
              ),
              child: Wrap(
                spacing: DashSpace.sm,
                runSpacing: DashSpace.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  printerStatePill(t, l10n, item.status, offline: offline),
                  ControllerFaultChip(printerId: printer.id),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: DashSpace.xs),
                child: Column(
                  children: [
                    for (final candidate in ControllerTab.values)
                      logTag(
                        'controller.panel_${candidate.name}',
                        _PanelTab(
                          icon: controllerTabIcon(candidate),
                          label: candidate.label(l10n),
                          selected: candidate == tab,
                          onTap: () => onTab(candidate),
                        ),
                        selected: candidate == tab,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelTab extends StatelessWidget {
  const _PanelTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final radius = BorderRadius.circular(DashSpace.md);
    return Material(
      color: selected ? t.accent.withValues(alpha: 0.16) : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: selected
            ? BorderSide(color: t.accent.withValues(alpha: 0.4))
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: SizedBox(
          height: _item,
          child: Row(
            children: [
              SizedBox.square(
                dimension: _item,
                child: Icon(
                  icon,
                  color: selected ? t.accentInk : t.textSecondary,
                ),
              ),
              Expanded(
                child: Text(
                  label,
                  style: selected
                      ? t.bodyBold.copyWith(color: t.accentInk)
                      : t.bodyBold,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
