import 'package:flutter/material.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/format/duration_format.dart';
import '../../core/models/plate_list.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../common/dash_sheet.dart';
import '../common/print_thumbnail.dart';

/// Picks which plate of a multi-plate 3MF to print.
///
/// A sheet rather than a `DropdownMenu` because the choice is not a word: two
/// plates of the same file differ by what is on them, and the render plus the
/// time and weight is what tells them apart. Returns the plate index, or null
/// when the user backed out — which leaves the caller's selection alone.
Future<int?> showQueuePlateSheet(
  BuildContext context, {
  required PlateList plates,
  required int? selected,
}) =>
    dashSheet<int>(
      context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        final t = DashTokens.of(ctx);
        return logTag(
          'sheet.queue_plate',
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  l10n.queuePlatePickTitle,
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final plate in plates.plates)
                      _PlateRow(
                        plate: plate,
                        selected: plate.index == selected,
                        onTap: () => Navigator.pop(ctx, plate.index),
                        tokens: t,
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );

class _PlateRow extends StatelessWidget {
  const _PlateRow({
    required this.plate,
    required this.selected,
    required this.onTap,
    required this.tokens,
  });

  final PlateInfo plate;
  final bool selected;
  final VoidCallback onTap;
  final DashTokens tokens;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Objects first — it is the one line that says what is actually on the
    // plate; time and weight only follow when the 3MF recorded them, which a
    // source-only project does not.
    final facts = <String>[
      l10n.queuePlateObjects(plate.objectCount),
      if (plate.printTimeSeconds != null)
        formatSeconds(l10n, plate.printTimeSeconds!),
      if (plate.filamentUsedGrams != null)
        '${plate.filamentUsedGrams!.toStringAsFixed(0)} g',
    ];
    return ListTile(
      leading: plate.thumbnailPath == null
          ? Icon(Icons.crop_square, color: tokens.textTertiary)
          : PrintThumbnail.path(path: plate.thumbnailPath!),
      title: Text(plateLabel(l10n, plate)),
      subtitle: Text(facts.join(' · ')),
      trailing: selected
          ? Icon(Icons.check, color: tokens.accentGreenInk)
          : null,
      selected: selected,
      onTap: onTap,
    ).tagged('queue_edit.plate_option');
  }
}

/// "Plate 3", or "Plate 3 · Lid" when the 3MF named the plate — the number is
/// what `plate_id` carries, so it leads whatever the designer called it.
String plateLabel(AppLocalizations l10n, PlateInfo plate) {
  final name = plate.name;
  return name == null || name.isEmpty
      ? l10n.queueEditPlateSelected(plate.index)
      : l10n.queueEditPlateNamed(plate.index, name);
}
