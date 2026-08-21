part of 'inventory_screen.dart';

/// The line above the shelf: how many spools the filters let through, and how
/// much filament has been consumed since the counters were last reset.
///
/// The two numbers count different things on purpose. [visibleCount] is what
/// the user is looking at, filters and search included; the consumed total runs
/// over the whole [shelf] — **archived spools included** — because it is a
/// running counter and past consumption is real history. Dropping it when a
/// spool is archived would make the total fall for no visible reason, which is
/// the bug bambuddy fixed in its own tile (server issue #1390).
class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.visibleCount, required this.shelf});

  final int visibleCount;
  final List<Spool> shelf;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    var consumed = 0.0;
    for (final spool in shelf) {
      consumed += spool.consumedWeight;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
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
            const SizedBox(width: 8),
            Icon(Icons.trending_down, size: 13, color: t.textTertiary),
            const SizedBox(width: 4),
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

    final metaLine = Row(
      children: [
        Text(
          '#${spool.id} · ${l10n.inventoryRemaining(spool.remainingWeight.toStringAsFixed(0))}'
          '${spool.labelWeight > 0 ? ' / ${spool.labelWeight}g' : ''}',
          style: t.monoLabel,
        ),
        if (assignment != null) ...[
          const Spacer(),
          Icon(Icons.print_outlined, size: 12, color: t.textTertiary),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              assignmentSlotLabel(l10n, assignment!),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.monoLabel,
            ),
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
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
              padding: const EdgeInsets.all(14),
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
                      selected ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 22,
                      color: selected ? t.accentGreenInk : t.textTertiary,
                    ),
                    const SizedBox(width: 10),
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
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  _MaterialTag(label: spool.material, tokens: t),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      spool.displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: t.titleSm.copyWith(color: spool.isArchived
                                            ? t.textTertiary
                                            : t.textPrimary),
                                    ),
                                  ),
                                  if (low) ...[
                                    const SizedBox(width: 6),
                                    _LowBadge(tokens: t),
                                  ],
                                  if (spool.isArchived) ...[
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.archive_outlined,
                                      size: 14,
                                      color: t.textTertiary,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: frac,
                                  minHeight: 4,
                                  backgroundColor: t.gaugeTrack,
                                  valueColor: AlwaysStoppedAnimation(fillColor),
                                ),
                              ),
                              const SizedBox(height: 8),
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.danger.withValues(alpha: 0.5)),
      ),
      child: Text(
        l10n.inventoryLowStock.toUpperCase(),
        style: tokens.micro.copyWith(color: tokens.danger),
      ),
    );
  }
}

/// Label of where a spool sits. Real AMS slot → "AMS0 · 2".
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
        border: Border.all(color: t.subCardBorder),
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

    return logTag(
      'sheet.spool_detail',
      DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (context, controller) => SheetSurface(
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Row(
                children: [
                  SpoolSwatch(rgba: spool.rgba, size: 52, radius: 16),
                  const SizedBox(width: 12),
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
                            const SizedBox(width: 8),
                            Text(
                              '#${spool.id}',
                              style: t.monoHeadline.copyWith(color: t.accentGreenInk),
                            ),
                          ],
                        ),
                        if (spool.colorName != null)
                          Text(
                            spool.colorName!,
                            style: t.bodyPlain,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              _SpoolActions(spool: spool, assignment: assignment),
              const SizedBox(height: 16),

              if (spool.remainingFraction != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: spool.remainingFraction,
                    minHeight: 8,
                    backgroundColor: t.gaugeTrack,
                    valueColor: AlwaysStoppedAnimation(
                      spool.isLowStock ? t.danger : t.accentGreen,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${l10n.inventoryRemaining(spool.remainingWeight.toStringAsFixed(0))}'
                  ' ${l10n.inventoryOfTotal(spool.labelWeight)}',
                  style: t.label.copyWith(color: t.textSecondary),
                ),
                const SizedBox(height: 16),
              ],

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: t.subCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: t.subCardBorder),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DetailRow(
                      icon: Icons.print_outlined,
                      label: assignment != null
                          ? l10n.inventoryLoadedIn(
                              [
                                if (assignment!.printerName != null)
                                  assignment!.printerName!,
                                assignmentSlotLabel(l10n, assignment!),
                              ].join(' · '),
                            )
                          : l10n.inventoryNotLoaded,
                    ),
                    if (spool.storageLocation != null)
                      _DetailRow(
                        icon: Icons.place_outlined,
                        label:
                            '${l10n.inventoryLocation}: ${spool.storageLocation}',
                      ),
                    // The counter the reset action resets. Without it on screen
                    // that action had nothing to show for itself: it moves the
                    // baseline, never the remaining weight above.
                    if (spool.consumedWeight > 0)
                      _DetailRow(
                        icon: Icons.trending_down,
                        label: l10n.inventoryConsumedSinceReset(
                          fmtGrams(spool.consumedWeight),
                        ),
                      ),
                    if (spool.costPerKg != null)
                      _DetailRow(
                        icon: Icons.payments_outlined,
                        label: l10n.inventoryCostPerKg(
                          spool.costPerKg!.toStringAsFixed(2),
                        ),
                      ),
                    if (spool.slicerFilamentName != null ||
                        spool.slicerFilament != null)
                      _DetailRow(
                        icon: Icons.tune,
                        label:
                            '${l10n.inventoryFieldSlicerPreset}: '
                            '${spool.slicerFilamentName ?? spool.slicerFilament}',
                      ),
                    if (spool.nozzleTempMin != null ||
                        spool.nozzleTempMax != null)
                      _DetailRow(
                        icon: Icons.thermostat_outlined,
                        label:
                            '${l10n.inventoryNozzleTemp}: ${spool.nozzleTempMin ?? '?'}–${spool.nozzleTempMax ?? '?'} °C',
                      ),
                    if (spool.tagUid != null)
                      _DetailRow(
                        icon: Icons.nfc_outlined,
                        label: '${l10n.inventoryTag}: ${spool.tagUid}',
                      ),
                    if (spool.note != null)
                      _DetailRow(
                        icon: Icons.sticky_note_2_outlined,
                        label: '${l10n.inventoryNote}: ${spool.note}',
                      ),
                  ],
                ),
              ),

              if (spool.kProfiles.isNotEmpty) ...[
                const SizedBox(height: 16),
                _SheetSectionTitle(label: l10n.inventoryKProfiles),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: t.subCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: t.subCardBorder),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final k in spool.kProfiles)
                        _DetailRow(
                          icon: Icons.tune,
                          label: [
                            if (k.name != null) k.name!,
                            l10n.inventoryKProfileLine(
                              k.nozzleDiameter ?? '?',
                              k.kValue?.toStringAsFixed(3) ?? '?',
                            ),
                          ].join(' · '),
                        ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),
              _SheetSectionTitle(label: l10n.inventoryUsageHistory),
              const SizedBox(height: 4),
              usage.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: DashLoading(),
                ),
                error: (_, _) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    l10n.inventoryUsageEmpty,
                    style: t.labelSoft,
                  ),
                ),
                data: (entries) => entries.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          l10n.inventoryUsageEmpty,
                          style: t.labelSoft,
                        ),
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
      )
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
    return Text(
      label,
      style: t.bodyBold.copyWith(color: t.textPrimary),
    );
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
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.history, size: 16, color: t.textTertiary),
              const SizedBox(width: 8),
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
                        entry.createdAt!.split('T').first,
                        style: t.monoMicro,
                      ),
                  ],
                ),
              ),
              Text(
                l10n.inventoryUsageWeight(entry.weightUsed.toStringAsFixed(0)),
                style: t.monoValue.copyWith(color: t.textSecondary),
              ),
            ],
          ),
          if (!last) ...[
            const SizedBox(height: 8),
            DashedLine(color: t.dottedRule),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: t.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: t.label.copyWith(color: t.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

