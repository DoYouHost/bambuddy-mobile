import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/action_outcome.dart';
import '../../core/diagnostics/log_tag.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/format/duration_format.dart';
import '../../core/models/printer.dart';
import '../../core/models/queue_item.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import '../common/confirm_dialog.dart';
import '../common/dash_async.dart';
import '../common/dash_sheet.dart';
import '../common/dash_snack.dart';
import '../common/plate_clear.dart';
import '../common/state_views.dart';
import '../common/print_thumbnail.dart';
import '../dashboard/ws_providers.dart';
import '../files/library_thumbnail.dart';
import 'queue_edit_screen.dart';
import 'queue_mapping_sheet.dart';
import 'queue_providers.dart';

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

class _QueueScreenState extends ConsumerState<QueueScreen> {
  /// Auto-refresh frequency in foreground. Less frequent than Dashboard's roster
  /// (5s) — queue changes slower and fetch is heavier.
  static const _refreshInterval = Duration(seconds: 10);

  Timer? _timer;
  late final AppLifecycleListener _lifecycle;

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
        unawaited(ref.read(queueProvider.notifier).refresh());
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
      (_) => unawaited(ref.read(queueProvider.notifier).refresh()),
    );
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stopTimer();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final async = ref.watch(queueProvider);

    // Pending prints (excluding currently printing) — "start next" button
    // visibility depends on their presence.
    final items = async.valueOrNull ?? const <QueueItem>[];
    final queued = [
      for (final i in items)
        if (i.statusKind != QueueItemStatusKind.printing) i,
    ];
    final firstQueued = queued.isEmpty ? null : queued.first;

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(
          context,
          title: l10n.navQueue,
          actions: [
            if (queued.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 16),
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
        floatingActionButton: firstQueued == null
            ? null
            : logTag(
                'queue.start_next',
                FloatingActionButton.extended(
                  onPressed: () => _startNext(context, ref, firstQueued, l10n),
                  backgroundColor: t.accentGreen,
                  foregroundColor: const Color(0xFF0A0C08),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l10n.queueStartNext),
                ),
              ),
        body: dashAsync(
          context,
          async,
          onRetry: () => ref.read(queueProvider.notifier).refresh(),
          data: (items) => RefreshIndicator(
            onRefresh: () => ref.read(queueProvider.notifier).refresh(),
            child: items.isEmpty
                ? EmptyStateView(
                    message: l10n.queueEmpty,
                    icon: Icons.playlist_add_check,
                  )
                : _QueueList(items: items),
          ),
        ),
      ),
    );
  }

  /// FAB "start next" — delegates to the shared start flow (assign a printer if
  /// the item has none, then filament mapping, then start).
  Future<void> _startNext(
    BuildContext context,
    WidgetRef ref,
    QueueItem item,
    AppLocalizations l10n,
  ) =>
      _startQueueItem(context, ref, item, l10n);
}

/// Printer entry in "start next" picker: name, status (online/offline), and plug
/// icon if printer has smart plug assigned (bambuddy will wake it before start).
/// No explanatory text.
class _PrinterCandidateTile extends StatelessWidget {
  const _PrinterCandidateTile({required this.candidate, required this.onTap});

  final PrinterCandidate candidate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = DashTokens.of(context);
    final p = candidate.printer;
    final offline = !candidate.online;

    return ListTile(
      leading: Icon(
        offline ? Icons.print_disabled_outlined : Icons.print_outlined,
        color: offline ? theme.disabledColor : null,
      ),
      title: Text(p.name),
      subtitle: Text(
        offline ? l10n.offline : l10n.online,
        style: theme.textTheme.bodySmall?.copyWith(
          color: offline ? theme.disabledColor : theme.colorScheme.primary,
        ),
      ),
      trailing: candidate.hasPlug
          ? Icon(Icons.power, color: t.accentGreenInk, size: 20)
          : null,
      onTap: onTap,
    ).tagged('queue.printer_option');
  }
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

    return Column(
      children: [
        for (final it in pinned) _QueueCard(item: it, pinned: true),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 6),
            physics: const AlwaysScrollableScrollPhysics(),
            // No default long-press drag — reorder only via explicit handle on left
            // side of tile.
            buildDefaultDragHandles: false,
            itemCount: reorderable.length,
            onReorderItem: (oldIndex, newIndex) async {
              final messenger = ScaffoldMessenger.of(context);
              final result = await ref
                  .read(queueProvider.notifier)
                  .reorder(oldIndex + offset, newIndex + offset);
              _snackForResult(messenger, l10n, result);
            },
            itemBuilder: (context, i) => _QueueCard(
              key: ValueKey(reorderable[i].id),
              item: reorderable[i],
              dragIndex: i,
              // First item in the reorderable list is the one "start next"
              // would launch — highlighted the same as the pinned/printing card.
              nextUp: i == 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _QueueCard extends ConsumerWidget {
  const _QueueCard({
    super.key,
    required this.item,
    this.pinned = false,
    this.dragIndex,
    this.nextUp = false,
  });

  final QueueItem item;

  /// Printing item: pinned on top, highlighted, non-reorderable, no swipe-to-delete
  /// (not wrapped in Dismissible).
  final bool pinned;

  /// Index in reorderable list; when provided, show explicit drag handle on left
  /// (`ReorderableDragStartListener`). Null for pinned items.
  final int? dragIndex;

  /// First (top) item of the reorderable queue — the one "start next" would
  /// launch. Highlighted the same way as the pinned/printing card.
  final bool nextUp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final idx = dragIndex;
    final highlighted = pinned || nextUp;

    final card = logTag(
      'queue.card',
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: t.cardGradient,
          borderRadius: BorderRadius.circular(22),
          // Printing/next-up distinguished by a green-tinted border, not a fill.
          border: Border.all(
            color: highlighted
                ? t.accentGreen.withValues(alpha: 0.3)
                : t.cardBorder,
          ),
        ),
        child: Row(
          children: [
            if (idx != null)
              logTag(
                'queue.reorder',
                ReorderableDragStartListener(
                  index: idx,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Icon(Icons.drag_indicator, color: t.textTertiary),
                  ),
                ),
              ),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: item.archiveId == null && item.libraryFileId != null
                  ? LibraryThumbnail(
                      fileId: item.libraryFileId!,
                      hasThumbnail: item.libraryFileThumbnail != null,
                      size: 56,
                    )
                  : PrintThumbnail(archiveId: item.archiveId, size: 56),
            ),
            const SizedBox(width: 12),
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
                  const SizedBox(height: 6),
                  _Subtitle(item: item),
                ],
              ),
            ),
            _QueueActions(item: item),
          ],
        ),
      ),
    );

    // Printing: no Dismissible — can't swipe-delete (and outside ReorderableListView,
    // so non-reorderable).
    if (pinned) return card;

    return Dismissible(
      key: ValueKey('dismiss_${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: t.danger.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Icon(Icons.delete_outline, color: t.danger),
      ),
      // Dialog here only; actual delete in onDismissed (notifier removes from state) —
      // else Dismissible conflicts with list rebuild.
      confirmDismiss: (_) => confirmDialog(
        context,
        id: 'queue.swipe_delete_confirm',
        title: l10n.queueDeleteTitle,
        message: l10n.queueDeleteBody,
        confirmLabel: l10n.queueDeleteConfirm,
      ),
      onDismissed: (_) async {
        final messenger = ScaffoldMessenger.of(context);
        final result = await ref.read(queueProvider.notifier).delete(item.id);
        _snackForResult(messenger, l10n, result);
      },
      child: card,
    ).tagged('queue.swipe_delete');
  }
}

class _Subtitle extends StatelessWidget {
  const _Subtitle({required this.item});

  final QueueItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final parts = <String>[
      if (item.printerName != null) item.printerName!,
      // A cross-model item (server #671) has no printer yet and never will
      // until dispatch picks one, so without this the row would say nothing
      // about where it can run. Naming the candidates beats a bare "Any model":
      // the whole point is that the user chose this specific set.
      if (item.isCrossModel)
        l10n.queueAnyOfModels(
          [for (final v in item.variants) v.targetModel].join(', '),
        ),
      if (item.printTimeSeconds != null) _eta(l10n, item.printTimeSeconds!),
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
        _StatusChip(item: item),
        if (parts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 5),
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
    final (label, accent) = switch (item.statusKind) {
      QueueItemStatusKind.printing => (l10n.queueStatusPrinting, t.accentGreenInk),
      QueueItemStatusKind.paused => (l10n.queueStatusPaused, t.accentOrange),
      QueueItemStatusKind.scheduled => (l10n.queueStatusScheduled, t.accentBlue),
      QueueItemStatusKind.pending => (l10n.queueStatusPending, t.textTertiary),
      _ => (item.status, t.textTertiary),
    };
    // Pending/unknown statuses get a subtle neutral pill instead of a
    // colored one — there's nothing actionable to draw the eye to.
    final neutral = accent == t.textTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: neutral ? t.subCard : accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: neutral ? t.subCardBorder : accent.withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        label,
        style: t.micro.copyWith(color: accent, letterSpacing: 0.2),
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
    final canStart = item.statusKind == QueueItemStatusKind.pending ||
        item.statusKind == QueueItemStatusKind.scheduled;
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
            await _startQueueItem(context, ref, item, l10n);
            return;
          }
          final messenger = ScaffoldMessenger.of(context);
          final notifier = ref.read(queueProvider.notifier);
          final printerId = item.printerId;

          // Standalone mapping (save without starting) — needs a known printer.
          if (value == 'ams' && printerId != null) {
            final mapping = await showQueueMappingSheet(context,
                item: item, printerId: printerId, confirmLabel: l10n.fmSave);
            if (mapping == null) return;
            final r = await notifier.saveMapping(item.id, mapping);
            messenger.snack(r.messageFor(l10n) ?? l10n.mappingSaved);
            return;
          }

          if (value != 'cancel') return;
          _snackForResult(messenger, l10n, await notifier.cancel(item.id));
        },
        itemBuilder: (_) => [
          if (canStart)
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
            value: 'cancel',
            child: logTag(
              'queue.action.cancel',
              ListTile(
                leading: const Icon(Icons.stop_circle_outlined),
                title: Text(l10n.queueCancel),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Opens fullscreen G-code preview for item source (archive or library file).
  /// App bar title = print name, if known.
  void _previewGcode(BuildContext context) {
    final title = item.archiveName ?? item.libraryFileName;
    final name =
        title == null ? '' : '&name=${Uri.encodeQueryComponent(title)}';
    final source = item.archiveId != null
        ? 'archive=${item.archiveId}'
        : 'library_file=${item.libraryFileId}';
    context.push('/gcode-viewer?$source$name');
  }
}


/// Shared start flow for a queue item, used by the FAB and the ⋮ Start action:
/// assign a printer if the item has none, then the filament-mapping screen
/// (pre-filled, not enforced), then start. Aborts silently if the user backs
/// out of either step.
Future<void> _startQueueItem(
  BuildContext context,
  WidgetRef ref,
  QueueItem item,
  AppLocalizations l10n,
) async {
  final messenger = ScaffoldMessenger.of(context);
  // Read through the app's provider container rather than the widget's `ref`,
  // for the same reason [messenger] is taken up front: this flow spans a
  // printer picker, the mapping sheet, a confirmation and two requests, and the
  // row that started it can be gone before any of those come back — the list
  // rebuilds on every WS refresh, and a removed item shrinks it. `ref` throws
  // the moment its widget is disposed ("Cannot use ref after the widget was
  // disposed"), while the container is the app's own and outlives every screen.
  // Reading through it also keeps each read live at the point of use, instead of
  // a snapshot taken before the sheet was even open.
  final providers = ProviderScope.containerOf(context, listen: false);
  var printerId = item.printerId;
  if (printerId == null) {
    final printer = await _pickQueuePrinter(context, ref, l10n);
    if (printer == null || !context.mounted) return;
    printerId = printer.id;
  }
  final mapping = await showQueueMappingSheet(
    context,
    item: item,
    printerId: printerId,
    confirmLabel: l10n.queueStart,
  );
  if (mapping == null) return; // backed out of mapping → abort

  // Plate-clear gate: when the scheduler requires it and this printer still has
  // a finished job on the plate, confirm + acknowledge (clear-plate) before
  // sending — otherwise the scheduler would hold the print anyway.
  if (await _awaitingPlateClear(providers, printerId)) {
    if (!context.mounted) return;
    final confirmed = await confirmDialog(
      context,
      id: 'queue.plate_clear_confirm',
      title: l10n.plateClearTitle,
      message: l10n.plateClearBody,
      confirmLabel: l10n.plateClearConfirm,
    );
    if (!confirmed) return;
    try {
      await providers.read(printerCommandsRepositoryProvider)
          .clearPlate(printerId);
    } on AppApiException catch (e) {
      showApiFailure(
        messenger,
        e,
        l10n,
        action: 'queue.plate_clear',
        message: recordPlateClearRefusal(
                providers.read(offlinePlateClearProvider.notifier), e.detail)
            ? l10n.plateClearNeedsOnline
            : null,
      );
      return;
    }
  }

  // One thing the container does not guarantee: `queueProvider` is autoDispose,
  // so it outlives this row only because the tab badge in `RootScaffold` keeps
  // it listened to.
  final result = await providers
      .read(queueProvider.notifier)
      .startOnPrinter(item.id, printerId, amsMapping: mapping);
  messenger.snack(result.messageFor(l10n) ?? l10n.queuePrintStarted);
}

/// Whether [printerId] still has a finished job on the plate AND the scheduler
/// requires plate-clear confirmation — i.e. we must acknowledge clearance
/// before sending. Best-effort: unknown state → no confirmation.
///
/// Prefers the last-known cached status: it survives the printer going offline
/// (`mergedWith` keeps `awaiting_plate_clear` through a disconnect on purpose),
/// whereas a fresh REST fetch can degrade to null for a powered-off printer and
/// wrongly skip the ack. Acking an offline printer is valid — clear-plate is a
/// pure server flag (no MQTT / no online requirement), so the scheduler
/// dispatches the pending job once the printer wakes. Falls back to a fresh
/// fetch only when the printer isn't cached.
///
/// Reads through the container rather than a `WidgetRef` because it runs after
/// the mapping sheet, by which time the row that opened it may be disposed —
/// see [_startQueueItem].
Future<bool> _awaitingPlateClear(
    ProviderContainer providers, int printerId) async {
  final gateEnabled = await providers.read(requirePlateClearProvider.future);
  if (!gateEnabled) return false;
  final cached = providers.read(printerStatusesProvider)[printerId];
  if (cached != null) {
    return plateClearPending(cached, gateEnabled: () => gateEnabled);
  }
  try {
    final st =
        await providers.read(printersRepositoryProvider).fetchStatus(printerId);
    return plateClearPending(st, gateEnabled: () => gateEnabled);
  } on AppApiException {
    return false;
  }
}

/// Printer picker for the start flow. OFFLINE printers are selectable too —
/// bambuddy wakes them before start. Returns null on cancel / no candidates.
Future<Printer?> _pickQueuePrinter(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final List<PrinterCandidate> candidates;
  try {
    candidates = await ref.read(availablePrintersProvider.future);
  } on AppApiException catch (e) {
    showApiFailure(messenger, e, l10n, action: 'queue.pick_printer');
    return null;
  }
  if (!context.mounted) return null;
  if (candidates.isEmpty) {
    messenger.snack(l10n.queueNoFreePrinters);
    return null;
  }
  return dashSheet<Printer>(
    context,
    scrollControlled: false,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(l10n.pickPrinterTitle,
                style: Theme.of(ctx).textTheme.titleMedium),
          ),
          for (final c in candidates)
            _PrinterCandidateTile(
              candidate: c,
              onTap: () => Navigator.pop(ctx, c.printer),
            ),
        ],
      ),
    ),
  );
}


/// Says nothing on success: the change is already visible in the list.
void _snackForResult(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  ActionOutcome result,
) {
  final text = result.messageFor(l10n);
  if (text == null) return;
  messenger.snack(text);
}
