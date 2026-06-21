import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/inventory.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import 'inventory_providers.dart';

/// Zakładka „Filamenty" (Faza 1, read-only): magazyn szpul z wyszukiwaniem,
/// przełącznikiem zarchiwizowanych i szczegółami (historia zużycia, slot AMS,
/// kalibracja). Dane przez [inventoryProvider] z backendu wybranego w ustawieniach
/// (natywny/Spoolman). Zarządzanie (CRUD, przypisania) dojdzie w Fazie 2.
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

  /// Filtr po stronie klienta: status (aktywne/zarchiwizowane), zapas, materiał,
  /// marka, lokalizacja oraz szukanie po materiale/marce/kolorze/lokalizacji
  /// (case-insensitive). Puste zbiory w [filters] = brak ograniczenia.
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

  /// Otwiera arkusz filtrów. Opcje (materiały/marki/lokalizacje) liczymy z pełnej
  /// listy szpul, żeby pokazać tylko realnie występujące wartości.
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

  /// Posortowane, niepuste, unikalne wartości pola — do listy opcji filtra.
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
      // Wspólna wysokość obu elementów, żeby pole i przycisk się równały.
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

/// Kwadratowy przycisk otwierający arkusz filtrów; plakietka pokazuje liczbę
/// aktywnych filtrów. Wyrównany rozmiarem do pola wyszukiwania (48×48).
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

/// Arkusz filtrów magazynu: status, zapas, materiał, marka, lokalizacja.
/// Zmiany zapisujemy od razu w [inventoryFiltersProvider] — lista pod spodem
/// odświeża się na żywo. Opcje przekazane z widoku (realnie występujące wartości).
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

/// Etykieta miejsca, w którym siedzi szpula. Realny slot AMS → „AMS0 · 2".
/// Szpula zewnętrzna (id 254/255) NIE jest jednostką AMS — pokazujemy ekstruder
/// (lewy/prawy), spójnie z dashboardem; mapowanie z [SpoolAssignment.extruder].
String assignmentSlotLabel(AppLocalizations l10n, SpoolAssignment a) {
  if (!a.isExternalSpool) return a.slotLabel;
  return switch (a.extruder) {
    1 => l10n.extruderLeft,
    0 => l10n.extruderRight,
    _ => l10n.externalSpool,
  };
}

/// Kwadratowy swatch koloru szpuli. `rgba` to zwykle hex `RRGGBBAA` (jak kolory
/// AMS) albo `#RRGGBB`; gdy nieznany, rysujemy neutralny placeholder.
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

/// Parsuje kolor szpuli z `RRGGBBAA` / `RRGGBB` (z opcjonalnym `#`).
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
                    Text(spool.displayName, style: theme.textTheme.titleLarge),
                    if (spool.colorName != null)
                      Text(spool.colorName!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Waga / pozostało.
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

          // Przypisanie do slotu AMS.
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

          // Kalibracja K.
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

          // Historia zużycia.
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
    // ListView, by RefreshIndicator działał także przy pustym stanie.
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
