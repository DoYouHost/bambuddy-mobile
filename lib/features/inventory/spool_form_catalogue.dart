part of 'inventory_screen.dart';

/// The colour catalogue as the spool form picks from it (#63): narrowed to the
/// form's brand, material and variant by [catalogueColoursFor], or the whole
/// catalogue when that finds nothing, each maker-and-material run under its own
/// heading so the many whites of one maker read apart. Pops the [ColorEntry].
class _ColorCatalogueSheet extends ConsumerStatefulWidget {
  const _ColorCatalogueSheet({
    this.brand,
    this.material,
    this.subtype,
    this.rgba,
    this.colorName,
  });

  final String? brand;
  final String? material;
  final String? subtype;

  /// The form's current colour, ticked when an entry has both this hex and
  /// [colorName]: the hex alone would tick every white of the maker.
  final String? rgba;
  final String? colorName;

  @override
  ConsumerState<_ColorCatalogueSheet> createState() =>
      _ColorCatalogueSheetState();
}

class _ColorCatalogueSheetState extends ConsumerState<_ColorCatalogueSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final all = ref.watch(colorCatalogProvider).value ?? const <ColorEntry>[];
    final narrowed = catalogueColoursFor(
      all,
      brand: widget.brand,
      material: widget.material,
      subtype: widget.subtype,
    );
    final rows = catalogueRows(narrowed.isEmpty ? all : narrowed, _query);
    final rgba = normalizeRgba(widget.rgba);
    final name = widget.colorName?.trim();

    return DraggableSheetSurface(
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
                  id: 'spool_form.color_search',
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
              child: rows.isEmpty
                  ? ListView(
                      controller: controller,
                      padding: const EdgeInsets.all(DashSpace.xxl),
                      children: [
                        Text(
                          l10n.noSearchResults(_query.trim()),
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
                        (heading: _, entry: final e?) => ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: DashSpace.gutter,
                          ),
                          leading: SpoolSwatch(
                            rgba: e.hexColor,
                            size: DashSize.d32,
                          ),
                          title: Text(e.colorName.isEmpty ? '—' : e.colorName),
                          trailing:
                              rgba != null &&
                                  normalizeRgba(e.hexColor) == rgba &&
                                  e.colorName == name
                              ? Icon(Icons.check, color: t.accentGreenInk)
                              : null,
                          onTap: () => Navigator.of(context).pop(e),
                        ).taggedMaterial('spool_form.color_option', e.material),
                        _ => const SizedBox.shrink(),
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// [entries] matching [query] by name, maker or material, as the sheet lists
/// them: a heading row ("Bambu Lab · PLA Matte") before each maker-and-material
/// run, runs in the order the catalogue first names them.
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
      (heading: heading, entry: null),
      for (final e in run) (heading: null, entry: e),
    ],
  ];
}
