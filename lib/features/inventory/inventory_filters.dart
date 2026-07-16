part of 'inventory_screen.dart';

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.filterCount,
    required this.onQuery,
    required this.onOpenFilters,
  });

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
              child: DashSearchField(
                hintText: l10n.inventorySearchHint,
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
    final t = DashTokens.of(context);
    final active = count > 0;
    return Tooltip(
      message: AppLocalizations.of(context).inventoryFilters,
      child: Badge(
        isLabelVisible: active,
        label: Text('$count'),
        backgroundColor: t.accentGreen,
        textColor: _onAccentGreen,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Material(
            color: active ? t.accentGreen.withValues(alpha: 0.16) : t.subCard,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: active
                        ? t.accentGreen.withValues(alpha: 0.4)
                        : t.subCardBorder,
                  ),
                ),
                child: Icon(
                  Icons.tune,
                  color: active ? t.accentGreenInk : t.textSecondary,
                ),
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
      builder: (context, controller) => _SheetSurface(child: ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Row(
            children: [
              Text(l10n.inventoryFilters, style: theme.textTheme.titleLarge),
              const Spacer(),
              if (filters.activeCount > 0)
                TextButton(
                  onPressed: () => notifier.state = const InventoryFilters(),
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
              onToggle: (v) => notifier.state = filters.copyWith(
                materials: toggled(filters.materials, v),
              ),
            ),
          ],
          if (brands.isNotEmpty) ...[
            const SizedBox(height: 16),
            _FilterGroup(label: l10n.inventoryFilterBrand),
            _ChipWrap(
              options: brands,
              selected: filters.brands,
              onToggle: (v) => notifier.state = filters.copyWith(
                brands: toggled(filters.brands, v),
              ),
            ),
          ],
          if (locations.isNotEmpty) ...[
            const SizedBox(height: 16),
            _FilterGroup(label: l10n.inventoryLocation),
            _ChipWrap(
              options: locations,
              selected: filters.locations,
              onToggle: (v) => notifier.state = filters.copyWith(
                locations: toggled(filters.locations, v),
              ),
            ),
          ],
        ],
      )),
    );
  }
}

class _FilterGroup extends StatelessWidget {
  const _FilterGroup({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: DashTokens.fontUi,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: t.textSecondary,
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
