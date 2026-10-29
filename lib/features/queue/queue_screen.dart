import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/action_outcome.dart';
import 'package:app_diagnostics/app_diagnostics.dart';
import '../../core/format/duration_format.dart';
import '../../core/models/queue_item.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../common/dash_async.dart';
import '../gcode/gcode_viewer_route.dart';
import '../dashboard/ws_providers.dart';
import '../orders/orders_providers.dart';
import 'queue_actions.dart';
import 'queue_bulk_edit_screen.dart';
import 'queue_edit_screen.dart';
import 'queue_history.dart';
import 'queue_item_view.dart';
import 'queue_mapping_sheet.dart';
import 'queue_providers.dart';
import 'queue_removal.dart';
import 'queue_resume_banner.dart';
import 'queue_selection.dart';
import '../tour/tour_beacon.dart';

/// Print queue screen (M5): drag-to-reorder, swipe-to-delete with confirmation,
/// start/cancel actions. Shows only active items.
///
/// Queue has no WS and state changes outside app (e.g. print started from
/// printer/other client), so when screen is in foreground we fetch fresh list
/// periodically. Timer pauses in background (like Dashboard polling) because it's
/// unnecessary server hits — returning fetches fresh anyway.
class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({super.key});

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen>
    with SingleTickerProviderStateMixin {
  /// Auto-refresh frequency in foreground. Less frequent than Dashboard's roster
  /// (5s) — queue changes slower and fetch is heavier.
  static const _refreshInterval = Duration(seconds: 10);

  Timer? _timer;
  late final AppLifecycleListener _lifecycle;

  /// The queue and its history, the web's first and History tabs.
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(_tabSettled);
  int _shownTab = 0;
  bool get _onHistory => _tabs.index == 1;

  /// A tab just brought into view shows what is there now rather than waiting
  /// for the next tick: only the tab on screen is polled, so the other one has
  /// been standing still.
  void _tabSettled() {
    if (_tabs.indexIsChanging || _tabs.index == _shownTab) return;
    setState(() => _shownTab = _tabs.index);
    unawaited(_refreshShown());
    if (_visible) _startTimer();
  }

  /// Whether this tab's branch is the one currently shown — see
  /// [didChangeDependencies]. Starts false; the framework-guaranteed
  /// `didChangeDependencies` call right after `initState` sets it correctly
  /// before the first frame.
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onPause: _stopTimer,
      onResume: () {
        // Return to foreground on a different tab shouldn't resume polling
        // for a screen the user isn't looking at.
        if (!_visible) return;
        unawaited(_refreshShown());
        _startTimer();
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `StatefulShellRoute`'s IndexedStack keeps every branch mounted (see
    // `root_scaffold.dart`) so this timer would otherwise tick on the
    // foreground for the app's entire lifetime once the Queue tab was
    // visited once, even while another tab is shown. go_router wraps each
    // offstage branch in `TickerMode(enabled: false)` for exactly this kind
    // of gating.
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible == _visible) return;
    _visible = visible;
    if (visible) {
      _startTimer();
    } else {
      _stopTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
      _refreshInterval,
      (_) => unawaited(_refreshShown()),
    );
  }

  /// Only the tab on screen is polled: the history is most of what the server
  /// holds, and nobody is looking at it from the queue tab.
  Future<void> _refreshShown() => _onHistory
      ? ref.read(queueHistoryProvider.notifier).refresh()
      : ref.read(queueProvider.notifier).refresh();

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stopTimer();
    _lifecycle.dispose();
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final async = ref.watch(queueProvider);

    // Pending prints (excluding currently printing) — "start next" button
    // visibility depends on their presence.
    final items = async.value ?? const <QueueItem>[];
    final queued = [
      for (final i in items)
        if (i.statusKind != QueueItemStatusKind.printing) i,
    ];
    final firstQueued = queued.isEmpty ? null : queued.first;
    final selection = ref.watch(queueSelectionProvider);
    // The selection belongs to the queue tab: the history has nothing to pick.
    final selecting = selection.isNotEmpty && !_onHistory;

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(
          context,
          title: selecting
              ? l10n.queueSelectedCount(selection.length)
              : l10n.navQueue,
          leading: selecting
              ? logTag(
                  'queue.selection_clear',
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: l10n.cancel,
                    onPressed: ref.read(queueSelectionProvider.notifier).clear,
                  ),
                )
              : null,
          bottom: TabBar(
            controller: _tabs,
            tabs: [
              Tab(
                text: l10n.navQueue,
              ).tagged('queue.tab_queue', selected: !_onHistory),
              Tab(
                text: l10n.queueHistory,
              ).tagged('queue.tab_history', selected: _onHistory),
            ],
          ),
          actions: [
            if (selecting) ...[
              logTag(
                'queue.select_all',
                IconButton(
                  icon: const Icon(Icons.select_all),
                  tooltip: l10n.queueSelectAll,
                  onPressed: () =>
                      ref.read(queueSelectionProvider.notifier).selectAll([
                        for (final i in items)
                          if (queueItemSelectable(i)) i.id,
                      ]),
                ),
              ),
              logTag(
                'queue.bulk_edit',
                IconButton(
                  icon: const Icon(Icons.edit_note),
                  tooltip: l10n.queueBulkEdit,
                  onPressed: () => _bulkEdit(selection),
                ),
              ),
            ] else if (ref.watch(batchListingProvider).orFalse)
              IconButton(
                tooltip: l10n.ordersTitle,
                icon: const Icon(Icons.inventory_2_outlined),
                onPressed: () => context.push('/orders'),
              ).tagged('queue.orders'),
            if (queued.isNotEmpty && !_onHistory && !selecting)
              Padding(
                padding: const EdgeInsets.only(right: DashSpace.lg),
                child: Center(
                  child: DashPill(
                    label: '${queued.length}',
                    accent: t.accentGreen,
                    accentInk: t.accentGreenInk,
                  ),
                ),
              ),
          ],
        ),
        floatingActionButton:
            firstQueued == null ||
                _onHistory ||
                selecting ||
                !ref.watch(
                  mayStartQueueItemProvider((
                    createdById: firstQueued.createdById,
                    printerId: firstQueued.printerId,
                  )),
                )
            ? null
            : logTag(
                'queue.start_next',
                FloatingActionButton.extended(
                  onPressed: () => _startNext(context, ref, firstQueued, l10n),
                  backgroundColor: t.accentGreen,
                  foregroundColor: t.onAccent,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l10n.queueStartNext),
                ),
              ),
        body: RefreshWhenShown(
          onRefresh: _refreshShown,
          child: TabBarView(
            controller: _tabs,
            children: [
              dashAsync(
                context,
                async,
                onRetry: () => ref.read(queueProvider.notifier).refresh(),
                data: (items) => RefreshIndicator(
                  onRefresh: () => ref.read(queueProvider.notifier).refresh(),
                  child: items.isEmpty
                      // Nothing to scroll, so the banners sit above the message.
                      ? Column(
                          children: [
                            const QueueResumeBanners(),
                            Expanded(
                              child: EmptyStateView(
                                message: l10n.queueEmpty,
                                icon: Icons.playlist_add_check,
                              ),
                            ),
                          ],
                        )
                      : _QueueList(items: items),
                ),
              ),
              const QueueHistoryView(),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the bulk edit for what is picked, in the queue's order. The picks
  /// are dropped only once something was applied: a refused edit keeps them, so
  /// the user can change one setting and send it again.
  Future<void> _bulkEdit(Set<int> picked) async {
    final items = ref.read(queueProvider).value ?? const <QueueItem>[];
    final ids = [
      for (final i in items)
        if (picked.contains(i.id)) i.id,
    ];
    if (ids.isEmpty) return;
    final applied = await openQueueBulkEdit(context, ids);
    if (applied && mounted) ref.read(queueSelectionProvider.notifier).clear();
  }

  /// FAB "start next" — delegates to the shared start flow (assign a printer if
  /// the item has none, then filament mapping, then start).
  Future<void> _startNext(
    BuildContext context,
    WidgetRef ref,
    QueueItem item,
    AppLocalizations l10n,
  ) => startQueueItem(context, ref, item, l10n);
}

class _QueueList extends ConsumerWidget {
  const _QueueList({required this.items});

  final List<QueueItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Printing pinned on top (non-reorderable, outside ReorderableListView);
    // rest is reorderable. Shift reorder indices by pinned count because
    // notifier operates on full active list (printing + rest).
    final pinned = [
      for (final i in items)
        if (i.statusKind == QueueItemStatusKind.printing) i,
    ];
    final reorderable = [
      for (final i in items)
        if (i.statusKind != QueueItemStatusKind.printing) i,
    ];
    final offset = pinned.length;

    // The resume banners and the printing cards are the list's header, so they
    // scroll away with it: with several printers running, fixed rows would take
    // the whole screen. The top inset goes above them, not into the list: inside
    // the list it also sat between the printing card and the next one, which
    // made that one gap twice the others.
    return ReorderableListView.builder(
      header: Padding(
        padding: const EdgeInsets.only(top: DashSpace.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const QueueResumeBanners(),
            for (final it in pinned) _QueueCard(item: it, pinned: true),
          ],
        ),
      ),
      padding: const EdgeInsets.only(bottom: DashSpace.sm),
      physics: const AlwaysScrollableScrollPhysics(),
      // No default long-press drag — reorder only via explicit handle on left
      // side of tile.
      buildDefaultDragHandles: false,
      itemCount: reorderable.length,
      onReorderItem: (oldIndex, newIndex) async {
        ref.read(tourBeaconProvider)?.signal('queue.reorder');
        final messenger = ScaffoldMessenger.of(context);
        final result = await ref
            .read(queueProvider.notifier)
            .reorder(oldIndex + offset, newIndex + offset);
        _snackFailure(messenger, l10n, result);
      },
      itemBuilder: (context, i) => _QueueCard(
        key: ValueKey(reorderable[i].id),
        item: reorderable[i],
        dragIndex: i,
      ),
    );
  }
}

class _QueueCard extends ConsumerWidget {
  const _QueueCard({
    super.key,
    required this.item,
    this.pinned = false,
    this.dragIndex,
  });

  final QueueItem item;

  /// Printing item: pinned on top, highlighted, non-reorderable, no swipe-to-delete
  /// (not wrapped in Dismissible).
  final bool pinned;

  /// Index in reorderable list; when provided, show explicit drag handle on left
  /// (`ReorderableDragStartListener`). Null for pinned items.
  final int? dragIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final idx = dragIndex;
    final selectable = queueItemSelectable(item);
    final selected = ref.watch(
      queueSelectionProvider.select((s) => s.contains(item.id)),
    );
    final selecting = ref.watch(
      queueSelectionProvider.select((s) => s.isNotEmpty),
    );
    // Long press starts a selection (the archive's gesture), a tap extends it.
    // Outside selection mode the card has no tap, as before.
    final selectionNotifier = ref.read(queueSelectionProvider.notifier);
    final mayPick = selectable && ref.watch(mayBulkEditQueueProvider);

    final card = logTag(
      'queue.card',
      GestureDetector(
        onLongPress: mayPick && !selecting
            ? () => selectionNotifier.toggle(item.id)
            : null,
        onTap: mayPick && selecting
            ? () => selectionNotifier.toggle(item.id)
            : null,
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: DashSpace.gutter,
            vertical: DashSpace.xs,
          ),
          padding: const EdgeInsets.all(DashSpace.lg),
          decoration: BoxDecoration(
            gradient: selected ? null : t.cardGradient,
            color: selected
                ? t.accentGreen.withValues(alpha: DashAlpha.wash)
                : null,
            borderRadius: BorderRadius.circular(DashRadius.xl),
            // The printing card wears a green-tinted border; only a pick is filled.
            border: Border.all(
              color: selected
                  ? t.accentGreen.withValues(alpha: DashAlpha.scrim)
                  : pinned
                  ? t.accentGreen.withValues(alpha: DashAlpha.soft)
                  : t.cardBorder,
            ),
          ),
          child: Row(
            children: [
              if (idx != null && !selecting)
                logTag(
                  'queue.reorder',
                  ReorderableDragStartListener(
                    index: idx,
                    child: Padding(
                      padding: const EdgeInsets.only(right: DashSpace.md),
                      child: Icon(Icons.drag_indicator, color: t.textTertiary),
                    ),
                  ).tourTarget('queue.reorder.${item.id}'),
                ),
              // A tick in place of the picture, as the archive marks a pick.
              if (selected)
                Container(
                  width: DashSize.d56,
                  height: DashSize.d56,
                  decoration: BoxDecoration(
                    color: t.accentGreen.withValues(alpha: DashAlpha.wash),
                    borderRadius: BorderRadius.circular(DashRadius.lg),
                  ),
                  child: Icon(Icons.check, color: t.accentGreenInk),
                )
              else
                ClipRRect(
                  borderRadius: BorderRadius.circular(DashRadius.lg),
                  child: QueueThumbnail(item: item, size: DashSize.d56),
                ),
              const SizedBox(width: DashSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleMd,
                    ),
                    const SizedBox(height: DashSpace.sm),
                    _Subtitle(item: item),
                  ],
                ),
              ),
              // The menu's removal and the swipe both act on one item, and a
              // selection is about several: they wait until it is over.
              if (!selecting) _QueueActions(item: item),
            ],
          ),
        ),
      ),
      // Said only where a pick is possible, so a reader does not announce every
      // other card as "not selected".
      selected: selecting && mayPick ? selected : null,
    );

    // Printing: no Dismissible — can't swipe-delete (and outside ReorderableListView,
    // so non-reorderable).
    if (pinned) return card;

    return Dismissible(
      key: ValueKey('dismiss_${item.id}'),
      // No swipe while picking: it would delete one of several. Switched off
      // rather than unwrapped, so entering a selection does not rebuild the card.
      direction: selecting
          ? DismissDirection.none
          : DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: DashSpace.xl),
        margin: const EdgeInsets.symmetric(
          horizontal: DashSpace.gutter,
          vertical: DashSpace.xs,
        ),
        decoration: BoxDecoration(
          color: t.danger.withValues(alpha: DashAlpha.wash),
          borderRadius: BorderRadius.circular(DashRadius.xl),
        ),
        child: Icon(Icons.delete_outline, color: t.dangerInk),
      ),
      // Dialog here only; actual delete in onDismissed (notifier removes from state) —
      // else Dismissible conflicts with list rebuild.
      confirmDismiss: (_) {
        ref.read(tourBeaconProvider)?.signal('queue.swipe_delete');
        return confirmDialog(
          context,
          id: 'queue.swipe_delete_confirm',
          title: l10n.queueDeleteTitle,
          message: l10n.queueDeleteBody,
          confirmLabel: l10n.queueDeleteConfirm,
        );
      },
      onDismissed: (_) async {
        final messenger = ScaffoldMessenger.of(context);
        final result = await ref.read(queueProvider.notifier).delete(item.id);
        // The swipe hits `DELETE`, which refuses a row that started printing
        // between the list being drawn and the finger arriving.
        _snackFailure(messenger, l10n, result);
      },
      child: card,
    ).tagged('queue.swipe_delete').tourTarget('queue.swipe_delete.${item.id}');
  }
}

class _Subtitle extends ConsumerWidget {
  const _Subtitle({required this.item});

  final QueueItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final parts = <String>[
      if (item.printerName != null) item.printerName!,
      // A cross-model item (server #671) has no printer yet and never will
      // until dispatch picks one, so without this the row would say nothing
      // about where it can run. Naming the candidates beats a bare "Any model":
      // the whole point is that the user chose this specific set.
      if (item.isCrossModel) queueTargetLabel(l10n, item),
      if (item.printTimeSeconds != null) _eta(l10n, item.printTimeSeconds!),
      // Which order or grouping the run belongs to — the only link from a
      // queue row to its order's progress.
      if (item.batchName != null) l10n.queueInBatch(item.batchName!),
      // Says the print will land in the exact trays the slicer picked, rather
      // than trays the scheduler works out from the file's type and colour.
      // Server ≥ 1.2.5.2; false everywhere else, so the marker just never
      // appears.
      if (item.archiveHasSlicerAmsMapping) l10n.queueAmsFromSlicer,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: DashSpace.xs,
          runSpacing: DashSpace.xs,
          children: [
            _StatusChip(item: item),
            // The web's Staged badge, which says who starts the job to a user
            // held for review (#1620).
            if (item.manualStart)
              _Chip(
                label: queueStagedLabel(
                  l10n,
                  awaitingReview: ref.watch(awaitingReviewProvider),
                ),
                accent: t.textTertiary,
              ),
          ],
        ),
        if (parts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: DashSpace.xs),
            child: Text(
              parts.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.monoLabel,
            ),
          ),
      ],
    );
  }

  String _eta(AppLocalizations l10n, int seconds) {
    final minutes = seconds ~/ 60;
    return formatMinutes(l10n, minutes);
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.item});

  final QueueItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final (label, accent) = queueStatusLabel(l10n, t, item);
    return _Chip(label: label, accent: accent);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    // Pending/unknown statuses get a subtle neutral pill instead of a
    // colored one — there's nothing actionable to draw the eye to.
    final neutral = accent == t.textTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DashSpace.sm,
        vertical: DashSpace.xs,
      ),
      decoration: BoxDecoration(
        color: neutral ? t.subCard : accent.withValues(alpha: DashAlpha.wash),
        borderRadius: BorderRadius.circular(DashRadius.xl),
        border: Border.all(
          color: neutral
              ? t.subCardBorder
              : accent.withValues(alpha: DashAlpha.outline),
        ),
      ),
      child: Text(
        label,
        style: t.micro.copyWith(
          color: accent,
          letterSpacing: DashTracking.label,
        ),
      ),
    );
  }
}

class _QueueActions extends ConsumerWidget {
  const _QueueActions({required this.item});

  final QueueItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    // Printing item doesn't make sense to "start"; any active item can cancel.
    final canStart =
        item.statusKind == QueueItemStatusKind.pending ||
        item.statusKind == QueueItemStatusKind.scheduled;
    final mayStart =
        canStart &&
        ref.watch(
          mayStartQueueItemProvider((
            createdById: item.createdById,
            printerId: item.printerId,
          )),
        );
    // Which route takes this item out of the queue, and how to word it. The
    // printer's own state only separates "stop the print" from "remove the
    // leftover row": a printer that failed is not printing anything to abort,
    // which is exactly what the item that raised #35 looked like.
    final printerId = item.printerId;
    final removal = queueRemovalFor(
      item.statusKind,
      printerBusy:
          printerId != null &&
          ref.watch(
                printerStatusesProvider.select((m) => m[printerId]?.isPrinting),
              ) ==
              true,
    );
    final canPreview = item.archiveId != null || item.libraryFileId != null;
    // Filament mapping needs a printer (for its AMS) and a source file.
    final canMap = canPreview && item.printerId != null;

    return logTag(
      'queue.actions',
      PopupMenuButton<String>(
        icon: Icon(Icons.more_vert, color: t.textSecondary),
        onSelected: (value) async {
          if (value == 'preview') {
            _previewGcode(context);
            return;
          }
          if (value == 'edit') {
            await openQueueEdit(context, item);
            return;
          }
          // Start: shared flow (assign printer if none → mapping → start).
          if (value == 'start') {
            await startQueueItem(context, ref, item, l10n);
            return;
          }
          final messenger = ScaffoldMessenger.of(context);
          final notifier = ref.read(queueProvider.notifier);

          // Standalone mapping (save without starting) — needs a known printer.
          if (value == 'ams' && printerId != null) {
            final mapping = await showQueueMappingSheet(
              context,
              item: item,
              printerId: printerId,
              confirmLabel: l10n.fmSave,
            );
            // Empty: the printer reported nothing to map to, and the web sends
            // no mapping then — saving [] would clear the stored one.
            if (mapping == null || mapping.isEmpty) return;
            final r = await notifier.saveMapping(item.id, mapping);
            messenger.snack(queueWriteMessage(l10n, r) ?? l10n.mappingSaved);
            return;
          }

          if (value != 'remove') return;
          await removeFromQueue(
            context,
            notifier,
            messenger,
            l10n,
            item: item,
            removal: removal,
          );
        },
        itemBuilder: (_) => [
          if (mayStart)
            PopupMenuItem(
              value: 'start',
              child: logTag(
                'queue.action.start',
                ListTile(
                  leading: const Icon(Icons.play_arrow),
                  title: Text(l10n.queueStart),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          // Only pending/scheduled items are editable server-side.
          if (canStart)
            PopupMenuItem(
              value: 'edit',
              child: logTag(
                'queue.action.edit',
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(l10n.queueEdit),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          if (canPreview)
            PopupMenuItem(
              value: 'preview',
              child: logTag(
                'queue.action.preview',
                ListTile(
                  leading: const Icon(Icons.view_in_ar_outlined),
                  title: Text(l10n.gcodeViewerOpen),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          if (canMap)
            PopupMenuItem(
              value: 'ams',
              child: logTag(
                'queue.action.mapping',
                ListTile(
                  leading: const Icon(Icons.bento_outlined),
                  title: Text(l10n.queueFilamentMapping),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          PopupMenuItem(
            value: 'remove',
            // The id stays `queue.action.cancel` across all four removals: it
            // is a wire value, and renaming it would decorrelate every log
            // recorded before this screen learned the other three routes.
            child: logTag(
              'queue.action.cancel',
              ListTile(
                leading: Icon(switch (removal) {
                  QueueRemoval.cancel ||
                  QueueRemoval.stopPrint => Icons.stop_circle_outlined,
                  QueueRemoval.stopAbandoned ||
                  QueueRemoval.delete => Icons.delete_outline,
                }),
                title: Text(switch (removal) {
                  QueueRemoval.cancel => l10n.queueCancel,
                  QueueRemoval.stopPrint => l10n.queueStop,
                  QueueRemoval.stopAbandoned ||
                  QueueRemoval.delete => l10n.queueRemove,
                }),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Opens fullscreen G-code preview for item source (archive or library file).
  ///
  /// The item's plate goes with it, so a multi-plate job previews the plate it
  /// will actually print.
  void _previewGcode(BuildContext context) {
    context.push(
      gcodeViewerRoute(
        archiveId: item.archiveId,
        libraryFileId: item.libraryFileId,
        plate: item.plateId,
        title: item.archiveName ?? item.libraryFileName,
      ),
    );
  }
}

/// Says nothing on success: the change is already visible in the list.
/// Says nothing when [result] succeeded — the row leaving the list is the
/// confirmation — and otherwise what [queueWriteMessage] made of the refusal.
void _snackFailure(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  ActionOutcome result,
) {
  final text = queueWriteMessage(l10n, result);
  if (text == null) return;
  messenger.snack(text);
}
