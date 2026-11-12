part of 'inventory_screen.dart';

/// The colour catalogue as the spool, swatch and AMS slot forms pick from it
/// (#63): narrowed by [narrow], or the whole catalogue when that finds nothing,
/// each maker-and-material run under its own heading so the many whites of one
/// maker read apart. Pops the [ColorEntry].
class ColorCatalogueSheet extends ConsumerStatefulWidget {
  const ColorCatalogueSheet({
    super.key,
    required this.id,
    required this.narrow,
    this.rgba,
    this.colorName,
  });

  /// The form's area in the diagnostic log: `<id>.color_search`,
  /// `<id>.color_option`.
  final String id;

  /// The entries the form's own fields point at: [catalogueColoursFor] for a
  /// spool or a swatch, `presetColours` for a slot's preset.
  final List<ColorEntry> Function(List<ColorEntry> catalogue) narrow;

  /// The form's current colour, ticked on every entry with this hex and a
  /// non-empty [colorName] (any case); the hex alone would tick every white.
  /// A null [colorName] is a form that keeps no name, the AMS slot, whose
  /// `presetColours` list holds one entry per hex: there the hex alone ticks.
  /// Only a list narrowed to the form's fields is ticked, so two ticks mean
  /// entries those fields cannot tell apart ("White" in PLA Silk+ and PLA Tough
  /// with no variant, or two makers with no brand). The whole-catalogue
  /// fallback ticks nothing: the fields matched none of it.
  final String? rgba;
  final String? colorName;

  @override
  ConsumerState<ColorCatalogueSheet> createState() =>
      _ColorCatalogueSheetState();
}

class _ColorCatalogueSheetState extends ConsumerState<ColorCatalogueSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final loaded = ref.watch(colorCatalogProvider).value;
    final all = loaded ?? const <ColorEntry>[];
    final narrowed = widget.narrow(all);
    final rows = catalogueRows(narrowed.isEmpty ? all : narrowed, _query);
    final rgba = narrowed.isEmpty ? null : normalizeRgba(widget.rgba);
    final name = widget.colorName?.trim().toLowerCase();

    // The search keeps the keyboard up, and a modal sheet does not avoid it on
    // its own: the end of the list sat under it, out of reach.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableSheetSurface(
        builder: (context, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DashSpace.gutter,
                0,
                DashSpace.gutter,
                DashSpace.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.inventoryColorPickTitle, style: t.display),
                  const SizedBox(height: DashSpace.sm),
                  DashSearchField(
                    id: '${widget.id}.color_search',
                    hintText: l10n.inventoryColorSearchHint,
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ],
              ),
            ),
            Expanded(
              // The tiles paint their ink on the nearest Material, which the
              // sheet's painted surface is not.
              child: Material(
                type: MaterialType.transparency,
                child: loaded == null
                    ? const DashLoading()
                    : rows.isEmpty
                    ? ListView(
                        controller: controller,
                        padding: const EdgeInsets.all(DashSpace.xxl),
                        children: [
                          Text(
                            all.isEmpty
                                ? l10n.swatchNoCatalogColors
                                : l10n.noSearchResults(_query.trim()),
                            textAlign: TextAlign.center,
                            style: t.bodySoft,
                          ),
                        ],
                      )
                    : ListView.builder(
                        controller: controller,
                        itemCount: rows.length,
                        itemBuilder: (context, i) => switch (rows[i]) {
                          (heading: final h?, entry: _) => Padding(
                            padding: const EdgeInsets.fromLTRB(
                              DashSpace.gutter,
                              DashSpace.md,
                              DashSpace.gutter,
                              DashSpace.xs,
                            ),
                            child: Text(h, style: t.micro),
                          ),
                          (heading: _, entry: final e?) =>
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: DashSpace.gutter,
                              ),
                              leading: SpoolSwatch(
                                rgba: e.hexColor,
                                size: DashSize.d32,
                              ),
                              title: Text(
                                e.colorName.isEmpty ? '—' : e.colorName,
                              ),
                              trailing:
                                  rgba != null &&
                                      normalizeRgba(e.hexColor) == rgba &&
                                      (name == null ||
                                          (name.isNotEmpty &&
                                              e.colorName
                                                      .trim()
                                                      .toLowerCase() ==
                                                  name))
                                  ? Icon(Icons.check, color: t.accentGreenInk)
                                  : null,
                              onTap: () => Navigator.of(context).pop(e),
                            ).taggedMaterial(
                              '${widget.id}.color_option',
                              e.material,
                            ),
                          _ => const SizedBox.shrink(),
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [entries] matching [query] by name, maker or material, as the sheet lists
/// them: a heading row ("Bambu Lab · PLA Matte") before each maker-and-material
/// run, runs in the order the catalogue first names them. A run with neither
/// maker nor material gets no heading.
@visibleForTesting
List<({String? heading, ColorEntry? entry})> catalogueRows(
  List<ColorEntry> entries,
  String query,
) {
  final q = query.trim().toLowerCase();
  final runs = <String, List<ColorEntry>>{};
  for (final e in entries) {
    if (q.isNotEmpty &&
        !e.colorName.toLowerCase().contains(q) &&
        !e.manufacturer.toLowerCase().contains(q) &&
        !(e.material?.toLowerCase().contains(q) ?? false)) {
      continue;
    }
    final heading = [
      e.manufacturer.trim(),
      ?e.material?.trim(),
    ].where((s) => s.isNotEmpty).join(' · ');
    (runs[heading] ??= []).add(e);
  }
  return [
    for (final MapEntry(key: heading, value: run) in runs.entries) ...[
      if (heading.isNotEmpty) (heading: heading, entry: null),
      for (final e in run) (heading: null, entry: e),
    ],
  ];
}
