import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/printer_location.dart';
import '../../core/settings/server_profile.dart';
import '../../core/theme/dash_theme.dart';
import '../../data/printers_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import '../common/dash_async.dart';
import '../common/dash_input.dart';
import '../common/dash_search_field.dart';
import '../common/inline_note.dart';
import '../dashboard/providers.dart';
import '../dashboard/ws_providers.dart';
import 'printer_location_form.dart';
import 'printer_locations_providers.dart';
import 'printer_locations_widgets.dart';

/// Printer Locations (server #2962): the places a printer can be filed under,
/// with an icon and a colour, and the printers in each.
///
/// The web page's behaviour, one for one: a card per location that opens onto
/// its printers, the printers without a location below, a search, "hide
/// empty" and four sort orders, ticking printers to move them and ticking
/// locations to delete them. The hide-empty and sort choices are not kept
/// between visits.
class PrinterLocationsScreen extends ConsumerStatefulWidget {
  const PrinterLocationsScreen({super.key});

  @override
  ConsumerState<PrinterLocationsScreen> createState() =>
      _PrinterLocationsScreenState();
}

class _PrinterLocationsScreenState
    extends ConsumerState<PrinterLocationsScreen> {
  String _query = '';
  String? _expanded;

  /// Ticking locations (to delete them) and ticking printers (to move them)
  /// are different modes, as on the web page: the first replaces the card
  /// headers' buttons, the second sits beside the printers.
  bool _selecting = false;
  final Set<String> _pickedLocations = {};
  final Set<int> _pickedPrinters = {};

  /// One write at a time: a second tap while one is in flight would send the
  /// same move twice.
  bool _busy = false;

  /// What the printers are filed under, blank meaning none. Trimmed, because
  /// the server trims on write and an older row may still carry spaces.
  static String _locationOf(PrinterWithStatus p) =>
      (p.printer.location ?? '').trim();

  /// Re-reads the locations and the roster, and waits for both: a write that
  /// let go of the screen before the list was back left a deleted location on
  /// show, with its buttons enabled. A failed re-read is the list's own error
  /// state, never this call's, so nothing is thrown.
  Future<void> _reload(ProviderContainer container) async {
    container.invalidate(printerLocationsProvider);
    try {
      await Future.wait([
        container.read(printerLocationsProvider.future).then((_) {}),
        container.read(dashboardProvider.notifier).refresh(),
      ]);
    } on Object {
      // See above.
    }
  }

  Future<void> _refresh() =>
      _reload(ProviderScope.containerOf(context, listen: false));

  /// Runs one write: [send] answers the sentence to show, a refusal shows the
  /// server's reason instead. Re-reads the locations and the roster either
  /// way, because a failed write may have changed part of what it asked for.
  Future<bool> _write(
    Future<String> Function(AppLocalizations l10n) send, {
    required String action,
  }) async {
    if (_busy) return false;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _busy = true);
    var ok = false;
    try {
      messenger.snack(await send(l10n));
      ok = true;
    } on AppApiException catch (e) {
      showApiFailure(
        mounted ? messenger : null,
        e,
        l10n,
        action: action,
        message: e.statusCode == 409 ? l10n.printerLocationsNameTaken : null,
      );
    } finally {
      await _reload(container);
      if (mounted) setState(() => _busy = false);
    }
    return ok;
  }

  Future<void> _edit(PrinterLocation location) async {
    final saved = await openPrinterLocationForm(context, existing: location);
    if (saved == null || !mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _busy = true);
    // A rename moved the printers along; the roster has to follow before the
    // card that was open can stay open under its new name, or it would show
    // empty until the printers arrive.
    await _reload(container);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (_expanded == location.name) _expanded = saved.name;
    });
  }

  Future<void> _delete(List<String> names, {required String action}) async {
    final l10n = AppLocalizations.of(context);
    final byName = {
      for (final l
          in ref.read(printerLocationsProvider).valueOrNull ??
              const <PrinterLocation>[])
        l.name: l.printerCount,
    };
    final orphaned = names.fold<int>(0, (sum, n) => sum + (byName[n] ?? 0));
    final ok = await confirmDialog(
      context,
      id: 'locations.delete_confirm',
      title: names.length == 1
          ? l10n.printerLocationsDeleteTitle
          : l10n.printerLocationsDeleteTitleMany(names.length),
      message: l10n.printerLocationsDeleteMessage(names.join(', '), orphaned),
      confirmLabel: l10n.inventoryDelete,
      destructive: true,
    );
    if (!ok || !mounted) return;
    final done = await _write((l10n) async {
      final deleted = await ref
          .read(printerLocationsRepositoryProvider)
          .delete(names);
      return l10n.printerLocationsDeleted(deleted);
    }, action: action);
    if (done && mounted) {
      setState(() {
        _pickedLocations.clear();
        _selecting = false;
        if (names.contains(_expanded)) _expanded = null;
      });
    }
  }

  Future<void> _move(List<int> ids, List<PrinterLocation> targets) async {
    final choice = await showDialog<({String? location})>(
      context: context,
      builder: (_) => _MoveDialog(count: ids.length, targets: targets),
    );
    if (choice == null || !mounted) return;
    final done = await _write((l10n) async {
      final moved = await ref
          .read(printerLocationsRepositoryProvider)
          .assign(ids, choice.location);
      return l10n.printerLocationsMoved(moved);
    }, action: 'location_move.confirm');
    if (done && mounted) setState(() => _pickedPrinters.removeAll(ids));
  }

  Future<void> _remove(PrinterWithStatus p) async {
    final done = await _write((l10n) async {
      final moved = await ref.read(printerLocationsRepositoryProvider).assign([
        p.printer.id,
      ], null);
      return l10n.printerLocationsMoved(moved);
    }, action: 'locations.printer_remove');
    if (done && mounted) setState(() => _pickedPrinters.remove(p.printer.id));
  }

  void _toggle<T>(Set<T> set, T value) => setState(() {
    if (!set.remove(value)) set.add(value);
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // A server that answered 404 to the listing has nothing to write to.
    final canEdit =
        ref.watch(canUpdatePrintersProvider) &&
        ref.watch(printerLocationsSupportedProvider).orFalse;
    final async = ref.watch(printerLocationsProvider);
    final roster = withLiveStatuses(
      ref.watch(dashboardProvider).printers ?? const [],
      ref.watch(printerStatusesProvider),
    );

    final bar = _selectionBar(l10n, canEdit);
    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(
          context,
          title: l10n.printerLocationsMenu,
          actions: [
            if (canEdit)
              TextButton(
                onPressed: () => setState(() {
                  _pickedLocations.clear();
                  _expanded = null;
                  _selecting = !_selecting;
                }),
                child: Text(
                  _selecting
                      ? l10n.printerLocationsDone
                      : l10n.printerLocationsSelect,
                ),
              ).tagged('locations.select_mode', selected: _selecting),
          ],
        ),
        floatingActionButton: canEdit && bar == null && !_selecting
            ? FloatingActionButton.extended(
                onPressed: _busy
                    ? null
                    : () => openPrinterLocationForm(context),
                icon: const Icon(Icons.add),
                label: Text(l10n.printerLocationsNew),
              ).tagged('locations.new')
            : null,
        bottomNavigationBar: bar,
        body: dashAsync(
          context,
          async,
          onRetry: _refresh,
          data: (all) => RefreshIndicator(
            onRefresh: _refresh,
            child: _list(l10n, canEdit, all, roster),
          ),
        ),
      ),
    );
  }

  Widget? _selectionBar(AppLocalizations l10n, bool canEdit) {
    if (!canEdit) return null;
    if (_selecting && _pickedLocations.isNotEmpty) {
      return LocationSelectionBar(
        count: _pickedLocations.length,
        actionLabel: l10n.printerLocationsDeleteSelected,
        actionIcon: Icons.delete_outline,
        id: 'locations.delete_selected',
        cancelId: 'locations.selection_cancel',
        destructive: true,
        busy: _busy,
        onAction: () =>
            _delete([..._pickedLocations], action: 'locations.delete_selected'),
        onCancel: () => setState(_pickedLocations.clear),
      );
    }
    if (!_selecting && _pickedPrinters.isNotEmpty) {
      return LocationSelectionBar(
        count: _pickedPrinters.length,
        actionLabel: l10n.printerLocationsMoveButton,
        actionIcon: Icons.drive_file_move_outline,
        id: 'locations.move_selected',
        cancelId: 'locations.printers_cancel',
        busy: _busy,
        onAction: () => _move([
          ..._pickedPrinters,
        ], ref.read(printerLocationsProvider).valueOrNull ?? const []),
        onCancel: () => setState(_pickedPrinters.clear),
      );
    }
    return null;
  }

  Widget _list(
    AppLocalizations l10n,
    bool canEdit,
    List<PrinterLocation> all,
    List<PrinterWithStatus> roster,
  ) {
    final t = DashTokens.of(context);
    final hideEmpty = ref.watch(hideEmptyLocationsProvider);
    final sort = ref.watch(locationSortProvider);
    final byLocation = <String, List<PrinterWithStatus>>{};
    for (final p in roster) {
      byLocation.putIfAbsent(_locationOf(p), () => []).add(p);
    }
    final ungrouped = byLocation[''] ?? const <PrinterWithStatus>[];
    final shown = arrangeLocations(
      all,
      query: _query,
      hideEmpty: hideEmpty,
      sort: sort,
    );
    final allUngroupedPicked =
        ungrouped.isNotEmpty &&
        ungrouped.every((p) => _pickedPrinters.contains(p.printer.id));

    LocationPrinterRow printerRow(
      PrinterWithStatus p, {
      required bool inside,
    }) => LocationPrinterRow(
      key: ValueKey(p.printer.id),
      printer: p,
      picked: _pickedPrinters.contains(p.printer.id),
      canEdit: canEdit && !_selecting,
      busy: _busy,
      onToggle: () => _toggle(_pickedPrinters, p.printer.id),
      onMove: () => _move([p.printer.id], all),
      onRemove: inside ? () => _remove(p) : null,
    );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: DashSpace.fabClearance),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            DashSpace.gutter,
            DashSpace.xs,
            DashSpace.gutter,
            DashSpace.sm,
          ),
          child: Text(
            l10n.printerLocationsSubtitle(
              roster.length - ungrouped.length,
              ungrouped.length,
            ),
            style: t.bodyPlain,
          ),
        ),
        if (ref.watch(serverProfileProvider)?.authMode == AuthMode.apiKey)
          InlineNote(
            l10n.printerLocationsReadOnly,
            icon: Icons.info_outline,
            padding: const EdgeInsets.fromLTRB(
              DashSpace.gutter,
              0,
              DashSpace.gutter,
              DashSpace.sm,
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DashSpace.gutter),
          child: DashSearchField(
            hintText: l10n.printerLocationsSearch,
            id: 'locations.search',
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            DashSpace.gutter,
            DashSpace.sm,
            DashSpace.gutter,
            DashSpace.md,
          ),
          child: Wrap(
            spacing: DashSpace.sm,
            runSpacing: DashSpace.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: Text(l10n.printerLocationsHideEmpty),
                selected: hideEmpty,
                onSelected: (v) =>
                    ref.read(hideEmptyLocationsProvider.notifier).state = v,
              ).tagged('locations.hide_empty', selected: hideEmpty),
              PopupMenuButton<LocationSort>(
                tooltip: l10n.printerLocationsSort,
                initialValue: sort,
                onSelected: (v) =>
                    ref.read(locationSortProvider.notifier).state = v,
                itemBuilder: (_) => [
                  for (final s in LocationSort.values)
                    PopupMenuItem(
                      value: s,
                      child: logTag(
                        'locations.sort.${s.name}',
                        Text(_sortLabel(l10n, s)),
                      ),
                    ),
                ],
                child: Chip(
                  avatar: const Icon(Icons.sort, size: 18),
                  label: Text(_sortLabel(l10n, sort)),
                ),
              ).tagged('locations.sort'),
            ],
          ),
        ),
        if (shown.isEmpty && ungrouped.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: DashSpace.xxl),
            child: Text(
              _query.isNotEmpty
                  ? l10n.printerLocationsNoResults
                  : l10n.printerLocationsEmpty,
              textAlign: TextAlign.center,
              style: t.bodyPlain,
            ),
          ),
        for (final location in shown)
          LocationCard(
            key: ValueKey(location.name),
            location: location,
            expanded: _expanded == location.name,
            selecting: _selecting,
            picked: _pickedLocations.contains(location.name),
            canEdit: canEdit,
            busy: _busy,
            onTap: () => _selecting
                ? _toggle(_pickedLocations, location.name)
                : setState(
                    () => _expanded = _expanded == location.name
                        ? null
                        : location.name,
                  ),
            onEdit: () => _edit(location),
            onDelete: () =>
                _delete([location.name], action: 'locations.delete'),
            children: [
              for (final p in byLocation[location.name] ?? const [])
                printerRow(p, inside: true),
            ],
          ),
        if (ungrouped.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DashSpace.gutter,
              DashSpace.lg,
              DashSpace.gutter,
              DashSpace.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.printerLocationsUngrouped(ungrouped.length),
                    style: t.bodyBold,
                  ),
                ),
                if (canEdit && !_selecting)
                  TextButton(
                    onPressed: () => setState(() {
                      for (final p in ungrouped) {
                        if (allUngroupedPicked) {
                          _pickedPrinters.remove(p.printer.id);
                        } else {
                          _pickedPrinters.add(p.printer.id);
                        }
                      }
                    }),
                    child: Text(
                      allUngroupedPicked
                          ? l10n.printerLocationsDeselectAll
                          : l10n.printerLocationsSelectAll,
                    ),
                  ).tagged('locations.ungrouped_select_all'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: DashSpace.gutter),
            child: Column(
              children: [
                for (final p in ungrouped) printerRow(p, inside: false),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static String _sortLabel(AppLocalizations l10n, LocationSort sort) =>
      switch (sort) {
        LocationSort.nameAsc => l10n.printerLocationsSortNameAsc,
        LocationSort.nameDesc => l10n.printerLocationsSortNameDesc,
        LocationSort.countAsc => l10n.printerLocationsSortCountAsc,
        LocationSort.countDesc => l10n.printerLocationsSortCountDesc,
      };
}

/// Where to move the ticked printers: one of the locations, or none.
class _MoveDialog extends StatefulWidget {
  const _MoveDialog({required this.count, required this.targets});

  final int count;
  final List<PrinterLocation> targets;

  @override
  State<_MoveDialog> createState() => _MoveDialogState();
}

/// The "no location" entry; the server's own name for it is `null`, which a
/// dropdown entry cannot hold as a value of its own.
const _noLocation = '';

class _MoveDialogState extends State<_MoveDialog> {
  String? _picked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(
        widget.count == 1
            ? l10n.printerLocationsMoveTitle
            : l10n.printerLocationsMoveTitleMany(widget.count),
      ),
      content: dashCombo<String>(
        context,
        id: 'location_move.target',
        label: Text(l10n.printerLocationsTargetHint),
        onSelected: (v) => setState(() => _picked = v),
        entries: [
          for (final target in widget.targets)
            DropdownMenuEntry(
              value: target.name,
              label: target.name,
              labelWidget: logTag('location_move.option', Text(target.name)),
            ),
          DropdownMenuEntry(
            value: _noLocation,
            label: l10n.printerLocationsNoLocation,
            labelWidget: logTag(
              'location_move.none',
              Text(l10n.printerLocationsNoLocation),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ).tagged('location_move.cancel'),
        FilledButton(
          onPressed: _picked == null
              ? null
              : () => Navigator.pop(context, (
                  location: _picked == _noLocation ? null : _picked,
                )),
          child: Text(l10n.printerLocationsMoveButton),
        ).tagged('location_move.confirm'),
      ],
    );
  }
}
