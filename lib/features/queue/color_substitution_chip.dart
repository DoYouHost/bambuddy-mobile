import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/ams/color_names.dart';
import '../../core/models/queue_item.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import 'queue_mapping_sheet.dart';

/// The web's `ColorSubstitutionNotes`: one amber line per slot that printed
/// from a spool of another colour than the file asked for (#3279). Shared by
/// the queue card and the history row, so a job says the same thing while it
/// prints and once it is done. Draws nothing — and asks for no colour
/// catalogue — when the item has no substitutions.
class ColorSubstitutionNotes extends ConsumerWidget {
  const ColorSubstitutionNotes({
    super.key,
    required this.item,
    this.indent = 0,
  });

  final QueueItem item;

  /// Space to the left, where a row starts its text under an icon and picture.
  final double indent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = item.colorSubstitutions;
    if (subs.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final catalog =
        ref.watch(mappingColorCatalogProvider).value ?? ColorCatalog.empty;
    return Padding(
      padding: EdgeInsets.only(left: indent, top: DashSpace.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final sub in subs)
            Padding(
              padding: const EdgeInsets.only(top: DashSpace.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: DashIcon.xs,
                    color: t.warningInk,
                  ),
                  const SizedBox(width: DashSpace.xs),
                  Expanded(
                    child: Text(
                      colorSubstitutionLabel(l10n, catalog, sub),
                      style: t.micro.copyWith(color: t.warningInk),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The line for one substitution: both colours by name, and by hex as well
/// when the two names would read alike (`disambiguateColorNames`, #2941).
String colorSubstitutionLabel(
  AppLocalizations l10n,
  ColorCatalog catalog,
  ColorSubstitution sub,
) {
  final type = sub.type.isEmpty ? null : sub.type;
  final (got, wanted) = disambiguateColorNames(
    (
      name: mappingColorName(l10n, catalog, sub.got, material: type),
      hex: sub.got,
    ),
    (
      name: mappingColorName(l10n, catalog, sub.wanted, material: type),
      hex: sub.wanted,
    ),
  );
  return l10n.queueColorSubstitution(sub.slotId, got, wanted);
}
