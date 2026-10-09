import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:app_util/app_util.dart';
import 'package:flutter/material.dart';

import '../../core/models/printer_location.dart';
import '../../core/theme/dash_theme.dart';
import '../../data/printers_repository.dart';
import '../../l10n/app_localizations.dart';
import '../dashboard/dashboard_filters.dart';
import 'printer_location_icons.dart';

/// The colour stripe on a [LocationIconTile].
const _stripeWidth = 4.0;

/// The location's icon on a tile, with its colour as a stripe down the left
/// edge — the web page's `LocationIcon`.
class LocationIconTile extends StatelessWidget {
  const LocationIconTile({super.key, required this.location});

  final PrinterLocation location;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final stripe = colorFromHex(location.color);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 44,
        height: 44,
        color: t.subCard,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              printerLocationIcon(location.icon),
              size: 24,
              color: t.textSecondary,
            ),
            if (stripe != null)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: _stripeWidth,
                child: ColoredBox(color: stripe),
              ),
          ],
        ),
      ),
    );
  }
}

/// One location: the header (expand, or tick in selection mode) and, when
/// [expanded], the printers in it.
class LocationCard extends StatelessWidget {
  const LocationCard({
    super.key,
    required this.location,
    required this.expanded,
    required this.selecting,
    required this.picked,
    required this.canEdit,
    required this.busy,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.children,
  });

  final PrinterLocation location;
  final bool expanded;
  final bool selecting;
  final bool picked;
  final bool canEdit;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// The printers shown under an expanded header.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DashSpace.gutter,
        vertical: DashSpace.xs,
      ),
      child: DecoratedBox(
        decoration: t.cardBox,
        child: Padding(
          padding: const EdgeInsets.all(DashSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: logTag(
                      'locations.row',
                      selected: selecting ? picked : null,
                      expanded: selecting ? null : expanded,
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: onTap,
                        child: Row(
                          children: [
                            Icon(
                              selecting
                                  ? (picked
                                        ? Icons.check_box
                                        : Icons.check_box_outline_blank)
                                  : (expanded
                                        ? Icons.expand_less
                                        : Icons.expand_more),
                              color: picked && selecting
                                  ? t.accentGreen
                                  : t.textSecondary,
                            ),
                            const SizedBox(width: DashSpace.sm),
                            LocationIconTile(location: location),
                            const SizedBox(width: DashSpace.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    location.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.titleSm,
                                  ),
                                  Text(
                                    l10n.printerLocationsPrinterCount(
                                      location.printerCount,
                                    ),
                                    style: t.bodyPlain,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (canEdit && !selecting) ...[
                    IconButton(
                      tooltip: l10n.printerLocationsEditTitle,
                      onPressed: busy ? null : onEdit,
                      icon: const Icon(Icons.edit_outlined),
                    ).tagged('locations.edit'),
                    IconButton(
                      tooltip: l10n.printerLocationsDeleteTitle,
                      onPressed: busy ? null : onDelete,
                      color: t.dangerInk,
                      icon: const Icon(Icons.delete_outline),
                    ).tagged('locations.delete'),
                  ],
                ],
              ),
              if (expanded) ...[
                const Divider(height: DashSpace.xl),
                if (children.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: DashSpace.lg),
                    child: Text(
                      l10n.printerLocationsNoPrinters,
                      textAlign: TextAlign.center,
                      style: t.bodyPlain.copyWith(color: t.textSecondary),
                    ),
                  )
                else
                  ...children,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One printer under a location, or among those without one.
class LocationPrinterRow extends StatelessWidget {
  const LocationPrinterRow({
    super.key,
    required this.printer,
    required this.picked,
    required this.canEdit,
    required this.busy,
    required this.onToggle,
    required this.onMove,
    this.onRemove,
  });

  final PrinterWithStatus printer;
  final bool picked;
  final bool canEdit;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onMove;

  /// Null among the printers that have no location to leave.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final bucket = classifyPrinter(printer.status);
    final (label, accent, ink) = switch (bucket) {
      PrinterStatusBucket.printing => (
        l10n.statusPrinting,
        t.accentOrange,
        t.accentOrangeInk,
      ),
      PrinterStatusBucket.paused => (
        l10n.statusPaused,
        t.warning,
        t.warningInk,
      ),
      PrinterStatusBucket.finished => (
        l10n.statusFinished,
        t.accentGreen,
        t.accentGreenInk,
      ),
      PrinterStatusBucket.error => (
        l10n.statusErrorFilter,
        t.danger,
        t.dangerInk,
      ),
      PrinterStatusBucket.offline => (
        l10n.statusOfflineFilter,
        t.textTertiary,
        t.textSecondary,
      ),
      _ => (l10n.statusIdle, t.textSecondary, t.textSecondary),
    };
    final model = printer.printer.model;
    return Padding(
      padding: const EdgeInsets.only(bottom: DashSpace.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: picked ? t.accentGreen.withValues(alpha: 0.1) : t.subCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: picked
                ? t.accentGreen.withValues(alpha: 0.3)
                : t.subCardBorder,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DashSpace.sm,
            vertical: DashSpace.xs,
          ),
          child: Row(
            children: [
              if (canEdit)
                IconButton(
                  tooltip: l10n.printerLocationsSelectPrinter,
                  onPressed: onToggle,
                  isSelected: picked,
                  icon: const Icon(Icons.check_box_outline_blank),
                  selectedIcon: Icon(Icons.check_box, color: t.accentGreen),
                ).tagged('locations.printer_select', selected: picked),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      printer.printer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyStrong,
                    ),
                    if (model != null && model.isNotEmpty)
                      Text(
                        model,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodyPlain,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: DashSpace.sm),
              DashPill(
                label: label,
                accent: accent,
                accentInk: ink,
                leadingDot: true,
                dense: true,
              ),
              if (canEdit)
                IconButton(
                  tooltip: l10n.printerLocationsMove,
                  onPressed: busy ? null : onMove,
                  icon: const Icon(Icons.drive_file_move_outline),
                ).tagged('locations.printer_move'),
              if (canEdit && onRemove != null)
                IconButton(
                  tooltip: l10n.printerLocationsRemoveFromLocation,
                  onPressed: busy ? null : onRemove,
                  color: t.dangerInk,
                  icon: const Icon(Icons.person_remove_outlined),
                ).tagged('locations.printer_remove'),
            ],
          ),
        ),
      ),
    );
  }
}

/// The bar that appears once something is ticked: how many, the action, and a
/// way out.
class LocationSelectionBar extends StatelessWidget {
  const LocationSelectionBar({
    super.key,
    required this.count,
    required this.actionLabel,
    required this.actionIcon,
    required this.id,
    required this.cancelId,
    required this.busy,
    required this.onAction,
    required this.onCancel,
    this.destructive = false,
  });

  final int count;
  final String actionLabel;
  final IconData actionIcon;

  /// The diagnostic id of the action button.
  final String id;
  final String cancelId;
  final bool busy;
  final bool destructive;
  final VoidCallback onAction;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Material(
      color: t.overlaySurface,
      shape: Border(top: BorderSide(color: t.overlayBorder)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DashSpace.gutter,
            vertical: DashSpace.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.printerLocationsSelected(count),
                  style: t.bodyStrong,
                ),
              ),
              TextButton(
                onPressed: busy ? null : onCancel,
                child: Text(l10n.cancel),
              ).tagged(cancelId),
              const SizedBox(width: DashSpace.sm),
              FilledButton.icon(
                onPressed: busy ? null : onAction,
                style: destructive ? dashDangerButtonStyle(t) : null,
                icon: Icon(actionIcon),
                label: Text(actionLabel),
              ).tagged(id),
            ],
          ),
        ),
      ),
    );
  }
}
