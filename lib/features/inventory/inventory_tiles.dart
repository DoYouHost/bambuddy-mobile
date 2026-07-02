part of 'inventory_screen.dart';

class _SpoolTile extends StatelessWidget {
  const _SpoolTile({required this.spool, this.assignment});

  final Spool spool;
  final SpoolAssignment? assignment;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final frac = spool.remainingFraction;

    return ListTile(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _SpoolDetailSheet(spool: spool, assignment: assignment),
      ),
      leading: SpoolSwatch(rgba: spool.rgba),
      title: Row(
        children: [
          _Badge(
            label: spool.material,
            color: spool.isArchived
                ? theme.disabledColor
                : theme.colorScheme.secondary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              spool.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: spool.isArchived
                  ? theme.textTheme.titleMedium?.copyWith(
                      color: theme.disabledColor,
                    )
                  : theme.textTheme.titleMedium,
            ),
          ),
          if (spool.isLowStock && !spool.isArchived) ...[
            const SizedBox(width: 6),
            _Badge(
              label: l10n.inventoryLowStock,
              color: theme.colorScheme.error,
            ),
          ],
          if (spool.isArchived) ...[
            const SizedBox(width: 6),
            _Badge(label: l10n.inventoryArchived, color: theme.disabledColor),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          if (frac != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 6,
                color: spool.isLowStock
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '#${spool.id}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                l10n.inventoryRemaining(
                  spool.remainingWeight.toStringAsFixed(0),
                ),
                style: theme.textTheme.bodySmall,
              ),
              if (spool.labelWeight > 0) ...[
                const SizedBox(width: 4),
                Text(
                  l10n.inventoryOfTotal(spool.labelWeight),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (assignment != null) ...[
                const Spacer(),
                Icon(
                  Icons.print_outlined,
                  size: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    assignmentSlotLabel(l10n, assignment!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      isThreeLine: true,
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
  const SpoolSwatch({super.key, this.rgba, this.size = 36});

  final String? rgba;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = parseSpoolColor(rgba);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color ?? scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: color == null
          ? Icon(
              Icons.question_mark,
              size: size * 0.5,
              color: scheme.onSurfaceVariant,
            )
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

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _SpoolDetailSheet extends ConsumerWidget {
  const _SpoolDetailSheet({required this.spool, this.assignment});

  final Spool spool;
  final SpoolAssignment? assignment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final usage = ref.watch(spoolUsageProvider(spool.id));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Row(
            children: [
              SpoolSwatch(rgba: spool.rgba, size: 48),
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
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '#${spool.id}',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    if (spool.colorName != null)
                      Text(
                        spool.colorName!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          _SpoolActions(spool: spool, assignment: assignment),
          const SizedBox(height: 16),

          if (spool.remainingFraction != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: spool.remainingFraction,
                minHeight: 10,
                color: spool.isLowStock
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${l10n.inventoryRemaining(spool.remainingWeight.toStringAsFixed(0))}'
              ' ${l10n.inventoryOfTotal(spool.labelWeight)}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
          ],

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
              label: '${l10n.inventoryLocation}: ${spool.storageLocation}',
            ),
          if (spool.costPerKg != null)
            _DetailRow(
              icon: Icons.payments_outlined,
              label: l10n.inventoryCostPerKg(
                spool.costPerKg!.toStringAsFixed(2),
              ),
            ),
          if (spool.nozzleTempMin != null || spool.nozzleTempMax != null)
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

          if (spool.kProfiles.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(l10n.inventoryKProfiles, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
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

          const SizedBox(height: 16),
          Text(l10n.inventoryUsageHistory, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          usage.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                l10n.inventoryUsageEmpty,
                style: theme.textTheme.bodySmall,
              ),
            ),
            data: (entries) => entries.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      l10n.inventoryUsageEmpty,
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                : Column(
                    children: [
                      for (final e in entries)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.history, size: 20),
                          title: Text(e.printName ?? '—'),
                          subtitle: e.createdAt != null
                              ? Text(e.createdAt!.split('T').first)
                              : null,
                          trailing: Text(
                            l10n.inventoryUsageWeight(
                              e.weightUsed.toStringAsFixed(0),
                            ),
                            style: theme.textTheme.bodyMedium,
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
