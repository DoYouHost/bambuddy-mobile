import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../core/ams/slot_addressing.dart';
import '../../core/diagnostics/log_tag.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/format/datetime_format.dart';
import '../../core/format/user_number.dart';
import '../../core/models/inventory.dart';
import '../../core/models/inventory_bulk.dart';
import '../../core/models/inventory_reference.dart';
import '../../core/models/location_sensor.dart';
import '../../core/models/slicer_preset.dart';
import '../../core/models/spool_label.dart';
import '../../core/models/spool_preset_override.dart';
import '../../core/slicer/preset_filters.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../data/inventory_repository.dart';
import '../../data/inventory_source.dart' show InventoryBackend;
import '../../providers.dart';
import '../../router.dart';
import '../common/api_failure_snack.dart';
import '../common/dash_async.dart';
import '../common/dash_progress.dart';
import '../common/dash_search_field.dart';
import '../common/dash_sheet.dart';
import '../common/dash_snack.dart';
import '../common/dashed_line.dart';
import '../common/inline_note.dart';
import '../common/filter_controls.dart';
import '../common/sheet_surface.dart';
import '../common/sliver_search_bar.dart';
import '../common/confirm_dialog.dart';
import '../common/state_views.dart';
import '../common/dash_input.dart';
import '../dashboard/ams_slot_config_providers.dart';
import '../dashboard/providers.dart';
import '../dashboard/ws_providers.dart';
import '../slicer/slice_providers.dart';
import '../stats/stats_common.dart' show fmtGrams;
import 'inventory_providers.dart';
import 'spool_scanner_screen.dart';

part 'inventory_filters.dart';
part 'inventory_tiles.dart';
part 'inventory_sheets.dart';
part 'inventory_form.dart';
part 'inventory_labels.dart';
part 'inventory_bulk_edit.dart';
part 'location_climate.dart';

/// Ink for text/icons painted directly on a solid [DashTokens.accentGreen]
/// fill (e.g. the primary FAB, the save button). Unlike the token pairs above,
/// this isn't theme-adaptive by design — the accent fill itself is a fixed
/// vivid swatch in both brightnesses, so a near-black ink keeps it readable
/// either way.
const Color _onAccentGreen = Color(0xFF08150D);

/// Scans a spool QR code and opens its detail card (NOT edit mode). The
/// scanner returns the id parsed from the URL's `?spool=`; [showSpoolDetail]
/// turns it into a card. Shared by the Filaments FAB and the home-screen
/// widget's scanner button, hence a top-level function and not a screen
/// method.
Future<void> scanSpoolFlow(BuildContext context, WidgetRef ref) async {
  final id = await Navigator.of(
    context,
    rootNavigator: true,
  ).push<int>(MaterialPageRoute(builder: (_) => const SpoolScannerScreen()));
  if (id == null || !context.mounted) return;
  await showSpoolDetail(context, ref, id);
}

/// Lands on Filaments and opens the spool's card there.
///
/// For the places outside the tab that name a spool — today the AMS slot sheet
/// on the dashboard. The tab switch is the point of it: everything the card
/// leads on to (usage history, editing, unassigning) lives in Filaments, and
/// opening it over the printer card would hide where the user just went.
Future<void> openSpoolInInventory(
  BuildContext context,
  WidgetRef ref,
  int spoolId,
) async {
  context.go('/inventory');
  // The sheet goes on the root navigator, above the shell that has just
  // switched tabs — the branch's own context is the one being replaced.
  final root = rootNavigatorKey.currentContext;
  if (root == null) return;
  await showSpoolDetail(root, ref, spoolId);
}

/// Opens one spool's detail card, the same the Filaments list opens.
///
/// [id] is resolved against the loaded shelf, and a miss is worth one refresh:
/// a spool created since the list was fetched is the normal case for both
/// callers — a freshly printed QR label, and a slot just registered from its
/// chip.
Future<void> showSpoolDetail(
  BuildContext context,
  WidgetRef ref,
  int id,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);

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
    messenger.snack(l10n.inventoryScanNotFound(id));
    return;
  }
  final assignment = ref
      .read(inventoryProvider)
      .valueOrNull
      ?.assignmentFor(spool.id);
  dashSurfaceSheet<void>(
    context,
    builder: (_) => _SpoolDetailSheet(spool: spool!, assignment: assignment),
  );
}

/// Filaments tab: spool inventory with search, archived toggle, details (usage
/// history, AMS slot, calibration) and management (CRUD, assignments). Data from
/// [inventoryProvider] via the selected backend (native/Spoolman).
///
/// Long-pressing a spool enters multi-select mode for a mass edit of fields
/// plus bulk reset-usage / archive / restore / delete / label printing,
/// mirroring the Archive tab.
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
    final consumedTotal = ref.watch(inventoryConsumedTotalProvider);
    final climates = ref.watch(locationClimateProvider).valueOrNull ?? const {};
    final climateAlerting = climates.values.any((c) => c.alerting);
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
                  // Only where a location actually has a sensor bound to it:
                  // the map is empty on a server without the feature, on
                  // Spoolman (no location catalog) and for anyone who has not
                  // wired one up, and an icon that opens an empty sheet is
                  // worse than no icon.
                  if (climates.isNotEmpty)
                    logTag(
                      'inventory.location_climate',
                      IconButton(
                        icon: Icon(
                          Icons.thermostat,
                          color: climateAlerting ? t.accentOrangeInk : null,
                        ),
                        // The tooltip carries the alert, because it is also the
                        // icon's semantic label — and the amber is the whole of
                        // what says so to everyone else.
                        tooltip: climateAlerting
                            ? l10n.inventoryClimateTitleAlerting
                            : l10n.inventoryClimateTitle,
                        onPressed: () => _openLocationClimate(context),
                      ),
                    ),
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
        body: dashAsync(
          context,
          async,
          onRetry: () => ref.read(inventoryProvider.notifier).refresh(),
          tonalRetry: true,
          errorIcon: null,
          data: (inv) {
            final spools = visible;
            return RefreshIndicator(
              onRefresh: () {
                // The readings age on their own — the server polls Home
                // Assistant on its own interval — so a pull has to re-ask for
                // them, not only for the shelf.
                ref.invalidate(locationClimateProvider);
                return ref.read(inventoryProvider.notifier).refresh();
              },
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
                            return _ListHeader(
                              visibleCount: spools.length,
                              consumed: consumedTotal,
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
            'edit' => _bulkEdit(ids),
            'reset' => _bulkResetUsage(ids),
            'archive' => _bulkArchive(ids),
            'restore' => _bulkRestore(ids),
            _ => _bulkDelete(ids),
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'edit',
              child: logTag(
                'inventory.bulk_edit',
                Text(l10n.inventoryBulkEdit),
              ),
            ),
            PopupMenuItem(
              value: 'reset',
              child: logTag(
                'inventory.bulk_reset_usage',
                Text(l10n.inventoryResetUsage),
              ),
            ),
            if (filters.showArchived)
              PopupMenuItem(
                value: 'restore',
                child: logTag(
                  'inventory.bulk_restore',
                  Text(l10n.inventoryRestore),
                ),
              )
            else
              PopupMenuItem(
                value: 'archive',
                child: logTag(
                  'inventory.bulk_archive',
                  Text(l10n.inventoryArchive),
                ),
              ),
            PopupMenuItem(
              value: 'delete',
              child: logTag(
                'inventory.bulk_delete',
                Text(l10n.inventoryDelete),
              ),
            ),
          ],
        ).tagged('inventory.bulk_menu'),
      ],
    );
  }

  /// Opens the label sheet for [pool], pre-checking [preselected]. Called both
  /// from selection mode (the picked spools) and from the app bar's print
  /// action outside it (every visible spool — "print labels for all").
  void _printLabels(List<Spool> pool, Set<int> preselected) {
    dashSurfaceSheet<void>(
      context,
      builder: (_) => _LabelSheet(spools: pool, initialSelected: preselected),
    );
  }

  /// Opens the mass-edit sheet. It reports its own refusals — the sheet stays
  /// open so the typed values survive one — and pops with the tally only when
  /// the edit actually went through.
  Future<void> _bulkEdit(Set<int> ids) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await dashSurfaceSheet<BulkOutcome>(
      context,
      builder: (_) => _BulkEditSheet(spoolIds: ids),
    );
    if (outcome == null || !mounted) return;
    _clearSelection();
    messenger.snack(_bulkTally(l10n, outcome));
  }

  Future<void> _bulkResetUsage(Set<int> ids) => _runBulk(
    ids,
    logId: 'inventory.bulk_reset_usage',
    title: AppLocalizations.of(context).inventoryBulkResetTitle(ids.length),
    message: AppLocalizations.of(context).inventoryBulkResetBody,
    confirmLabel: AppLocalizations.of(context).inventoryResetUsage,
    action: (n) => n.resetUsageMany(ids),
  );

  Future<void> _bulkArchive(Set<int> ids) => _runBulk(
    ids,
    logId: 'inventory.bulk_archive',
    title: AppLocalizations.of(context).inventoryBulkArchiveTitle(ids.length),
    message: AppLocalizations.of(context).inventoryBulkArchiveBody,
    confirmLabel: AppLocalizations.of(context).inventoryArchive,
    action: (n) => n.archiveSpools(ids),
  );

  Future<void> _bulkRestore(Set<int> ids) => _runBulk(
    ids,
    logId: 'inventory.bulk_restore',
    title: AppLocalizations.of(context).inventoryBulkRestoreTitle(ids.length),
    message: AppLocalizations.of(context).inventoryBulkRestoreBody,
    confirmLabel: AppLocalizations.of(context).inventoryRestore,
    action: (n) => n.restoreSpools(ids),
  );

  Future<void> _bulkDelete(Set<int> ids) => _runBulk(
    ids,
    logId: 'inventory.bulk_delete',
    title: AppLocalizations.of(context).inventoryBulkDeleteTitle(ids.length),
    message: AppLocalizations.of(context).inventoryBulkDeleteBody,
    confirmLabel: AppLocalizations.of(context).inventoryDelete,
    destructive: true,
    action: (n) => n.deleteSpools(ids),
  );

  /// Confirm → run a bulk mutation → report the tally. Selection is cleared
  /// either way: the notifier has reloaded, so keeping stale ids around would
  /// only invite a second action on rows that may no longer exist.
  ///
  /// A refusal reaches here as an exception now that one request stands for the
  /// whole selection — a key without `filaments:update` fails the batch outright
  /// instead of failing every id in turn, and the tally has nothing to say
  /// about why.
  Future<void> _runBulk(
    Set<int> ids, {
    required String logId,
    required String title,
    required String message,
    required String confirmLabel,
    required Future<BulkOutcome> Function(InventoryNotifier) action,
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
    final BulkOutcome res;
    try {
      res = await action(ref.read(inventoryProvider.notifier));
    } on AppApiException catch (e) {
      if (mounted) _clearSelection();
      showApiFailure(mounted ? messenger : null, e, l10n, action: logId);
      return;
    }
    if (!mounted) return;
    _clearSelection();
    messenger.snack(_bulkTally(l10n, res));
  }

  /// One line for what a bulk call did. A spool that was already in the state
  /// the user asked for is called out separately: it is not a failure — the
  /// shelf ends up as intended — but "5 updated" would be a lie when two of
  /// them were archived already.
  ///
  /// All three counts can be non-zero at once on a chunked selection, so they
  /// are reported together rather than one winning over the others.
  String _bulkTally(AppLocalizations l10n, BulkOutcome outcome) {
    if (outcome.failed > 0 && outcome.skipped > 0) {
      return l10n.inventoryBulkPartialSkipped(
        outcome.ok,
        outcome.skipped,
        outcome.failed,
      );
    }
    if (outcome.failed > 0) {
      return l10n.inventoryBulkPartial(outcome.ok, outcome.failed);
    }
    if (outcome.skipped > 0) {
      return l10n.inventoryBulkSkipped(outcome.ok, outcome.skipped);
    }
    return l10n.inventoryBulkDone(outcome.ok);
  }

  /// Client-side filter: status (active/archived), stock, material, brand, location,
  /// and search by material/brand/color/location (case-insensitive). Empty sets in
  /// [filters] = no restriction.
  List<Spool> _filter(
    List<Spool> spools,
    String query,
    InventoryFilters filters,
  ) {
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
                  if (s.matchesSearch(query)) s,
    ];
  }

  /// Scans a spool QR code and opens its detail card (NOT edit mode).
  /// Delegates to [scanSpoolFlow], shared with the home screen widget.
  Future<void> _scanSpool(BuildContext context, WidgetRef ref) =>
      scanSpoolFlow(context, ref);

  /// Opens the filter sheet. Options (materials/brands/locations) counted from the
  /// full spool list to show only actually occurring values.
  void _openFilters(BuildContext context, List<Spool> all) {
    dashSurfaceSheet<void>(
      context,
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
}
