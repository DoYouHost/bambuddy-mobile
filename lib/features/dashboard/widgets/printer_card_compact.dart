part of 'printer_card.dart';

/// One filament slot as a compact tile: the colour with the material on it, the
/// slot's number in a pill at the corner, and under it the colour's name, the
/// percent, the grams and a bar. Tappable like [_FilamentRow], and takes the
/// same inputs; [width] is the slot [compactBlockLayout] gave it, gap included.
class _CompactSlotTile extends ConsumerWidget {
  const _CompactSlotTile({
    required this.width,
    required this.last,
    required this.tray,
    required this.active,
    required this.fill,
    required this.spool,
    required this.preset,
    this.badge,
    this.dryerInk,
    this.slot,
  });

  final double width;

  /// The last tile of its row: the slot's gap is not drawn, so the row ends
  /// flush with its container instead of one gap past it.
  final bool last;
  final AmsTray tray;
  final bool active;
  final TrayFill fill;
  final Spool? spool;
  final SlotPreset? preset;

  /// The slot's number, or the external holder's side on a dual machine.
  final String? badge;

  /// Set on a slot inside the AMS 3H's dryer, in the dryer chip's colour.
  final Color? dryerInk;
  final _SlotRef? slot;

  /// The swatch is nearly square, but never shorter than two lines of material
  /// and the room the pill's inner half leaves above them, so tiles of one row
  /// are as tall as each other and the pill never overlaps the name (it may
  /// touch it, on the narrowest tile).
  static const _squareness = 0.95;
  static const _lineHeight = 1.15;
  static const _materialLines = 2;

  /// How far the pill (and the dryer mark) stand out of the swatch's corner. It
  /// is also the room kept above the name, so the part inside the swatch ends
  /// where the name begins and the name can sit at the swatch's centre.
  static const _pillOutset = DashSpace.sm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final empty = tray.isEmpty;
    final unconfigured = tray.emptyKind == EmptySlotKind.unconfigured;
    // Same rule as [_FilamentRow]: a spool the printer cannot name, with one
    // assigned to the slot, is shown as that spool (#3434).
    final pending = empty && unconfigured ? spool : null;
    final question =
        empty &&
        unconfigured &&
        pending == null &&
        this.slot?.amsId != externalHolderUnit;
    final naming = empty
        ? null
        : slotNaming(
            l10n,
            ref.watchColorNames(),
            tray,
            spool,
            preset,
            subBrandFirst: true,
          );
    final percent = empty ? null : fill.percent;
    final grams = empty ? null : fill.grams;
    final ink = active ? t.accentGreenInk : t.textPrimary;
    final color = empty
        ? parseSpoolColor(pending?.rgba)
        : parseTrayColor(tray.trayColor);
    // A translucent filament reads as it shows over the card, not as its hex.
    final shown = color == null
        ? null
        : Color.alphaBlend(color, t.overlaySurface);
    final swatchInk = shown == null ? t.textTertiary : _inkOn(shown);

    final material =
        naming?.name ?? pending?.material ?? (question ? '?' : '–');
    final caption =
        naming?.colour ??
        (empty && pending == null
            ? (question ? l10n.traySlotUnconfigured : l10n.traySlotEmpty)
            : _pendingLabel(pending) ?? '');
    final dim = empty && pending == null && !question;

    final tileWidth = max(0.0, width - compactTileGap);
    // The font is scaled first and the leading applied to the result, as Text
    // does; scaling the product would come out short on a nonlinear scaler.
    final lineHeight =
        MediaQuery.textScalerOf(context).scale(DashFontSize.body) * _lineHeight;
    final swatchHeight = max(
      tileWidth * _squareness,
      _materialLines * lineHeight + 2 * _pillOutset,
    );

    final swatch = SizedBox(
      height: swatchHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _SwatchPainter(
                fill: shown,
                edge: active ? t.accentGreen : t.textTertiary,
                stroke: active ? DashStroke.regular : DashStroke.hairline,
                dashed: empty && pending == null,
              ),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(DashSpace.xs),
              child: Center(
                // The dash or question mark is only a picture of "nothing here";
                // the caption under the swatch says it in words.
                child: ExcludeSemantics(
                  excluding: empty && pending == null,
                  child: Text(
                    material,
                    textAlign: TextAlign.center,
                    maxLines: _materialLines,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodyStrong.copyWith(
                      fontSize: DashFontSize.body,
                      height: _lineHeight,
                      color: swatchInk,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (badge != null)
            PositionedDirectional(
              top: -_pillOutset,
              start: -DashSpace.xs,
              child: _SlotPill(text: badge!),
            ),
          if (dryerInk != null)
            PositionedDirectional(
              top: -_pillOutset,
              end: 0,
              child: Container(
                width: DashIcon.sm,
                height: DashIcon.sm,
                decoration: BoxDecoration(
                  color: t.overlaySurface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.local_fire_department,
                  size: DashIcon.xs,
                  color: dryerInk,
                  semanticLabel: l10n.amsDryer,
                ),
              ),
            ),
        ],
      ),
    );

    // A blank line keeps its height, so an empty tile ends where a full one
    // does and the bars of a row line up.
    Widget line(String? text, TextStyle style) => Text(
      text ?? ' ',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: style,
    );

    final tile = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        swatch,
        const SizedBox(height: DashSpace.xs),
        line(caption, t.bodyStrong.copyWith(color: dim ? t.textTertiary : ink)),
        line(
          percent == null ? null : '$percent%',
          t.monoValue.copyWith(fontWeight: DashWeight.bold, color: ink),
        ),
        line(
          grams == null
              ? null
              : l10n.inventoryUsageWeight(grams.toStringAsFixed(0)),
          t.monoLabel,
        ),
        const SizedBox(height: DashSpace.xs),
        // The percent above says it; the bar's own "75%" would read twice, and
        // "0%" on a slot with no reading.
        ExcludeSemantics(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(DashRadius.xs),
            child: LinearProgressIndicator(
              value: (percent ?? 0).clamp(0, 100) / 100,
              minHeight: DashBar.thin,
              color: active ? t.accentGreen : t.textTertiary,
              backgroundColor: t.gaugeTrack,
            ),
          ),
        ),
      ],
    );

    final slot = this.slot;
    // The slot owns the gap after the tile, except the row's last, which has
    // none to give.
    return SizedBox(
      width: last ? tileWidth : width,
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: SizedBox(
          width: tileWidth,
          child: MergeSemantics(
            child: slot == null
                ? tile
                : logTagMaterial(
                    'printer.ams_slot',
                    tray.trayType,
                    InkWell(
                      borderRadius: BorderRadius.circular(DashRadius.md),
                      onTap: () => dashSheet<void>(
                        context,
                        builder: (_) => _AssignSlotSheet(slot: slot),
                      ),
                      child: tile,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// The slot's number or side, white on a dark pill so it reads on any colour.
class _SlotPill extends StatelessWidget {
  const _SlotPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: DashSize.d16),
      height: DashSize.d16,
      padding: const EdgeInsets.symmetric(horizontal: DashSpace.xs),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: DashAlpha.scrim),
        borderRadius: BorderRadius.circular(DashRadius.sm),
      ),
      // Clamped so the number stays inside the fixed pill. The pill is the only
      // place the number is drawn.
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: DashTokens.fontMono,
            fontSize: DashFontSize.micro,
            fontWeight: DashWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// A swatch's rounded rectangle: filled with the filament's colour, outlined,
/// and dashed when the slot is empty.
class _SwatchPainter extends CustomPainter {
  const _SwatchPainter({
    required this.fill,
    required this.edge,
    required this.stroke,
    required this.dashed,
  });

  final Color? fill;
  final Color edge;
  final double stroke;
  final bool dashed;

  static const _dash = DashSize.d4;

  @override
  void paint(Canvas canvas, Size size) {
    // Inset by half the stroke so the outline stays inside the box.
    final rect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(stroke / 2),
      const Radius.circular(DashRadius.md),
    );
    if (fill != null) canvas.drawRRect(rect, Paint()..color = fill!);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = edge;
    if (!dashed) {
      canvas.drawRRect(rect, line);
      return;
    }
    final path = Path()..addRRect(rect);
    for (final metric in path.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += _dash * 2) {
        canvas.drawPath(metric.extractPath(at, at + _dash), line);
      }
    }
  }

  @override
  bool shouldRepaint(_SwatchPainter old) =>
      old.fill != fill ||
      old.edge != edge ||
      old.stroke != stroke ||
      old.dashed != dashed;
}
