import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/models/inventory.dart';
import '../../core/models/inventory_reference.dart';
import '../../core/models/slicer_preset.dart';
import '../../core/models/spool_label.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../common/dash_search_field.dart';
import '../common/sliver_search_bar.dart';
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
part 'inventory_labels.dart';

/// Ink for text/icons painted directly on a solid [DashTokens.accentGreen]
/// fill (e.g. the primary FAB, the save button). Unlike the token pairs above,
/// this isn't theme-adaptive by design — the accent fill itself is a fixed
/// vivid swatch in both brightnesses, so a near-black ink keeps it readable
/// either way.
const Color _onAccentGreen = Color(0xFF08150D);

/// Opaque rounded-top surface for every Filaments bottom sheet. Pairs with
/// `backgroundColor: Colors.transparent` on the enclosing
/// `showModalBottomSheet` — that keeps the framework's drag handle, while
/// this paints the actual dark (or light) sheet fill instead of the default
/// Material `colorScheme.surface`, which doesn't match the "2a" backdrop.
/// Rounded-top surface for a Filaments bottom sheet, with its own grab handle
/// pinned at the top. Used INSIDE each `DraggableScrollableSheet` builder,
/// wrapping the scroll view ([child]) — NOT the framework `showDragHandle`,
/// which detaches from a partial-height draggable sheet and floats in the dim
/// area above it. Gives a distinct top edge (hairline + lift shadow) so the
/// sheet reads as its own surface above the dimmed backdrop.
class _SheetSurface extends StatelessWidget {
  const _SheetSurface({required this.child});

  /// The scroll view (typically a `ListView` bound to the drag controller).
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: t.isDark ? const Color(0xFF0E1310) : const Color(0xFFF6F8F4),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(
            color: t.isDark ? const Color(0x24FFFFFF) : const Color(0x14000000),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: t.isDark ? 0.5 : 0.22),
            blurRadius: 40,
            offset: const Offset(0, -12),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: t.isDark
                  ? const Color(0x40FFFFFF)
                  : const Color(0x33000000),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Darker scrim for Filaments sheets so the screen behind reads as "dimmed
/// backdrop", not a half-rendered glitch bleeding through the top.
const Color _sheetBarrier = Color(0xB3000000); // black @ 70%

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
    backgroundColor: Colors.transparent,
    barrierColor: _sheetBarrier,
    builder: (_) => _SpoolDetailSheet(spool: spool!, assignment: assignment),
  );
}

/// Filaments tab: spool inventory with search, archived toggle, details (usage
/// history, AMS slot, calibration) and management (CRUD, assignments). Data from
/// [inventoryProvider] via the selected backend (native/Spoolman).
///
/// Long-pressing a spool enters multi-select mode for bulk reset-usage /
/// archive / restore / delete / label printing, mirroring the Archive tab.
class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  /// Spool ids picked in multi-select mode. Non-empty → selection mode.
  final Set<int> _selected = {};

  bool get _selectionMode => _selected.isNotEmpty;

  void _toggleSelect(int id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  void _clearSelection() => setState(_selected.clear);

  /// Selects everything currently passing search + filters — not the whole
  /// inventory, so "select all" can't reach rows the user can't see.
  void _selectAllVisible(List<Spool> visible) =>
      setState(() => _selected.addAll(visible.map((s) => s.id)));

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(inventoryProvider);
    final query = ref.watch(inventoryQueryProvider);
    final filters = ref.watch(inventoryFiltersProvider);
    final visible = _filter(
      async.valueOrNull?.spools ?? const [],
      query,
      filters,
    );

    // Drop ids that a filter/search change has scrolled out of reach — acting
    // on invisible rows would be a surprise, and the count would lie.
    final visibleIds = {for (final s in visible) s.id};
    _selected.retainWhere(visibleIds.contains);

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: _selectionMode
            ? _selectionAppBar(context, l10n, visible, filters)
            : dashAppBar(
                context,
                title: l10n.navFilaments,
                actions: [
                  logTag(
                    'inventory.print_labels_all',
                    IconButton(
                      icon: const Icon(Icons.print_outlined),
                      tooltip: l10n.inventoryLabelsPrintAll,
                      onPressed: visible.isEmpty
                          ? null
                          : () => _printLabels(visible, visibleIds),
                    ),
                  ),
                ],
              ),
        floatingActionButton: _selectionMode
            ? null
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  logTag(
                    'inventory.scan_spool',
                    FloatingActionButton.small(
                      heroTag: 'scanSpool',
                      backgroundColor: t.subCard,
                      foregroundColor: t.textPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: t.subCardBorder),
                      ),
                      onPressed: () => _scanSpool(context, ref),
                      tooltip: l10n.inventoryScanSpool,
                      child: const Icon(Icons.qr_code_scanner),
                    ),
                  ),
                  const SizedBox(height: 12),
                  logTag(
                    'inventory.add_spool',
                    FloatingActionButton.extended(
                      heroTag: 'addSpool',
                      backgroundColor: t.accentGreen,
                      foregroundColor: _onAccentGreen,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      onPressed: () => openSpoolForm(context),
                      icon: const Icon(Icons.add),
                      label: Text(
                        l10n.inventoryAddSpool,
                        style: const TextStyle(
                          fontFamily: DashTokens.fontUi,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
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
            final spools = visible;
            return RefreshIndicator(
              onRefresh: () => ref.read(inventoryProvider.notifier).refresh(),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  DashSliverSearchBar(
                    child: _SearchBar(
                      filterCount: filters.activeCount,
                      onQuery: (v) =>
                          ref.read(inventoryQueryProvider.notifier).state = v,
                      onOpenFilters: () => _openFilters(context, inv.spools),
                    ),
                  ),
                  if (spools.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyStateView(
                        message: inv.spools.isEmpty
                            ? l10n.inventoryEmpty
                            : l10n.inventoryNoMatches,
                        icon: Icons.inventory_2_outlined,
                      ),
                    )
                  else
                    SliverPadding(
                      // Clears the whole FAB stack (scan + add) plus its margin,
                      // so the last spool stays reachable at the end of the list.
                      padding: const EdgeInsets.only(bottom: 120),
                      sliver: SliverList.builder(
                        itemCount: spools.length + 1,
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                              child: Text(
                                l10n.inventorySpoolCount(spools.length),
                                style: TextStyle(
                                  fontFamily: DashTokens.fontMono,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: t.textTertiary,
                                ),
                              ),
                            );
                          }
                          final spool = spools[i - 1];
                          return _SpoolTile(
                            spool: spool,
                            assignment: inv.assignmentFor(spool.id),
                            selected: _selected.contains(spool.id),
                            selectionMode: _selectionMode,
                            // Outside selection mode `onTap` stays null so the
                            // tile keeps its own detail-sheet default.
                            onTap: _selectionMode
                                ? () => _toggleSelect(spool.id)
                                : null,
                            onLongPress: () => _toggleSelect(spool.id),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Contextual app bar shown while spools are selected. Print and "select all"
  /// stay as icons (the two non-destructive, most-used actions); the rest live
  /// in an overflow menu so Delete can't be hit by a stray tap.
  ///
  /// The list filter is exclusive (active XOR archived), so the whole selection
  /// is homogeneous and one archive/restore entry is always the right one.
  PreferredSizeWidget _selectionAppBar(
    BuildContext context,
    AppLocalizations l10n,
    List<Spool> visible,
    InventoryFilters filters,
  ) {
    final ids = Set<int>.from(_selected);
    return dashAppBar(
      context,
      title: l10n.inventorySelectedCount(_selected.length),
      leading: logTag(
        'inventory.selection_clear',
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: l10n.cancel,
          onPressed: _clearSelection,
        ),
      ),
      actions: [
        logTag(
          'inventory.select_all',
          IconButton(
            icon: const Icon(Icons.select_all),
            tooltip: l10n.inventorySelectAll,
            onPressed: () => _selectAllVisible(visible),
          ),
        ),
        logTag(
          'inventory.print_labels',
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: l10n.inventoryLabelsPrint,
            onPressed: () => _printLabels(visible, ids),
          ),
        ),
        PopupMenuButton<String>(
          onSelected: (v) => switch (v) {
            'reset' => _bulkResetUsage(ids),
            'archive' => _bulkArchive(ids),
            'restore' => _bulkRestore(ids),
            _ => _bulkDelete(ids),
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'reset',
              child: Text(l10n.inventoryResetUsage),
            ),
            if (filters.showArchived)
              PopupMenuItem(
                value: 'restore',
                child: Text(l10n.inventoryRestore),
              )
            else
              PopupMenuItem(
                value: 'archive',
                child: Text(l10n.inventoryArchive),
              ),
            PopupMenuItem(
              value: 'delete',
              child: Text(l10n.inventoryDelete),
            ),
          ],
        ),
      ],
    );
  }

  /// Opens the label sheet for [pool], pre-checking [preselected]. Called both
  /// from selection mode (the picked spools) and from the app bar's print
  /// action outside it (every visible spool — "print labels for all").
  void _printLabels(List<Spool> pool, Set<int> preselected) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: _sheetBarrier,
      builder: (_) => _LabelSheet(spools: pool, initialSelected: preselected),
    );
  }

  Future<void> _bulkResetUsage(Set<int> ids) => _runBulk(
    ids,
    title: AppLocalizations.of(context).inventoryBulkResetTitle(ids.length),
    message: AppLocalizations.of(context).inventoryBulkResetBody,
    confirmLabel: AppLocalizations.of(context).inventoryResetUsage,
    action: (n) => n.resetUsageMany(ids),
  );

  Future<void> _bulkArchive(Set<int> ids) => _runBulk(
    ids,
    title: AppLocalizations.of(context).inventoryBulkArchiveTitle(ids.length),
    message: AppLocalizations.of(context).inventoryBulkArchiveBody,
    confirmLabel: AppLocalizations.of(context).inventoryArchive,
    action: (n) => n.archiveSpools(ids),
  );

  Future<void> _bulkRestore(Set<int> ids) => _runBulk(
    ids,
    title: AppLocalizations.of(context).inventoryBulkRestoreTitle(ids.length),
    message: AppLocalizations.of(context).inventoryBulkRestoreBody,
    confirmLabel: AppLocalizations.of(context).inventoryRestore,
    action: (n) => n.restoreSpools(ids),
  );

  Future<void> _bulkDelete(Set<int> ids) => _runBulk(
    ids,
    title: AppLocalizations.of(context).inventoryBulkDeleteTitle(ids.length),
    message: AppLocalizations.of(context).inventoryBulkDeleteBody,
    confirmLabel: AppLocalizations.of(context).inventoryDelete,
    destructive: true,
    action: (n) => n.deleteSpools(ids),
  );

  /// Confirm → run a bulk mutation → report the tally. Selection is cleared
  /// either way: the notifier has reloaded, so keeping stale ids around would
  /// only invite a second action on rows that may no longer exist.
  Future<void> _runBulk(
    Set<int> ids, {
    required String title,
    required String message,
    required String confirmLabel,
    required Future<({int ok, int failed})> Function(InventoryNotifier) action,
    bool destructive = false,
  }) async {
    final l10n = AppLocalizations.of(context);
    final ok = await confirmDialog(
      context,
      id: 'inventory.bulk_confirm',
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      destructive: destructive,
    );
    if (!ok || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final res = await action(ref.read(inventoryProvider.notifier));
    if (!mounted) return;
    _clearSelection();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          res.failed == 0
              ? l10n.inventoryBulkDone(res.ok)
              : l10n.inventoryBulkPartial(res.ok, res.failed),
        ),
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
      backgroundColor: Colors.transparent,
      barrierColor: _sheetBarrier,
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
