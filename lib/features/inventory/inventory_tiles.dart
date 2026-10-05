part of 'inventory_screen.dart';

/// The line above the shelf: how many spools the filters let through, and how
/// much filament has been consumed since the counters were last reset.
///
/// The two numbers count different things on purpose. [visibleCount] is what
/// the user is looking at, filters and search included; [consumed] comes from
/// [inventoryConsumedTotalProvider] and covers the whole shelf, archived spools
/// included.
class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.visibleCount, required this.consumed});

  final int visibleCount;
  final double consumed;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DashSpace.gutter,
        DashSpace.xs,
        DashSpace.gutter,
        DashSpace.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.inventorySpoolCount(visibleCount),
              style: t.monoLabel,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (consumed > 0) ...[
            const SizedBox(width: DashSpace.sm),
            Icon(Icons.trending_down, size: 13, color: t.textTertiary),
            const SizedBox(width: DashSpace.xs),
            Text(
              l10n.inventoryTotalConsumed(fmtGrams(consumed)),
              style: t.monoLabel,
            ),
          ],
        ],
      ),
    );
  }
}

class _SpoolTile extends StatelessWidget {
  const _SpoolTile({
    required this.spool,
    this.assignment,
    this.selected = false,
    this.selectionMode = false,
    this.onTap,
    this.onLongPress,
  });

  final Spool spool;
  final SpoolAssignment? assignment;

  /// Whether this spool is picked in multi-select mode.
  final bool selected;

  /// Whether the screen is in multi-select mode at all — drives the checkbox
  /// slot, which stays visible (unchecked) on unselected rows so the whole
  /// list reads as selectable.
  final bool selectionMode;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final frac = spool.remainingFraction;
    final low = spool.isLowStock && !spool.isArchived;
    final fillColor = low ? t.danger : t.accentGreen;

    // The weight line takes the leftover space and the slot label keeps its
    // natural width, right-aligned by that.
    //
    // NOT a `Spacer` between the two: the weight text was unconstrained, so it
    // took whatever it wanted first, and the Spacer — a flex child itself —
    // then halved what was left with the label. The label got 50% of the
    // remainder at best and nothing at all once the weight text filled the row:
    // "AMS-A ·…", or no slot at all. Which half gives way is decided here
    // instead, and it is the weight line: it ends in `/ 1000g`, which the
    // progress bar above already shows, while the slot is what the reader
    // came for.
    final metaLine = Row(
      children: [
        Expanded(
          child: Text(
            '#${spool.id} · ${l10n.inventoryRemaining(spool.remainingWeight.toStringAsFixed(0))}'
            '${spool.labelWeight > 0 ? ' / ${spool.labelWeight}g' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.monoLabel,
          ),
        ),
        if (assignment != null) ...[
          const SizedBox(width: DashSpace.sm),
          Icon(Icons.print_outlined, size: 12, color: t.textTertiary),
          const SizedBox(width: DashSpace.xs),
          Text(
            assignmentSlotLabel(l10n, assignment!),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.monoLabel,
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DashSpace.gutter,
        0,
        DashSpace.gutter,
        DashSpace.md,
      ),
      child: Material(
        color: Colors.transparent,
        child: logTagMaterial(
          'inventory.spool',
          spool.material,
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onLongPress: onLongPress,
            onTap:
                onTap ??
                () => dashSurfaceSheet<void>(
                  context,
                  builder: (_) =>
                      _SpoolDetailSheet(spool: spool, assignment: assignment),
                ),
            child: Container(
              padding: const EdgeInsets.all(DashSpace.lg),
              decoration: BoxDecoration(
                color: selected
                    ? t.accentGreen.withValues(alpha: 0.12)
                    : low
                    ? t.danger.withValues(alpha: 0.05)
                    : t.subCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected
                      ? t.accentGreen.withValues(alpha: 0.6)
                      : low
                      ? t.danger.withValues(alpha: 0.35)
                      : t.subCardBorder,
                ),
              ),
              // Two nested rows so the checkbox can centre against the full row
              // height while the swatch stays top-aligned with the title: the
              // outer row centres, the inner one keeps the original `start`.
              child: Row(
                children: [
                  if (selectionMode) ...[
                    Icon(
                      selected
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 22,
                      color: selected ? t.accentGreenInk : t.textTertiary,
                    ),
                    const SizedBox(width: DashSpace.md),
                  ],
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Opacity(
                          opacity: spool.isArchived ? 0.5 : 1,
                          child: SpoolSwatch(
                            rgba: spool.rgba,
                            size: 44,
                            radius: 13,
                          ),
                        ),
                        const SizedBox(width: DashSpace.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  _MaterialTag(
                                    label: spool.material,
                                    tokens: t,
                                  ),
                                  const SizedBox(width: DashSpace.sm),
                                  Expanded(
                                    child: Text(
                                      spool.displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: t.titleSm.copyWith(
                                        color: spool.isArchived
                                            ? t.textTertiary
                                            : t.textPrimary,
                                      ),
                                    ),
                                  ),
                                  if (low) ...[
                                    const SizedBox(width: DashSpace.sm),
                                    _LowBadge(tokens: t),
                                  ],
                                  if (spool.isArchived) ...[
                                    const SizedBox(width: DashSpace.sm),
                                    Icon(
                                      Icons.archive_outlined,
                                      size: 14,
                                      color: t.textTertiary,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: DashSpace.sm),
                              DashProgressBar(
                                value: frac,
                                height: 4,
                                radius: 2,
                                color: fillColor,
                              ),
                              const SizedBox(height: DashSpace.sm),
                              metaLine,
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bordered material-code pill on a spool row (e.g. "PLA").
class _MaterialTag extends StatelessWidget {
  const _MaterialTag({required this.label, required this.tokens});

  final String label;
  final DashTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DashSpace.sm,
        vertical: DashSpace.xs,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tokens.textSecondary.withValues(alpha: 0.25)),
      ),
      child: Text(
        label.toUpperCase(),
        style: tokens.monoLabel.copyWith(color: tokens.textSecondary),
      ),
    );
  }
}

/// "LOW" stock badge on a spool row.
class _LowBadge extends StatelessWidget {
  const _LowBadge({required this.tokens});

  final DashTokens tokens;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DashSpace.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.danger.withValues(alpha: 0.5)),
      ),
      child: Text(
        l10n.inventoryLowStock.toUpperCase(),
        style: tokens.micro.copyWith(color: tokens.dangerInk),
      ),
    );
  }
}

/// Label of where a spool sits. Real AMS slot → "AMS-A · 2".
/// External spool (id 254/255) is NOT an AMS unit — show extruder (left/right),
/// consistent with dashboard; mapping from [SpoolAssignment.extruder].
String assignmentSlotLabel(AppLocalizations l10n, SpoolAssignment a) {
  if (!a.isExternalSpool) return a.slotLabel;
  return switch (a.extruder) {
    1 => l10n.extruderLeft,
    0 => l10n.extruderRight,
    _ => l10n.externalSpool,
  };
}

/// Square spool color swatch. `rgba` is typically hex `RRGGBBAA` (like AMS colors)
/// or `#RRGGBB`; if unknown, show neutral placeholder.
class SpoolSwatch extends StatelessWidget {
  const SpoolSwatch({super.key, this.rgba, this.size = 36, this.radius = 8});

  final String? rgba;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final color = parseSpoolColor(rgba);
    final t = DashTokens.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color ?? t.subCard,
        borderRadius: BorderRadius.circular(radius),
        // Stronger than a card's hairline: a black spool on the dark theme,
        // or a white one on the light theme, is otherwise just a hole.
        border: Border.all(color: t.textTertiary.withValues(alpha: 0.4)),
      ),
      child: color == null
          ? Icon(Icons.question_mark, size: size * 0.5, color: t.textTertiary)
          : null,
    );
  }
}

/// Normalizes color hex to server format: `RRGGBBAA` (8 chars, no `#`).
/// Accepts input with `#`, 6-digit (adds `FF` alpha), and 8-digit.
/// Returns null for empty/invalid — skip field to avoid 422
/// (`SpoolCreate.rgba` pattern is `^[0-9A-Fa-f]{8}$`).
String? normalizeRgba(String? raw) {
  if (raw == null) return null;
  var h = raw.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.isEmpty) return null;
  if (RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(h)) return '${h.toUpperCase()}FF';
  if (RegExp(r'^[0-9A-Fa-f]{8}$').hasMatch(h)) return h.toUpperCase();
  return null;
}

/// Parses spool color from `RRGGBBAA` / `RRGGBB` (optional `#`).
Color? parseSpoolColor(String? raw) {
  if (raw == null) return null;
  var hex = raw.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length == 8) {
    final rgb = int.tryParse(hex.substring(0, 6), radix: 16);
    final a = int.tryParse(hex.substring(6, 8), radix: 16);
    if (rgb == null || a == null) return null;
    return Color((a << 24) | rgb);
  }
  if (hex.length == 6) {
    final rgb = int.tryParse(hex, radix: 16);
    if (rgb == null) return null;
    return Color(0xFF000000 | rgb);
  }
  return null;
}

class _SpoolDetailSheet extends ConsumerWidget {
  const _SpoolDetailSheet({required this.spool, this.assignment});

  final Spool spool;
  final SpoolAssignment? assignment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final usage = ref.watch(spoolUsageProvider(spool.id));
    final climate = climateOfSpool(
      ref.watch(locationClimateProvider).valueOrNull ?? const {},
      spool,
    );

    return logTag(
      'sheet.spool_detail',
      DraggableSheetSurface(
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(
            DashSpace.gutter,
            0,
            DashSpace.gutter,
            DashSpace.xl,
          ),
          children: [
            Row(
              children: [
                SpoolSwatch(rgba: spool.rgba, size: 52, radius: 16),
                const SizedBox(width: DashSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Expanded(
                            child: Text(
                              spool.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.display,
                            ),
                          ),
                          const SizedBox(width: DashSpace.sm),
                          Text(
                            '#${spool.id}',
                            style: t.monoHeadline.copyWith(
                              color: t.accentGreenInk,
                            ),
                          ),
                        ],
                      ),
                      if (spool.colorName != null)
                        Text(spool.colorName!, style: t.bodyPlain),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: DashSpace.lg),

            _SpoolActions(spool: spool, assignment: assignment),
            const SizedBox(height: DashSpace.lg),

            if (spool.remainingFraction != null) ...[
              DashProgressBar(
                value: spool.remainingFraction,
                height: 8,
                color: spool.isLowStock ? t.danger : null,
              ),
              const SizedBox(height: DashSpace.sm),
              Text(
                '${l10n.inventoryRemaining(spool.remainingWeight.toStringAsFixed(0))}'
                ' ${l10n.inventoryOfTotal(spool.labelWeight)}',
                style: t.label.copyWith(color: t.textSecondary),
              ),
              const SizedBox(height: DashSpace.lg),
            ],

            _DetailCard(
              children: [
                _InfoRow(
                  icon: Icons.print_outlined,
                  label: l10n.inventoryDetailSlot,
                  value: assignment != null
                      ? [
                          if (assignment!.printerName != null)
                            assignment!.printerName!,
                          assignmentSlotLabel(l10n, assignment!),
                        ].join(' · ')
                      : l10n.inventoryDetailNotLoaded,
                ),
                if (spool.storageLocation != null)
                  _InfoRow(
                    icon: Icons.place_outlined,
                    label: l10n.inventoryLocation,
                    value: spool.storageLocation!,
                    // What the location's own thermometer or hygrometer
                    // reads, where one is bound to it — the answer to "is
                    // this spool sitting somewhere dry", asked at the one
                    // place the spool and its shelf are both on screen.
                    below: climate == null
                        ? null
                        : _ClimatePills(readings: climate.readings),
                  ),
                // The counter the reset action resets. Without it on screen
                // that action had nothing to show for itself: it moves the
                // baseline, never the remaining weight above.
                if (spool.consumedWeight > 0)
                  _InfoRow(
                    icon: Icons.trending_down,
                    label: l10n.inventoryDetailConsumedSinceReset,
                    value: fmtGrams(spool.consumedWeight),
                  ),
                if (spool.costPerKg != null)
                  _InfoRow(
                    icon: Icons.payments_outlined,
                    label: l10n.inventoryFieldCostPerKg,
                    value: spool.costPerKg!.toStringAsFixed(2),
                  ),
                if (spool.slicerFilamentName ?? spool.slicerFilament
                    case final preset?)
                  _InfoRow(
                    icon: Icons.tune,
                    label: l10n.inventoryFieldSlicerPreset,
                    value: preset,
                  ),
                if (spool.nozzleTempMin != null || spool.nozzleTempMax != null)
                  _InfoRow(
                    icon: Icons.thermostat_outlined,
                    label: l10n.inventoryNozzleTemp,
                    value:
                        '${spool.nozzleTempMin ?? '?'}–${spool.nozzleTempMax ?? '?'} °C',
                  ),
                if (spool.tagUid != null)
                  _InfoRow(
                    icon: Icons.nfc_outlined,
                    label: l10n.inventoryTag,
                    value: spool.tagUid!,
                  ),
                if (spool.note != null)
                  _InfoRow(
                    icon: Icons.sticky_note_2_outlined,
                    label: l10n.inventoryNote,
                    value: spool.note!,
                    stacked: true,
                  ),
              ],
            ),

            if (spool.kProfiles.isNotEmpty) ...[
              const SizedBox(height: DashSpace.lg),
              _SheetSectionTitle(label: l10n.inventoryKProfiles),
              const SizedBox(height: DashSpace.sm),
              _DetailCard(
                children: [
                  for (final k in spool.kProfiles)
                    _InfoRow(
                      icon: Icons.tune,
                      label: k.name ?? '—',
                      value: l10n.inventoryKProfileLine(
                        k.nozzleDiameter ?? '?',
                        k.kValue?.toStringAsFixed(3) ?? '?',
                      ),
                    ),
                ],
              ),
            ],

            if (spool.suppliers case final links? when links.isNotEmpty) ...[
              const SizedBox(height: DashSpace.lg),
              _SheetSectionTitle(label: l10n.inventorySuppliersTitle),
              const SizedBox(height: DashSpace.sm),
              _DetailCard(
                children: [
                  for (final link in purchaseSourceFirst(links))
                    _SupplierLinkRow(link: link),
                ],
              ),
            ],

            const SizedBox(height: DashSpace.lg),
            _SheetSectionTitle(label: l10n.inventoryUsageHistory),
            const SizedBox(height: DashSpace.xs),
            usage.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(DashSpace.lg),
                child: DashLoading(),
              ),
              error: (_, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: DashSpace.sm),
                child: Text(l10n.inventoryUsageEmpty, style: t.labelSoft),
              ),
              data: (entries) => entries.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: DashSpace.sm,
                      ),
                      child: Text(l10n.inventoryUsageEmpty, style: t.labelSoft),
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < entries.length; i++)
                          _UsageRow(
                            entry: entries[i],
                            last: i == entries.length - 1,
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small uppercase section title inside the detail sheet (e.g. above usage
/// history / K profiles) — mirrors the AMS section labels on the dashboard.
class _SheetSectionTitle extends StatelessWidget {
  const _SheetSectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Text(label, style: t.bodyBold.copyWith(color: t.textPrimary));
  }
}

/// One usage-history entry: print name + date on the left, weight used on the
/// right, separated from the next entry by a dotted rule (as on the dashboard's
/// filament rows).
class _UsageRow extends StatelessWidget {
  const _UsageRow({required this.entry, required this.last});

  final SpoolUsageEntry entry;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: DashSpace.sm),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.history, size: 16, color: t.textTertiary),
              const SizedBox(width: DashSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.printName ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.body,
                    ),
                    if (entry.createdAt != null)
                      Text(
                        DateTimeFormats.of(context).date(entry.createdAt!),
                        style: t.monoMicro,
                      ),
                  ],
                ),
              ),
              Text(
                l10n.inventoryUsageWeight(entry.weightUsed.toStringAsFixed(0)),
                // Not the mono face: its space is as wide as a digit, which
                // read as "96  g".
                style: t.body.copyWith(
                  color: t.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          if (!last) ...[
            const SizedBox(height: DashSpace.sm),
            DashedLine(color: t.dottedRule),
          ],
        ],
      ),
    );
  }
}

/// The sub-card the detail sheet's rows sit on.
class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DashSpace.lg,
        vertical: DashSpace.xs,
      ),
      decoration: BoxDecoration(
        color: t.subCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.subCardBorder),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// One fact about the spool: what it is on the left, its value on the right,
/// read first. [stacked] puts the value under the label instead, for free text
/// that would otherwise wrap into a narrow right-aligned column.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.below,
    this.stacked = false,
  });

  final IconData icon;
  final String label;
  final String value;

  /// Under the whole row, lined up with the label.
  final Widget? below;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final labelText = Text(
      label,
      style: t.label.copyWith(color: t.textSecondary),
    );
    final valueText = Text(
      value,
      textAlign: stacked ? TextAlign.start : TextAlign.end,
      style: t.body.copyWith(color: t.textPrimary),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DashSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: _detailIconNudge),
            child: Icon(icon, size: 16, color: t.textSecondary),
          ),
          const SizedBox(width: DashSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (stacked) ...[
                  labelText,
                  const SizedBox(height: DashSpace.xs),
                  valueText,
                ] else
                  Row(
                    // Both sides loose: each wraps at half the row instead of
                    // one squeezing the other to nothing at a large text size,
                    // and spaceBetween keeps the value on the row's right edge
                    // however short the label is.
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(child: labelText),
                      const SizedBox(width: DashSpace.md),
                      Flexible(child: valueText),
                    ],
                  ),
                if (below != null) ...[
                  const SizedBox(height: DashSpace.sm),
                  below!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Puts a 16 dp icon on the first line of body text next to it.
const _detailIconNudge = 2.0;

/// A supplier the spool can be bought from: the name reads as the row's title,
/// with the purchase source marked beside it, and what the user noted about
/// buying there underneath.
class _SupplierLinkRow extends StatelessWidget {
  const _SupplierLinkRow({required this.link});

  final SpoolSupplierLink link;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final details = supplierLinkDetails(l10n, link);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DashSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: _detailIconNudge),
            child: Icon(
              link.isPurchaseSource
                  ? Icons.shopping_bag_outlined
                  : Icons.storefront_outlined,
              size: 16,
              color: link.isPurchaseSource ? t.accentGreenInk : t.textSecondary,
            ),
          ),
          const SizedBox(width: DashSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        link.supplierName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodyBold.copyWith(color: t.textPrimary),
                      ),
                    ),
                    if (link.isPurchaseSource) ...[
                      const SizedBox(width: DashSpace.sm),
                      DashPill(
                        dense: true,
                        label: l10n.inventorySupplierBoughtHere,
                        accent: t.accentGreen,
                        accentInk: t.accentGreenInk,
                      ),
                    ],
                  ],
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: DashSpace.xs),
                  Text(
                    details,
                    style: t.label.copyWith(color: t.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What the user noted about buying at a supplier — its article number and
/// the price quoted there — or an empty string when nothing was.
String supplierLinkDetails(AppLocalizations l10n, SpoolSupplierLink link) => [
  if (link.articleNumber case final number?)
    l10n.inventorySupplierArticleValue(number),
  if (link.quotedPricePerKg case final price?)
    l10n.inventorySupplierQuotedPrice(price.toStringAsFixed(2)),
].join(' · ');
