import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:app_util/app_util.dart';
import 'package:dash_kit/dash_kit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/ams/color_names.dart';
import '../../core/models/queue_item.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import 'queue_mapping_sheet.dart';

/// The web's `ColorSubstitutionNotes` (#3279) as a chip: a slot that printed
/// from a spool of another colour than the file asked for. The web writes one
/// line per slot; on a phone that made a row grow with every slot and filled
/// the screen at large text, so the row carries one chip and the lines are in
/// the sheet it opens. Draws nothing — and asks for no colour catalogue —
/// when the item has no substitutions.
class ColorSubstitutionChip extends ConsumerWidget {
  const ColorSubstitutionChip({super.key, required this.item});

  final QueueItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = item.colorSubstitutions;
    if (subs.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final catalog =
        ref.watch(mappingColorCatalogProvider).value ?? ColorCatalog.empty;
    final single = subs.length == 1 ? subs.single : null;
    return logTag(
      'queue.color_substitution',
      Semantics(
        button: true,
        // One slot reads its whole sentence; several read the count, and the
        // sheet has the rest.
        label: single == null
            ? l10n.queueColorSubstitutionSlots(subs.length)
            : colorSubstitutionLabel(l10n, catalog, single),
        // The tap is declared here: `excludeSemantics` drops the InkWell's own
        // action, and a button a screen reader cannot activate is worse than
        // none.
        onTap: () => showColorSubstitutionSheet(context, item),
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(DashRadius.xl),
          onTap: () => showColorSubstitutionSheet(context, item),
          // 48 dp tall to be tapped; the pill inside is drawn smaller.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: DashSize.d48),
            child: Center(
              widthFactor: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: DashSpace.sm,
                  vertical: DashSpace.xs,
                ),
                decoration: BoxDecoration(
                  color: t.warning.withValues(alpha: DashAlpha.wash),
                  borderRadius: BorderRadius.circular(DashRadius.xl),
                  border: Border.all(
                    color: t.warning.withValues(alpha: DashAlpha.outline),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: DashIcon.xs,
                      color: t.warningInk,
                    ),
                    const SizedBox(width: DashSpace.xs),
                    if (single != null) ...[
                      _Swatch(hex: single.got),
                      Icon(
                        Icons.arrow_forward,
                        size: DashIcon.xs,
                        color: t.warningInk,
                      ),
                      _Swatch(hex: single.wanted),
                    ] else
                      Text(
                        l10n.queueColorSubstitutionSlots(subs.length),
                        style: t.micro.copyWith(color: t.warningInk),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showColorSubstitutionSheet(BuildContext context, QueueItem item) =>
    dashSheet<void>(context, builder: (_) => _SubstitutionSheet(item: item));

/// A colour as a dot; a hex that is no colour leaves the dot empty rather than
/// drawing a wrong one.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.hex, this.size = DashSize.d12});

  final String hex;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorFromHex(hex.replaceFirst('#', '')),
        shape: BoxShape.circle,
        border: Border.all(color: t.hairline),
      ),
    );
  }
}

class _SubstitutionSheet extends ConsumerWidget {
  const _SubstitutionSheet({required this.item});

  final QueueItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final catalog =
        ref.watch(mappingColorCatalogProvider).value ?? ColorCatalog.empty;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        DashSpace.xl,
        DashSpace.sm,
        DashSpace.xl,
        DashSpace.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(l10n.queueColorSubstitutionTitle, style: t.titleMd),
          ),
          const SizedBox(height: DashSpace.xs),
          Text(
            l10n.queueColorSubstitutionWhy,
            style: t.body.copyWith(color: t.textSecondary),
          ),
          for (final sub in item.colorSubstitutions)
            Padding(
              padding: const EdgeInsets.only(top: DashSpace.md),
              child: _SlotBlock(sub: sub, catalog: catalog),
            ),
        ],
      ),
    );
  }
}

/// One slot: the colour it printed in beside the colour the file asked for,
/// each named and given as a hex.
class _SlotBlock extends StatelessWidget {
  const _SlotBlock({required this.sub, required this.catalog});

  final ColorSubstitution sub;
  final ColorCatalog catalog;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final type = sub.type.isEmpty ? null : sub.type;
    return Container(
      padding: const EdgeInsets.all(DashSpace.md),
      decoration: BoxDecoration(
        color: t.subCard,
        borderRadius: BorderRadius.circular(DashRadius.lg),
        border: Border.all(color: t.subCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.queueColorSubstitutionSlot(sub.slotId),
            style: t.label.copyWith(fontWeight: DashWeight.semibold),
          ),
          const SizedBox(height: DashSpace.sm),
          // Two columns while they fit, stacked at large text.
          LayoutBuilder(
            builder: (context, box) {
              final printed = _Side(
                caption: l10n.queueColorSubstitutionPrinted,
                hex: sub.got,
                name: mappingColorName(l10n, catalog, sub.got, material: type),
              );
              final wanted = _Side(
                caption: l10n.queueColorSubstitutionWanted,
                hex: sub.wanted,
                name: mappingColorName(
                  l10n,
                  catalog,
                  sub.wanted,
                  material: type,
                ),
              );
              // Two columns need room for a caption and a name each; the room
              // they need grows with the text, so the rule is the width left
              // at this scale, not the scale alone.
              final stacked =
                  box.maxWidth <
                  (DashSize.d128 * 2 + DashSpace.md) *
                      MediaQuery.textScalerOf(context).scale(1);
              return stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        printed,
                        const SizedBox(height: DashSpace.sm),
                        wanted,
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: printed),
                        const SizedBox(width: DashSpace.md),
                        Expanded(child: wanted),
                      ],
                    );
            },
          ),
        ],
      ),
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({required this.caption, required this.hex, required this.name});

  final String caption;
  final String hex;
  final String name;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final shown = '#${hex.replaceFirst('#', '').toUpperCase()}';
    return Semantics(
      container: true,
      label: '$caption: $name $shown',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(caption, style: t.micro.copyWith(color: t.textTertiary)),
          const SizedBox(height: DashSpace.xs),
          Row(
            children: [
              _Swatch(hex: hex, size: DashSize.d24),
              const SizedBox(width: DashSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: t.label),
                    Text(shown, style: t.monoLabel),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The line for one substitution as a sentence: both colours by name, and by
/// hex as well when the two names would read alike (`disambiguateColorNames`,
/// #2941). The chip reads it aloud for a single slot.
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
