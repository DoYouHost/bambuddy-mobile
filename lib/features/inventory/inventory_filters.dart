part of 'inventory_screen.dart';

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.filterCount,
    required this.onQuery,
    required this.onOpenFilters,
  });

  final TextEditingController controller;
  final int filterCount;
  final ValueChanged<String> onQuery;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Outer padding is supplied by the enclosing [DashSliverSearchBar].
    return DashSearchField(
      id: 'inventory.search',
      controller: controller,
      hintText: l10n.inventorySearchHint,
      onChanged: onQuery,
      trailing: [
        FilterButton(
          count: filterCount,
          tooltip: l10n.inventoryFilters,
          id: 'inventory.filters',
          onTap: onOpenFilters,
        ),
      ],
    );
  }
}

/// Inventory filter sheet: status, stock, material, brand, location, material
/// number, supplier.
/// Changes saved immediately to [inventoryFiltersProvider] — list below updates live.
/// Options passed from view (values that actually occur).
class _FilterSheet extends ConsumerWidget {
  const _FilterSheet({
    required this.materials,
    required this.brands,
    required this.locations,
    required this.materialNumbers,
    required this.suppliers,
  });

  final List<String> materials;
  final List<String> brands;
  final List<String> locations;
  final List<String> materialNumbers;

  /// Supplier id → name, for the suppliers some spool carries.
  final Map<int, String> suppliers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final filters = ref.watch(inventoryFiltersProvider);
    final notifier = ref.read(inventoryFiltersProvider.notifier);

    Set<T> toggled<T>(Set<T> set, T value) {
      final next = {...set};
      if (!next.remove(value)) next.add(value);
      return next;
    }

    return logTag(
      'sheet.inventory_filters',
      DraggableSheetSurface(
        initialSize: 0.6,
        maxSize: 0.9,
        minSize: 0.35,
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
                Text(l10n.inventoryFilters, style: theme.textTheme.titleLarge),
                const Spacer(),
                if (filters.activeCount > 0)
                  TextButton(
                    onPressed: () => notifier.state = filters.cleared(),
                    child: Text(l10n.inventoryFiltersClear),
                  ).tagged('inventory.filters_clear'),
              ],
            ),
            const SizedBox(height: DashSpace.sm),

            FilterGroupLabel(label: l10n.inventorySortLabel),
            Wrap(
              spacing: DashSpace.sm,
              runSpacing: DashSpace.xs,
              children: [
                for (final sort in InventorySort.values)
                  ChoiceChip(
                    label: Text(_sortLabel(l10n, sort)),
                    selected: filters.sort == sort,
                    onSelected: (_) =>
                        notifier.state = filters.copyWith(sort: sort),
                  ),
              ],
            ),
            if (filters.sort != InventorySort.standard) ...[
              const SizedBox(height: DashSpace.sm),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: true,
                    label: Text(l10n.printLogSortDescending),
                    icon: const Icon(Icons.arrow_downward),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text(l10n.printLogSortAscending),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                ],
                selected: {filters.descending},
                onSelectionChanged: (s) =>
                    notifier.state = filters.copyWith(descending: s.first),
              ),
            ],
            const SizedBox(height: DashSpace.lg),

            FilterGroupLabel(label: l10n.inventoryFilterStatus),
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
            const SizedBox(height: DashSpace.lg),

            FilterGroupLabel(label: l10n.inventoryFilterStock),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(l10n.inventoryStockAll),
                ),
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
              const SizedBox(height: DashSpace.lg),
              FilterGroupLabel(label: l10n.inventoryFilterMaterial),
              _ChipWrap(
                options: materials,
                selected: filters.materials,
                onToggle: (v) => notifier.state = filters.copyWith(
                  materials: toggled(filters.materials, v),
                ),
              ),
            ],
            if (brands.isNotEmpty) ...[
              const SizedBox(height: DashSpace.lg),
              FilterGroupLabel(label: l10n.inventoryFilterBrand),
              _ChipWrap(
                options: brands,
                selected: filters.brands,
                onToggle: (v) => notifier.state = filters.copyWith(
                  brands: toggled(filters.brands, v),
                ),
              ),
            ],
            if (locations.isNotEmpty) ...[
              const SizedBox(height: DashSpace.lg),
              FilterGroupLabel(label: l10n.inventoryLocation),
              _ChipWrap(
                options: locations,
                selected: filters.locations,
                onToggle: (v) => notifier.state = filters.copyWith(
                  locations: toggled(filters.locations, v),
                ),
              ),
            ],
            if (materialNumbers.isNotEmpty) ...[
              const SizedBox(height: DashSpace.lg),
              FilterGroupLabel(label: l10n.inventoryFieldMaterialNumber),
              _ChipWrap(
                options: materialNumbers,
                selected: filters.materialNumbers,
                onToggle: (v) => notifier.state = filters.copyWith(
                  materialNumbers: toggled(filters.materialNumbers, v),
                ),
              ),
            ],
            if (suppliers.isNotEmpty) ...[
              const SizedBox(height: DashSpace.lg),
              FilterGroupLabel(label: l10n.inventorySuppliersTitle),
              Wrap(
                spacing: DashSpace.sm,
                runSpacing: DashSpace.xs,
                children: [
                  for (final MapEntry(key: id, value: name)
                      in (suppliers.entries.toList()..sort(
                        (a, b) => a.value.toLowerCase().compareTo(
                          b.value.toLowerCase(),
                        ),
                      )))
                    FilterChip(
                      label: Text(name),
                      selected: filters.suppliers.contains(id),
                      onSelected: (_) => notifier.state = filters.copyWith(
                        suppliers: toggled(filters.suppliers, id),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _sortLabel(AppLocalizations l10n, InventorySort sort) => switch (sort) {
  InventorySort.standard => l10n.inventorySortStandard,
  InventorySort.usage => l10n.inventorySortUsage,
  InventorySort.added => l10n.inventorySortAdded,
  InventorySort.price => l10n.inventorySortPrice,
  InventorySort.id => l10n.inventorySortId,
};

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
      spacing: DashSpace.sm,
      runSpacing: DashSpace.xs,
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
