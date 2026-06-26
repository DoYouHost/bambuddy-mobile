import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/inventory.dart';
import '../../core/models/inventory_reference.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../dashboard/providers.dart';
import '../dashboard/ws_providers.dart';
import 'inventory_providers.dart';
import 'spool_scanner_screen.dart';

/// Scans a spool QR code and opens its detail card (NOT edit mode).
/// Scanner returns id (parsed from URL `?spool=`); we find the spool in the loaded
/// list (includes archived, so it should be there). Newly added on server is fetched
/// with one refresh; if still missing, we report it. Shared by Filaments FAB and
/// home screen widget (scanner button), hence top-level function (not screen method).
Future<void> scanSpoolFlow(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final id = await Navigator.of(context, rootNavigator: true).push<int>(
    MaterialPageRoute(builder: (_) => const SpoolScannerScreen()),
  );
  if (id == null || !context.mounted) return;

  Spool? findSpool() {
    final spools = ref.read(inventoryProvider).valueOrNull?.spools ?? const [];
    for (final s in spools) {
      if (s.id == id) return s;
    }
    return null;
  }

  var spool = findSpool();
  if (spool == null) {
    await ref.read(inventoryProvider.notifier).refresh();
    spool = findSpool();
  }
  if (!context.mounted) return;
  if (spool == null) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.inventoryScanNotFound(id))),
    );
    return;
  }
  final assignment =
      ref.read(inventoryProvider).valueOrNull?.assignmentFor(spool.id);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SpoolDetailSheet(spool: spool!, assignment: assignment),
  );
}

/// Filaments tab (Phase 1, read-only): spool inventory with search, archived toggle,
/// and details (usage history, AMS slot, calibration). Data from [inventoryProvider]
/// via selected backend (native/Spoolman). Management (CRUD, assignments) comes in Phase 2.
class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(inventoryProvider);
    final query = ref.watch(inventoryQueryProvider);
    final filters = ref.watch(inventoryFiltersProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navFilaments)),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'scanSpool',
            onPressed: () => _scanSpool(context, ref),
            tooltip: l10n.inventoryScanSpool,
            child: const Icon(Icons.qr_code_scanner),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'addSpool',
            onPressed: () => openSpoolForm(context),
            icon: const Icon(Icons.add),
            label: Text(l10n.inventoryAddSpool),
          ),
        ],
      ),
      body: async.when(
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorView(
          message: err is AppApiException
              ? err.localized(l10n)
              : l10n.connectFailed,
          onRetry: () => ref.read(inventoryProvider.notifier).refresh(),
          retryLabel: l10n.retry,
        ),
        data: (inv) {
          final spools = _filter(inv.spools, query, filters);
          return Column(
            children: [
              _SearchBar(
                query: query,
                filterCount: filters.activeCount,
                onQuery: (v) =>
                    ref.read(inventoryQueryProvider.notifier).state = v,
                onOpenFilters: () => _openFilters(context, inv.spools),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () =>
                      ref.read(inventoryProvider.notifier).refresh(),
                  child: spools.isEmpty
                      ? _EmptyView(
                          message: inv.spools.isEmpty
                              ? l10n.inventoryEmpty
                              : l10n.inventoryNoMatches,
                        )
                      : ListView.builder(
                          itemCount: spools.length + 1,
                          itemBuilder: (context, i) {
                            if (i == 0) {
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                                child: Text(
                                  l10n.inventorySpoolCount(spools.length),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              );
                            }
                            final spool = spools[i - 1];
                            return _SpoolTile(
                              spool: spool,
                              assignment: inv.assignmentFor(spool.id),
                            );
                          },
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Client-side filter: status (active/archived), stock, material, brand, location,
  /// and search by material/brand/color/location (case-insensitive). Empty sets in
  /// [filters] = no restriction.
  List<Spool> _filter(List<Spool> spools, String query, InventoryFilters filters) {
    final q = query.trim().toLowerCase();
    return [
      for (final s in spools)
        if (filters.showArchived ? s.isArchived : !s.isArchived)
          if (!filters.lowStockOnly || s.isLowStock)
            if (filters.materials.isEmpty ||
                filters.materials.contains(s.material))
              if (filters.brands.isEmpty ||
                  (s.brand != null && filters.brands.contains(s.brand)))
                if (filters.locations.isEmpty ||
                    (s.storageLocation != null &&
                        filters.locations.contains(s.storageLocation)))
                  if (q.isEmpty || _matches(s, q)) s,
    ];
  }

  /// Scans a spool QR code and opens its detail card (NOT edit mode).
  /// Delegates to [scanSpoolFlow], shared with the home screen widget.
  Future<void> _scanSpool(BuildContext context, WidgetRef ref) =>
      scanSpoolFlow(context, ref);

  /// Opens the filter sheet. Options (materials/brands/locations) counted from the
  /// full spool list to show only actually occurring values.
  void _openFilters(BuildContext context, List<Spool> all) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FilterSheet(
        materials: _distinct(all.map((s) => s.material)),
        brands: _distinct(all.map((s) => s.brand)),
        locations: _distinct(all.map((s) => s.storageLocation)),
      ),
    );
  }

  /// Sorted, non-empty, unique field values — for filter option list.
  List<String> _distinct(Iterable<String?> values) {
    final set = <String>{
      for (final v in values)
        if (v != null && v.trim().isNotEmpty) v,
    };
    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  bool _matches(Spool s, String q) {
    for (final field in [
      s.material,
      s.subtype,
      s.brand,
      s.colorName,
      s.storageLocation,
      s.category,
    ]) {
      if (field != null && field.toLowerCase().contains(q)) return true;
    }
    return false;
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.query,
    required this.filterCount,
    required this.onQuery,
    required this.onOpenFilters,
  });

  final String query;
  final int filterCount;
  final ValueChanged<String> onQuery;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      // Common height for both elements so field and button align.
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  prefixIcon: const Icon(Icons.search),
                  hintText: l10n.inventorySearchHint,
                  border: const OutlineInputBorder(),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => onQuery(''),
                        ),
                ),
                onChanged: onQuery,
              ),
            ),
            const SizedBox(width: 8),
            _FilterButton(count: filterCount, onTap: onOpenFilters),
          ],
        ),
      ),
    );
  }
}

/// Square button opening the filter sheet; badge shows count of active filters.
/// Size matches search field (48×48).
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = count > 0;
    return Tooltip(
      message: AppLocalizations.of(context).inventoryFilters,
      child: Badge(
        isLabelVisible: active,
        label: Text('$count'),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Material(
            color: active
                ? scheme.secondaryContainer
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: Icon(
                Icons.tune,
                color: active
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Inventory filter sheet: status, stock, material, brand, location.
/// Changes saved immediately to [inventoryFiltersProvider] — list below updates live.
/// Options passed from view (values that actually occur).
class _FilterSheet extends ConsumerWidget {
  const _FilterSheet({
    required this.materials,
    required this.brands,
    required this.locations,
  });

  final List<String> materials;
  final List<String> brands;
  final List<String> locations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final filters = ref.watch(inventoryFiltersProvider);
    final notifier = ref.read(inventoryFiltersProvider.notifier);

    Set<String> toggled(Set<String> set, String value) {
      final next = {...set};
      if (!next.remove(value)) next.add(value);
      return next;
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.35,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Row(
            children: [
              Text(l10n.inventoryFilters, style: theme.textTheme.titleLarge),
              const Spacer(),
              if (filters.activeCount > 0)
                TextButton(
                  onPressed: () =>
                      notifier.state = const InventoryFilters(),
                  child: Text(l10n.inventoryFiltersClear),
                ),
            ],
          ),
          const SizedBox(height: 8),

          _FilterGroup(label: l10n.inventoryFilterStatus),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: false,
                label: Text(l10n.inventoryStatusActive),
                icon: const Icon(Icons.inventory_2_outlined),
              ),
              ButtonSegment(
                value: true,
                label: Text(l10n.inventoryStatusArchived),
                icon: const Icon(Icons.archive_outlined),
              ),
            ],
            selected: {filters.showArchived},
            onSelectionChanged: (s) =>
                notifier.state = filters.copyWith(showArchived: s.first),
          ),
          const SizedBox(height: 16),

          _FilterGroup(label: l10n.inventoryFilterStock),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(l10n.inventoryStockAll)),
              ButtonSegment(
                value: true,
                label: Text(l10n.inventoryStockLow),
                icon: const Icon(Icons.warning_amber_outlined),
              ),
            ],
            selected: {filters.lowStockOnly},
            onSelectionChanged: (s) =>
                notifier.state = filters.copyWith(lowStockOnly: s.first),
          ),

          if (materials.isNotEmpty) ...[
            const SizedBox(height: 16),
            _FilterGroup(label: l10n.inventoryFilterMaterial),
            _ChipWrap(
              options: materials,
              selected: filters.materials,
              onToggle: (v) => notifier.state =
                  filters.copyWith(materials: toggled(filters.materials, v)),
            ),
          ],
          if (brands.isNotEmpty) ...[
            const SizedBox(height: 16),
            _FilterGroup(label: l10n.inventoryFilterBrand),
            _ChipWrap(
              options: brands,
              selected: filters.brands,
              onToggle: (v) => notifier.state =
                  filters.copyWith(brands: toggled(filters.brands, v)),
            ),
          ],
          if (locations.isNotEmpty) ...[
            const SizedBox(height: 16),
            _FilterGroup(label: l10n.inventoryLocation),
            _ChipWrap(
              options: locations,
              selected: filters.locations,
              onToggle: (v) => notifier.state =
                  filters.copyWith(locations: toggled(filters.locations, v)),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterGroup extends StatelessWidget {
  const _FilterGroup({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _ChipWrap extends StatelessWidget {
  const _ChipWrap({
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final o in options)
          FilterChip(
            label: Text(o),
            selected: selected.contains(o),
            onSelected: (_) => onToggle(o),
          ),
      ],
    );
  }
}

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
                  ? theme.textTheme.titleMedium
                      ?.copyWith(color: theme.disabledColor)
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
            _Badge(
              label: l10n.inventoryArchived,
              color: theme.disabledColor,
            ),
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
                l10n.inventoryRemaining(spool.remainingWeight.toStringAsFixed(0)),
                style: theme.textTheme.bodySmall,
              ),
              if (spool.labelWeight > 0) ...[
                const SizedBox(width: 4),
                Text(
                  l10n.inventoryOfTotal(spool.labelWeight),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
              if (assignment != null) ...[
                const Spacer(),
                Icon(Icons.print_outlined,
                    size: 13, color: theme.colorScheme.onSurfaceVariant),
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
          ? Icon(Icons.question_mark,
              size: size * 0.5, color: scheme.onSurfaceVariant)
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
                          child: Text(spool.displayName,
                              style: theme.textTheme.titleLarge),
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
                      Text(spool.colorName!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
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
              label: l10n.inventoryCostPerKg(spool.costPerKg!.toStringAsFixed(2)),
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
              child: Text(l10n.inventoryUsageEmpty,
                  style: theme.textTheme.bodySmall),
            ),
            data: (entries) => entries.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(l10n.inventoryUsageEmpty,
                        style: theme.textTheme.bodySmall),
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
                                e.weightUsed.toStringAsFixed(0)),
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

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    // ListView so RefreshIndicator works when empty.
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(Icons.inventory_2_outlined,
            size: 48, color: Theme.of(context).disabledColor),
        const SizedBox(height: 12),
        Center(child: Text(message)),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.retryLabel,
  });

  final String message;
  final VoidCallback onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}

/// Opens spool create/edit sheet. [existing] != null → edit mode.
void openSpoolForm(BuildContext context, {Spool? existing}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SpoolFormSheet(existing: existing),
  );
}

/// Opens spool-to-slot assignment sheet (AMS or external extruder) —
/// reverse flow from dashboard chip: spool is known, we pick a slot.
/// Available when spool is not yet assigned anywhere.
void _openAssignSheet(BuildContext context, Spool spool) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AssignSheet(spool: spool),
  );
}

/// Printer and slot picker for assigning [spool]. Printer list from dashboard roster;
/// slot layout (AMS units, dual-extruder) fetched from live status if available —
/// for offline printer, fall back to manual number entry (assignment is DB operation,
/// works even with machine off). External spool convention: `ams_id=255`,
/// `tray_id` 0=left, 1=right ([[inventory-filaments]]).
class _AssignSheet extends ConsumerStatefulWidget {
  const _AssignSheet({required this.spool});

  final Spool spool;

  @override
  ConsumerState<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends ConsumerState<_AssignSheet> {
  int? _printerId;
  bool _external = false;
  int _amsUnit = 0;
  int _amsSlot = 0;
  int _externalTray = 0; // 0 = lewy, 1 = prawy
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final roster = ref.watch(dashboardProvider).printers ?? const [];

    // Default printer: first from roster (once, while nothing chosen).
    if (_printerId == null && roster.isNotEmpty) {
      _printerId = roster.first.printer.id;
    }

    final status = _printerId == null
        ? null
        : ref.watch(printerStatusesProvider)[_printerId];
    final dual = status?.isDualExtruder ?? false;
    // AMS units detected live (their ids) — if none, provide 0..3.
    final unitIds = (status?.ams ?? const [])
        .map((u) => u.id ?? 0)
        .toSet()
        .toList()
      ..sort();
    final unitOptions = unitIds.isNotEmpty ? unitIds : const [0, 1, 2, 3];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(l10n.inventoryAssignTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(widget.spool.displayName,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),

          if (roster.isEmpty)
            Text(l10n.inventoryAssignNoPrinters)
          else ...[
            Text(l10n.inventoryAssignPrinter,
                style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              initialValue: _printerId,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(), isDense: true),
              items: [
                for (final p in roster)
                  DropdownMenuItem(
                      value: p.printer.id, child: Text(p.printer.name)),
              ],
              onChanged: (v) => setState(() => _printerId = v),
            ),
            const SizedBox(height: 16),

            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(l10n.inventorySlotAms)),
                ButtonSegment(
                    value: true, label: Text(l10n.externalSpool)),
              ],
              selected: {_external},
              onSelectionChanged: (s) => setState(() => _external = s.first),
            ),
            const SizedBox(height: 16),

            if (_external) ...[
              if (dual) ...[
                Text(l10n.inventoryAssignExtruder,
                    style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                SegmentedButton<int>(
                  segments: [
                    ButtonSegment(value: 0, label: Text(l10n.extruderLeft)),
                    ButtonSegment(value: 1, label: Text(l10n.extruderRight)),
                  ],
                  selected: {_externalTray},
                  onSelectionChanged: (s) =>
                      setState(() => _externalTray = s.first),
                ),
              ] else
                Text(l10n.inventoryAssignExternalHint,
                    style: theme.textTheme.bodyMedium),
            ] else
              Row(
                children: [
                  Expanded(
                    child: _NumberDropdown(
                      label: l10n.inventoryAssignUnit,
                      value: unitOptions.contains(_amsUnit)
                          ? _amsUnit
                          : unitOptions.first,
                      // Display 1-based, value is unit id.
                      items: {for (final u in unitOptions) u: '${u + 1}'},
                      onChanged: (v) => setState(() => _amsUnit = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NumberDropdown(
                      label: l10n.inventoryAssignSlot,
                      value: _amsSlot,
                      items: {for (var s = 0; s < 4; s++) s: '${s + 1}'},
                      onChanged: (v) => setState(() => _amsSlot = v),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 24),

            FilledButton.icon(
              onPressed: _saving || _printerId == null ? null : _assign,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_link, size: 18),
              label: Text(l10n.inventoryAssignConfirm),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _assign() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final printerId = _printerId;
    if (printerId == null) return;
    final draft = SpoolAssignmentDraft(
      spoolId: widget.spool.id,
      printerId: printerId,
      amsId: _external ? 255 : _amsUnit,
      trayId: _external ? _externalTray : _amsSlot,
    );
    setState(() => _saving = true);
    try {
      await ref.read(inventoryProvider.notifier).assignSpool(draft);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger
          .showSnackBar(SnackBar(content: Text(l10n.inventorySpoolAssigned)));
    } on AppApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(e.localized(l10n))));
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.inventoryActionFailed)));
    }
  }
}

/// Numeric dropdown (label above field) — int with display label map.
class _NumberDropdown extends StatelessWidget {
  const _NumberDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final int value;
  final Map<int, String> items;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        DropdownButtonFormField<int>(
          initialValue: value,
          decoration: const InputDecoration(
              border: OutlineInputBorder(), isDense: true),
          items: [
            for (final e in items.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => v == null ? null : onChanged(v),
        ),
      ],
    );
  }
}

/// Action row in spool details: edit, reset usage, archive/restore, delete.
/// Each action closes the sheet first, then calls mutation on [inventoryProvider]
/// (which reloads the list itself) and reports result via snackbar.
/// Destructive actions (delete, reset) need dialog confirmation.
class _SpoolActions extends ConsumerWidget {
  const _SpoolActions({required this.spool, this.assignment});

  final Spool spool;
  final SpoolAssignment? assignment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        FilledButton.tonalIcon(
          onPressed: () {
            Navigator.of(context).pop();
            openSpoolForm(context, existing: spool);
          },
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: Text(l10n.inventoryEdit),
        ),
        if (!spool.isArchived)
          if (assignment != null)
            OutlinedButton.icon(
              onPressed: () => _run(
                context,
                ref,
                l10n,
                ref.read(inventoryProvider.notifier).unassignSpool(
                      assignment!.printerId,
                      assignment!.amsId,
                      assignment!.trayId,
                    ),
                l10n.inventorySpoolUnassigned,
              ),
              icon: const Icon(Icons.link_off, size: 18),
              label: Text(l10n.inventoryUnassign),
            )
          else
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _openAssignSheet(context, spool);
              },
              icon: const Icon(Icons.add_link, size: 18),
              label: Text(l10n.inventoryAssign),
            ),
        if (spool.weightUsed > 0)
          OutlinedButton.icon(
            onPressed: () => _resetUsage(context, ref, l10n),
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(l10n.inventoryResetUsage),
          ),
        if (spool.isArchived)
          OutlinedButton.icon(
            onPressed: () => _run(context, ref, l10n,
                ref.read(inventoryProvider.notifier).restoreSpool(spool.id),
                l10n.inventorySpoolRestored),
            icon: const Icon(Icons.unarchive_outlined, size: 18),
            label: Text(l10n.inventoryRestore),
          )
        else
          OutlinedButton.icon(
            onPressed: () => _run(context, ref, l10n,
                ref.read(inventoryProvider.notifier).archiveSpool(spool.id),
                l10n.inventorySpoolArchived),
            icon: const Icon(Icons.archive_outlined, size: 18),
            label: Text(l10n.inventoryArchive),
          ),
        TextButton.icon(
          onPressed: () => _delete(context, ref, l10n),
          icon: Icon(Icons.delete_outline, size: 18, color: scheme.error),
          label: Text(l10n.inventoryDelete,
              style: TextStyle(color: scheme.error)),
        ),
      ],
    );
  }

  Future<void> _resetUsage(
      BuildContext context, WidgetRef ref, AppLocalizations l10n) async {
    final ok = await _confirm(context, l10n.inventoryResetUsage,
        l10n.inventoryResetUsageConfirm, l10n.inventoryResetUsage);
    if (!ok || !context.mounted) return;
    await _run(context, ref, l10n,
        ref.read(inventoryProvider.notifier).resetUsage(spool.id),
        l10n.inventoryUsageReset);
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, AppLocalizations l10n) async {
    final ok = await _confirm(context, l10n.inventoryDeleteTitle,
        l10n.inventoryDeleteConfirm(spool.displayName), l10n.inventoryDelete,
        destructive: true);
    if (!ok || !context.mounted) return;
    await _run(context, ref, l10n,
        ref.read(inventoryProvider.notifier).deleteSpool(spool.id),
        l10n.inventorySpoolDeleted);
  }

  /// Closes sheet, waits for [action], reports result to parent ScaffoldMessenger
  /// (captured before pop, since sheet context disappears).
  Future<void> _run(BuildContext context, WidgetRef ref, AppLocalizations l10n,
      Future<void> action, String successMsg) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    try {
      await action;
      messenger.showSnackBar(SnackBar(content: Text(successMsg)));
    } on AppApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.localized(l10n))));
    } on Object {
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.inventoryActionFailed)));
    }
  }
}

/// Simple confirmation dialog. Returns true if user confirmed.
Future<bool> _confirm(BuildContext context, String title, String message,
    String confirmLabel,
    {bool destructive = false}) async {
  final l10n = AppLocalizations.of(context);
  final scheme = Theme.of(context).colorScheme;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: scheme.error)
              : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Spool create/edit sheet. Text fields + validation; save via [inventoryProvider]
/// (create if [existing] == null, else update). Empty numeric fields → null
/// (server uses defaults). Color previewed live.
class _SpoolFormSheet extends ConsumerStatefulWidget {
  const _SpoolFormSheet({this.existing});

  final Spool? existing;

  @override
  ConsumerState<_SpoolFormSheet> createState() => _SpoolFormSheetState();
}

/// Fixed filament effects for dropdown (None + popular).
const _effectOptions = [
  'Silk', 'Matte', 'Glow', 'Sparkle', 'Marble', 'Metal', 'Dual', 'Gradient',
];

class _SpoolFormSheetState extends ConsumerState<_SpoolFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c;
  int? _coreWeightCatalogId;
  String? _effectType;
  String _colorQuery = '';
  bool _materialMissing = false;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    String n(num? v) => v == null ? '' : v.toString();
    // Remaining weight = label − used. For new spool, default full 1000 g.
    final remaining = s == null ? '1000' : n(s.remainingWeight.round());
    _c = {
      'material': TextEditingController(text: s?.material ?? ''),
      'brand': TextEditingController(text: s?.brand ?? ''),
      'subtype': TextEditingController(text: s?.subtype ?? ''),
      'colorName': TextEditingController(text: s?.colorName ?? ''),
      'rgba': TextEditingController(text: s?.rgba ?? ''),
      'extraColors': TextEditingController(text: s?.extraColors ?? ''),
      'labelWeight':
          TextEditingController(text: s == null ? '1000' : n(s.labelWeight)),
      'remaining': TextEditingController(text: remaining),
      'measured': TextEditingController(text: n(s?.lastScaleWeight)),
      'coreWeight': TextEditingController(text: n(s?.coreWeight ?? 250)),
      'costPerKg': TextEditingController(text: n(s?.costPerKg)),
      'category': TextEditingController(text: s?.category ?? ''),
      'lowStock': TextEditingController(text: n(s?.lowStockThresholdPct)),
      'location': TextEditingController(text: s?.storageLocation ?? ''),
      'note': TextEditingController(text: s?.note ?? ''),
    };
    _coreWeightCatalogId = s?.coreWeightCatalogId;
    _effectType = s?.effectType;
    // Swatch preview updates when hex changes.
    _c['rgba']!.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _trim(String key) {
    final v = _c[key]!.text.trim();
    return v.isEmpty ? null : v;
  }

  /// Measured weight is gross (filament + empty spool/core). After entering scale
  /// reading, calculate remaining filament: remaining = measured − empty spool weight.
  /// This ensures save (weight_used = label − remaining) actually changes spool state —
  /// without it, the reading alone wouldn't update anything.
  void _applyScaleWeight(String raw) {
    final measured = double.tryParse(raw.trim());
    if (measured == null) return;
    final core = double.tryParse(_c['coreWeight']!.text.trim()) ?? 0;
    final remaining = (measured - core).clamp(0, double.infinity);
    _c['remaining']!.text = remaining.round().toString();
    setState(() {});
  }

  /// Sets color from database (hex + name + optional gradient/effect).
  void _applyColor(ColorEntry e) {
    setState(() {
      _c['rgba']!.text = e.hexColor;
      _c['colorName']!.text = e.colorName;
      _c['extraColors']!.text = e.extraColors ?? '';
      _effectType = e.effectType;
    });
  }

  Future<void> _save() async {
    final material = _c['material']!.text.trim();
    final formOk = _formKey.currentState!.validate();
    if (material.isEmpty) {
      setState(() => _materialMissing = true);
    }
    if (!formOk || material.isEmpty) return;

    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // Server requires low-stock threshold in range 1..99 (outside = 422).
    final lowStock = int.tryParse(_c['lowStock']!.text.trim())?.clamp(1, 99);
    final label = int.tryParse(_c['labelWeight']!.text.trim());
    final remaining = double.tryParse(_c['remaining']!.text.trim());
    // Remaining weight controls usage: weight_used = label − remaining.
    double? used;
    if (remaining != null && label != null) {
      used = (label - remaining).clamp(0, label).toDouble();
    } else if (_isEdit && remaining == null) {
      used = widget.existing!.weightUsed;
    }
    final draft = SpoolDraft(
      material: material,
      brand: _trim('brand'),
      subtype: _trim('subtype'),
      colorName: _trim('colorName'),
      rgba: normalizeRgba(_c['rgba']!.text),
      extraColors: _trim('extraColors'),
      effectType: _effectType,
      labelWeight: label,
      weightUsed: used,
      coreWeight: int.tryParse(_c['coreWeight']!.text.trim()),
      coreWeightCatalogId: _coreWeightCatalogId,
      lastScaleWeight: int.tryParse(_c['measured']!.text.trim()),
      costPerKg: double.tryParse(_c['costPerKg']!.text.trim()),
      category: _trim('category'),
      lowStockThresholdPct: lowStock,
      storageLocation: _trim('location'),
      note: _trim('note'),
    );
    setState(() => _saving = true);
    final notifier = ref.read(inventoryProvider.notifier);
    try {
      if (_isEdit) {
        await notifier.updateSpool(widget.existing!.id, draft);
      } else {
        await notifier.createSpool(draft);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(
        content: Text(
            _isEdit ? l10n.inventorySpoolUpdated : l10n.inventorySpoolCreated),
      ));
    } on AppApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(e.localized(l10n))));
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(l10n.inventorySaveFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final materials = ref.watch(materialOptionsProvider);
    final brands = ref.watch(brandOptionsProvider);
    final subtypes = ref.watch(subtypeOptionsProvider);
    final cores = ref.watch(coreWeightsProvider).valueOrNull ?? const [];
    final labelInt = int.tryParse(_c['labelWeight']!.text.trim());

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, controller) => Form(
        key: _formKey,
        child: ListView(
          controller: controller,
          padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + bottomInset),
          children: [
            Row(
              children: [
                SpoolSwatch(rgba: _c['rgba']!.text, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isEdit ? l10n.inventoryEditSpool : l10n.inventoryNewSpool,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // --- FILAMENT ---
            _FormSection(label: l10n.inventorySectionFilament),
            _combo('material', l10n.inventoryFieldMaterial, materials,
                required: true, errorText: _materialMissing ? l10n.inventoryFieldRequired : null),
            _combo('brand', l10n.inventoryFieldBrand, brands),
            _combo('subtype', l10n.inventoryFieldSubtype, subtypes),
            _field('labelWeight', l10n.inventoryFieldLabelWeight,
                number: true, onChanged: (_) => setState(() {})),

            const SizedBox(height: 8),

            // --- COLOR ---
            _FormSection(label: l10n.inventorySectionColor),
            _ColorPicker(
              rgba: _c['rgba']!.text,
              query: _colorQuery,
              onQuery: (v) => setState(() => _colorQuery = v),
              onPick: _applyColor,
            ),
            Row(
              children: [
                Expanded(
                  child: _field('colorName', l10n.inventoryFieldColorName),
                ),
                const SizedBox(width: 12),
                Expanded(child: _hexColorPickerField(l10n)),
              ],
            ),
            _field('extraColors', l10n.inventoryFieldExtraColors,
                hint: l10n.inventoryExtraColorsHint),
            _effectDropdown(l10n),

            const SizedBox(height: 8),

            // --- ADDITIONAL ---
            _FormSection(label: l10n.inventorySectionAdditional),
            _emptySpoolField(l10n, cores),
            _field('remaining', l10n.inventoryFieldRemainingWeight,
                number: true,
                suffixText:
                    labelInt != null ? l10n.inventoryRemainingOfLabel(labelInt) : null),
            _field('measured', l10n.inventoryFieldMeasuredWeight,
                number: true, onChanged: _applyScaleWeight),
            _field('costPerKg', l10n.inventoryFieldCostPerKg, number: true),
            _field('category', l10n.inventoryFieldCategory),
            _field('lowStock', l10n.inventoryFieldLowStock,
                number: true, hint: l10n.inventoryLowStockHint),
            _field('location', l10n.inventoryFieldLocation),
            _field('note', l10n.inventoryFieldNote, maxLines: 3),

            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.inventorySave),
            ),
          ],
        ),
      ),
    );
  }

  /// Editable combo (dropdown with filtering + custom entry) for material/brand/variant.
  /// Value held by controller — entry outside list is kept.
  Widget _combo(String key, String label, List<String> options,
      {bool required = false, String? errorText}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: DropdownMenu<String>(
        controller: _c[key],
        label: Text(required ? '$label *' : label),
        expandedInsets: EdgeInsets.zero,
        enableFilter: true,
        requestFocusOnTap: true,
        menuHeight: 320,
        errorText: errorText,
        onSelected: (v) {
          if (required && v != null && v.isNotEmpty) {
            setState(() => _materialMissing = false);
          }
        },
        dropdownMenuEntries: [
          for (final o in options) DropdownMenuEntry(value: o, label: o),
        ],
      ),
    );
  }

  /// Empty Spool Weight field: dropdown from core catalog (sets weight + id)
  /// beside editable weight in grams. If catalog empty — weight only.
  Widget _emptySpoolField(AppLocalizations l10n, List<CoreWeightEntry> cores) {
    final weightField = SizedBox(
      width: cores.isEmpty ? null : 110,
      child: TextFormField(
        controller: _c['coreWeight'],
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'g',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (_) => setState(() => _coreWeightCatalogId = null),
      ),
    );
    if (cores.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: l10n.inventoryFieldEmptySpoolWeight,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          child: weightField,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: DropdownButtonFormField<int?>(
              initialValue: _coreWeightCatalogId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.inventoryFieldEmptySpoolWeight,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final c in cores)
                  DropdownMenuItem(
                    value: c.id,
                    child: Text(c.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (id) {
                final entry = cores.where((c) => c.id == id).firstOrNull;
                setState(() {
                  _coreWeightCatalogId = id;
                  if (entry != null) {
                    _c['coreWeight']!.text = entry.weight.toString();
                  }
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          weightField,
        ],
      ),
    );
  }

  Widget _effectDropdown(AppLocalizations l10n) {
    final options = <String>{..._effectOptions, ?_effectType};
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: DropdownButtonFormField<String?>(
        initialValue: _effectType,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: l10n.inventoryFieldEffect,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          DropdownMenuItem(value: null, child: Text(l10n.inventoryEffectNone)),
          for (final e in options) DropdownMenuItem(value: e, child: Text(e)),
        ],
        onChanged: (v) => setState(() => _effectType = v),
      ),
    );
  }

  /// Color field: instead of manual hex entry, opens color picker (HSV wheel + hex bar).
  /// On selection, writes hex `RRGGBBAA` to `rgba` controller (alpha preserved
  /// from previous value, default `FF`).
  Widget _hexColorPickerField(AppLocalizations l10n) {
    final hex = _c['rgba']!.text.trim();
    final color = parseSpoolColor(hex);
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => _openColorPicker(l10n),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: l10n.inventoryFieldColorHex,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: const Icon(Icons.colorize),
        ),
        child: Row(
          children: [
            SpoolSwatch(rgba: hex.isEmpty ? null : hex, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hex.isEmpty ? l10n.inventoryColorNone : hex.toUpperCase(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: color == null
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : null,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Color picker dialog. Starts from current color (or white), saves chosen hex
  /// `RRGGBBAA` to `rgba` field on confirm. Preserves existing alpha byte (usually `FF`) —
  /// picker edits RGB only, so we don't lose spool alpha (if ever non-full).
  Future<void> _openColorPicker(AppLocalizations l10n) async {
    final rawCurrent = _c['rgba']!.text.trim().replaceFirst('#', '');
    final alphaHex =
        rawCurrent.length == 8 ? rawCurrent.substring(6, 8).toUpperCase() : 'FF';
    var picked = parseSpoolColor(_c['rgba']!.text) ?? const Color(0xFFFFFFFF);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.inventoryColorPickTitle),
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: picked,
            onColorChanged: (c) => picked = c,
            enableAlpha: false,
            hexInputBar: true,
            labelTypes: const [],
            portraitOnly: true,
            pickerAreaHeightPercent: 0.7,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.inventoryColorSelect),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() {
        _c['rgba']!.text = colorToHex(picked, enableAlpha: false) + alphaHex;
      });
    }
  }

  Widget _field(
    String key,
    String label, {
    bool number = false,
    String? hint,
    String? suffixText,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: _c[key],
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true)
            : (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
        maxLines: maxLines,
        textCapitalization:
            number ? TextCapitalization.none : TextCapitalization.sentences,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          suffixText: suffixText,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        validator: (v) {
          final text = (v ?? '').trim();
          if (number && text.isNotEmpty && double.tryParse(text) == null) {
            return l10n.inventoryFieldInvalidNumber;
          }
          return null;
        },
      ),
    );
  }
}

/// Color picker: large preview + popular swatches from database + search.
/// Tap color fills hex/name/gradient/effect in form (via [onPick]).
class _ColorPicker extends ConsumerWidget {
  const _ColorPicker({
    required this.rgba,
    required this.query,
    required this.onQuery,
    required this.onPick,
  });

  final String rgba;
  final String query;
  final ValueChanged<String> onQuery;
  final ValueChanged<ColorEntry> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = ref.watch(colorCatalogProvider).valueOrNull ?? const [];
    final preview = parseSpoolColor(rgba);

    final q = query.trim().toLowerCase();
    final List<ColorEntry> shown;
    if (q.isEmpty) {
      shown = colors.where((c) => c.isDefault).take(18).toList();
    } else {
      shown = colors
          .where((c) =>
              c.colorName.toLowerCase().contains(q) ||
              c.manufacturer.toLowerCase().contains(q) ||
              (c.material?.toLowerCase().contains(q) ?? false))
          .take(24)
          .toList();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 40,
          decoration: BoxDecoration(
            color: preview ?? theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
        ),
        const SizedBox(height: 8),
        if (colors.isNotEmpty) ...[
          TextField(
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              hintText: l10n.inventoryColorSearchHint,
              border: const OutlineInputBorder(),
            ),
            onChanged: onQuery,
          ),
          const SizedBox(height: 8),
          if (q.isEmpty)
            Text(l10n.inventoryColorCommon,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in shown)
                _ColorChip(entry: c, onTap: () => onPick(c)),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ColorChip extends StatelessWidget {
  const _ColorChip({required this.entry, required this.onTap});

  final ColorEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = parseSpoolColor(entry.hexColor);
    return Tooltip(
      message: entry.colorName,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color ?? scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: color == null
              ? Icon(Icons.question_mark, size: 16, color: scheme.onSurfaceVariant)
              : null,
        ),
      ),
    );
  }
}

class _FormSection extends StatelessWidget {
  const _FormSection({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
