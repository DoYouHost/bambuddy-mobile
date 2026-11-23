import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ams/filament_mapping.dart';
import '../../core/models/queue_item.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../common/color_catalog.dart';
import '../dashboard/ws_providers.dart';
import '../inventory/inventory_screen.dart' show parseSpoolColor;
import '../slicer/slice_providers.dart';
import 'queue_filaments.dart';

/// The filaments a queued job uses, one chip each, as the web's queue row
/// lists them: the tray the stored mapping names, its spool and the colour; a
/// tray the printer reports empty in the warning colour (`QueuePage.tsx`).
class QueueFilamentChips extends ConsumerWidget {
  const QueueFilamentChips({super.key, required this.item});

  final QueueItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final catalog = ref.watchColorNames();
    // A library file's plates, or the archive's; none for an archive whose 3MF
    // went with it (the web skips that request, which only answers 404).
    final library = item.libraryFileId != null && item.archiveId == null;
    final source = library
        ? (false, item.libraryFileId!)
        : item.archiveId != null && !item.archiveDeleted
        ? (true, item.archiveId!)
        : null;
    final plates = source == null
        ? const <Never>[]
        : ref.watch(plateListProvider(source)).value?.plates ?? const [];
    final printerId = item.printerId;
    final status = printerId == null
        ? null
        : ref.watch(printerStatusesProvider)[printerId];
    final filaments = resolveQueueFilaments(
      item,
      plates,
      buildLoadedFilaments(status),
      status,
    );
    if (filaments.isEmpty) return const SizedBox.shrink();

    String label(QueueFilament f) {
      final colour =
          f.colorName ??
          colorDisplayName(
            l10n,
            catalog,
            f.color,
            material: f.type.isEmpty ? null : f.type,
          );
      final slot = f.slotLabel;
      if (slot == null) return colour;
      return [
        slot,
        if (f.emptySlot) l10n.traySlotEmpty else if (f.type.isNotEmpty) f.type,
        colour,
      ].join(' · ');
    }

    return Padding(
      padding: const EdgeInsets.only(top: DashSpace.sm),
      child: Wrap(
        spacing: DashSpace.xs,
        runSpacing: DashSpace.xs,
        children: [
          for (final f in filaments)
            _Chip(
              colour: parseSpoolColor(f.color),
              label: label(f),
              warn: f.emptySlot,
              t: t,
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.colour,
    required this.label,
    required this.warn,
    required this.t,
  });

  final Color? colour;
  final String label;
  final bool warn;
  final DashTokens t;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(
      DashSpace.xs,
      DashSpace.xs,
      DashSpace.sm,
      DashSpace.xs,
    ),
    decoration: BoxDecoration(
      color: warn ? t.warning.withValues(alpha: DashAlpha.wash) : null,
      borderRadius: BorderRadius.circular(DashRadius.xl),
      border: Border.all(
        color: warn ? t.warning : t.cardBorder,
        width: DashStroke.hairline,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: DashIcon.sm,
          height: DashIcon.sm,
          decoration: BoxDecoration(
            color: colour,
            shape: BoxShape.circle,
            border: Border.all(
              color: t.textTertiary,
              width: DashStroke.hairline,
            ),
          ),
        ),
        const SizedBox(width: DashSpace.xs),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.microSoft.copyWith(
              color: warn ? t.warningInk : t.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}
