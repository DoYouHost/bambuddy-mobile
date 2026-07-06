import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/inventory.dart';
import '../../core/models/inventory_reference.dart';
import '../../core/models/slicer_preset.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../common/confirm_dialog.dart';
import '../common/state_views.dart';
import '../dashboard/providers.dart';
import '../dashboard/ws_providers.dart';
import '../slicer/slice_providers.dart';
import 'inventory_providers.dart';
import 'spool_scanner_screen.dart';

part 'inventory_filters.dart';
part 'inventory_tiles.dart';
part 'inventory_sheets.dart';
part 'inventory_form.dart';

/// Scans a spool QR code and opens its detail card (NOT edit mode).
/// Scanner returns id (parsed from URL `?spool=`); we find the spool in the loaded
/// list (includes archived, so it should be there). Newly added on server is fetched
/// with one refresh; if still missing, we report it. Shared by Filaments FAB and
/// home screen widget (scanner button), hence top-level function (not screen method).
Future<void> scanSpoolFlow(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final id = await Navigator.of(
    context,
    rootNavigator: true,
  ).push<int>(MaterialPageRoute(builder: (_) => const SpoolScannerScreen()));
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
  final assignment = ref
      .read(inventoryProvider)
      .valueOrNull
      ?.assignmentFor(spool.id);
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
        error: (err, _) => AsyncErrorView(
          message: err is AppApiException
              ? err.localized(l10n)
              : l10n.connectFailed,
          onRetry: () => ref.read(inventoryProvider.notifier).refresh(),
          retryLabel: l10n.retry,
          icon: null,
          tonal: true,
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
                      ? EmptyStateView(
                          message: inv.spools.isEmpty
                              ? l10n.inventoryEmpty
                              : l10n.inventoryNoMatches,
                          icon: Icons.inventory_2_outlined,
                        )
                      : ListView.builder(
                          itemCount: spools.length + 1,
                          itemBuilder: (context, i) {
                            if (i == 0) {
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  4,
                                  16,
                                  8,
                                ),
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
  List<Spool> _filter(
    List<Spool> spools,
    String query,
    InventoryFilters filters,
  ) {
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
