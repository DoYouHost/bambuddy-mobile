part of 'printer_card.dart';

/// What one filament slot needs, whether it is drawn as a detailed row or a
/// compact tile, and whether it is an AMS slot or an external spool.
class _TileSpec {
  const _TileSpec({
    required this.tray,
    required this.active,
    required this.fill,
    required this.spool,
    required this.preset,
    required this.badge,
    required this.slot,
    this.dryerInk,
    this.filamentName,
  });

  final AmsTray tray;
  final bool active;
  final TrayFill fill;
  final Spool? spool;
  final SlotPreset? preset;
  final String? badge;
  final _SlotRef? slot;
  final Color? dryerInk;

  /// Names the detailed row only: the compact tile keeps the older chain.
  final String? filamentName;

  Widget row({required bool last}) => _FilamentRow(
    tray: tray,
    active: active,
    fill: fill,
    spool: spool,
    preset: preset,
    last: last,
    badge: badge,
    dryerInk: dryerInk,
    slot: slot,
    filamentName: filamentName,
  );

  Widget tile(double width) => _CompactSlotTile(
    width: width,
    tray: tray,
    active: active,
    fill: fill,
    spool: spool,
    preset: preset,
    badge: badge,
    dryerInk: dryerInk,
    slot: slot,
  );
}

/// The title of a printer's filament block, with the switch between the two
/// views. The glyph is the view a tap leads to, and the choice is for this
/// printer's whole block, every AMS unit and the external spools alike.
class _FilamentTitle extends ConsumerWidget {
  const _FilamentTitle({required this.printerId});

  final int printerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final compact = ref.watch(printerCompactAmsProvider).isCompact(printerId);
    return Row(
      children: [
        Expanded(child: SectionLabel(l10n.amsSlotFilament)),
        _HeaderIconButton(
          id: 'printer.ams_layout',
          icon: compact ? Icons.view_list : Icons.grid_view,
          tooltip: compact ? l10n.amsViewDetailed : l10n.amsViewCompact,
          onPressed: () => ref
              .read(printerCompactAmsProvider.notifier)
              .set(printerId, !compact),
        ),
      ],
    );
  }
}

/// The compact tiles of one AMS unit, and the external spools when this is the
/// printer's last unit. [compactBlockLayout] decides the rows; a block whose
/// external group does not fit beside the AMS tiles gets the same heading the
/// detailed list uses.
class _CompactTiles extends StatelessWidget {
  const _CompactTiles({required this.ams, required this.external});

  final List<_TileSpec> ams;
  final List<_TileSpec> external;

  @override
  Widget build(BuildContext context) {
    // The text scale as the body font sees it, so a nonlinear scaler counts
    // for the size the tiles actually use.
    final scale =
        MediaQuery.textScalerOf(context).scale(DashFontSize.body) /
        DashFontSize.body;
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = compactBlockLayout(
          width: constraints.maxWidth,
          textScale: scale,
          amsCount: ams.length,
          externalCount: external.length,
        );
        final tiles = [...ams, ...external];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var r = 0; r < layout.rows.length; r++) ...[
              if (r == layout.externalFromRow) ...[
                if (r > 0) const SizedBox(height: DashSpace.md),
                const _ExternalTitle(rack: false),
                const SizedBox(height: DashSpace.sm),
              ] else if (r > 0)
                const SizedBox(height: DashSpace.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (
                    var i = layout.rows[r].start;
                    i < layout.rows[r].end;
                    i++
                  )
                    tiles[i].tile(layout.rows[r].slot),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}
