import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:app_util/app_util.dart';
import 'package:flutter/foundation.dart' show mergeSort;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/action_outcome.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/format/datetime_format.dart';
import '../../core/format/duration_format.dart';
import '../../core/format/relative_time.dart';
import '../../core/models/current_user.dart';
import '../../core/models/queue_item.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/dash_async.dart';
import '../common/print_thumbnail.dart';
import '../files/library_thumbnail.dart';
import 'queue_edit_screen.dart';
import 'queue_removal.dart';

/// The queue's History tab, as the web's `QueuePage.tsx` (`HistorySection`,
/// `CompactHistoryRow`) shows it: every finished, failed, skipped and
/// cancelled item, why it failed, and a way to queue it again.

enum QueueHistorySort { date, name, printer }

typedef QueueHistoryOrder = ({QueueHistorySort by, bool ascending});

/// The history's order, kept across launches as the web keeps it
/// (`queue.historySortBy`, `queue.historySortAsc`). Newest first by default.
final queueHistoryOrderProvider =
    NotifierProvider<QueueHistoryOrderNotifier, QueueHistoryOrder>(
      QueueHistoryOrderNotifier.new,
    );

class QueueHistoryOrderNotifier extends Notifier<QueueHistoryOrder> {
  static const _byKey = 'queue.history_sort_by';
  static const _ascendingKey = 'queue.history_sort_asc';

  @override
  QueueHistoryOrder build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final by = prefs.getString(_byKey);
    return (
      by: QueueHistorySort.values.firstWhere(
        (s) => s.name == by,
        orElse: () => QueueHistorySort.date,
      ),
      ascending: prefs.getBool(_ascendingKey) ?? false,
    );
  }

  void set(QueueHistoryOrder order) {
    state = order;
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setString(_byKey, order.by.name);
    prefs.setBool(_ascendingKey, order.ascending);
  }
}

final queueHistoryProvider =
    AsyncNotifierProvider.autoDispose<QueueHistoryNotifier, List<QueueItem>>(
      QueueHistoryNotifier.new,
    );

class QueueHistoryNotifier extends AutoDisposeAsyncNotifier<List<QueueItem>> {
  @override
  Future<List<QueueItem>> build() =>
      ref.watch(queueRepositoryProvider).fetchHistory();

  /// Keeps the rows on screen while the new answer is out.
  Future<void> refresh() async {
    state = const AsyncValue<List<QueueItem>>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard(
      ref.read(queueRepositoryProvider).fetchHistory,
    );
  }
}

/// `historyItems`: newest first by the time each finished (else was queued),
/// or by name or printer. Stable, as the browser's sort is, so ties keep the
/// server's order.
List<QueueItem> sortQueueHistory(
  List<QueueItem> items,
  QueueHistoryOrder order,
) {
  // ponytail: lower-cased compareTo for the web's localeCompare; collation
  // only differs for accented names.
  int text(String? a, String? b) =>
      (a ?? '').toLowerCase().compareTo((b ?? '').toLowerCase());
  int millis(QueueItem i) =>
      (i.completedAt ?? i.createdAt)?.millisecondsSinceEpoch ?? 0;
  final sorted = [...items];
  mergeSort(
    sorted,
    compare: (a, b) {
      final cmp = switch (order.by) {
        QueueHistorySort.name => text(
          a.archiveName ?? a.libraryFileName,
          b.archiveName ?? b.libraryFileName,
        ),
        QueueHistorySort.printer => text(a.printerName, b.printerName),
        QueueHistorySort.date => millis(b) - millis(a),
      };
      return order.ascending ? -cmp : cmp;
    },
  );
  return sorted;
}

/// One line of the history: an item, or every item of one batch.
typedef QueueHistoryRow = ({
  QueueItem? item,
  int? batchId,
  String? batchName,
  List<QueueItem> batch,
});

/// The rows the first [visible] items make (`HistorySection`): an item of a
/// batch stands for the whole batch, at the place its first item sorts to, and
/// carries every sibling — shown or not yet.
List<QueueHistoryRow> queueHistoryRows(List<QueueItem> sorted, int visible) {
  final rows = <QueueHistoryRow>[];
  final seen = <int>{};
  for (final item in sorted.take(visible)) {
    final batchId = item.batchId;
    if (batchId == null) {
      rows.add((item: item, batchId: null, batchName: null, batch: const []));
      continue;
    }
    if (!seen.add(batchId)) continue;
    rows.add((
      item: null,
      batchId: batchId,
      batchName: item.batchName,
      batch: [
        for (final s in sorted)
          if (s.batchId == batchId) s,
      ],
    ));
  }
  return rows;
}

/// `canModify(resource, action, createdById)` (web `AuthContext.tsx`): the
/// `_all` permission, or the `_own` one on the user's own item. Unknown
/// identity offers it and lets the server decide, as [permissionProvider] does.
bool canModifyOwned(
  CurrentUser? me, {
  required String all,
  required String own,
  required int? createdById,
}) {
  if (me == null || me.can(all)) return true;
  if (!me.can(own)) return false;
  return createdById != null && createdById == me.id;
}

/// The History tab's body.
class QueueHistoryView extends ConsumerStatefulWidget {
  const QueueHistoryView({super.key});

  /// `HISTORY_PAGE_SIZE`: rows drawn at first, and added per "show more".
  static const pageSize = 50;

  @override
  ConsumerState<QueueHistoryView> createState() => _QueueHistoryViewState();
}

class _QueueHistoryViewState extends ConsumerState<QueueHistoryView> {
  int _visible = QueueHistoryView.pageSize;

  /// Batches start folded, as on the web.
  final Set<int> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(queueHistoryProvider);
    // A new order starts again from one page (#2682 on the web).
    ref.listen(queueHistoryOrderProvider, (_, _) {
      setState(() => _visible = QueueHistoryView.pageSize);
    });
    final order = ref.watch(queueHistoryOrderProvider);
    Future<void> refresh() => ref.read(queueHistoryProvider.notifier).refresh();

    return dashAsync(
      context,
      async,
      onRetry: refresh,
      data: (items) {
        if (items.isEmpty) {
          return RefreshIndicator(
            onRefresh: refresh,
            child: EmptyStateView(
              message: l10n.queueHistoryEmpty,
              icon: Icons.format_list_numbered,
            ),
          );
        }
        final sorted = sortQueueHistory(items, order);
        final rows = queueHistoryRows(sorted, _visible);
        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              DashSpace.gutter,
              DashSpace.sm,
              DashSpace.gutter,
              DashSpace.xxl,
            ),
            children: [
              _Header(items: sorted),
              const SizedBox(height: DashSpace.md),
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: DashSpace.sm),
                  child: row.item != null
                      ? _HistoryRow(item: row.item!)
                      : _BatchRow(
                          row: row,
                          expanded: _expanded.contains(row.batchId),
                          onToggle: () => setState(() {
                            if (!_expanded.remove(row.batchId)) {
                              _expanded.add(row.batchId!);
                            }
                          }),
                        ),
                ),
              if (sorted.length > _visible) ...[
                const SizedBox(height: DashSpace.sm),
                Center(
                  child: OutlinedButton(
                    onPressed: () =>
                        setState(() => _visible += QueueHistoryView.pageSize),
                    child: Text(l10n.queueHistoryShowMore),
                  ).tagged('queue_history.show_more'),
                ),
                const SizedBox(height: DashSpace.xs),
                Center(
                  child: Text(
                    // Only drawn while there are more, so every visible row is shown.
                    l10n.queueHistoryShowing(_visible, sorted.length),
                    style: DashTokens.of(context).micro,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// "History (12 items)", the order, and clearing it all.
class _Header extends ConsumerWidget {
  const _Header({required this.items});

  final List<QueueItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final order = ref.watch(queueHistoryOrderProvider);
    final canClear = ref.watch(permissionProvider(Permissions.queueDeleteAll));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: l10n.queueHistory,
                  style: t.titleMd,
                  children: [
                    TextSpan(
                      text: '  ${l10n.queueItemCount(items.length)}',
                      style: t.micro.copyWith(color: t.textTertiary),
                    ),
                  ],
                ),
              ),
            ),
            _SortMenu(order: order),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Tooltip(
            message: canClear ? '' : l10n.queueHistoryNoClear,
            child: TextButton.icon(
              icon: const Icon(Icons.delete_sweep_outlined),
              label: Text(l10n.queueHistoryClear),
              onPressed: canClear ? () => _clear(context, ref) : null,
            ).tagged('queue_history.clear'),
          ),
        ),
      ],
    );
  }

  /// `clearHistoryMutation`: every history item, one `DELETE` each, counting
  /// the ones the server keeps for a batch order rather than deletes.
  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await confirmDialog(
      context,
      id: 'queue_history.clear_confirm',
      title: l10n.queueHistoryClearTitle,
      message: l10n.queueHistoryClearMessage(items.length),
      confirmLabel: l10n.queueHistoryClear,
      destructive: true,
    );
    if (!ok) return;
    final repo = ref.read(queueRepositoryProvider);
    var cleared = 0;
    var kept = 0;
    try {
      for (final item in items) {
        if (await repo.delete(item.id)) {
          cleared++;
        } else {
          kept++;
        }
      }
      messenger.snack(
        kept > 0
            ? '${l10n.queueHistoryCleared(cleared)} '
                  '${l10n.queueHistoryKeptForOrders(kept)}'
            : l10n.queueHistoryCleared(cleared),
      );
    } on AppApiException catch (e) {
      ActionOutcome.failed(e, action: 'queue_history.clear');
      messenger.snack(l10n.queueHistoryClearFailed);
    } finally {
      await ref.read(queueHistoryProvider.notifier).refresh();
    }
  }
}

class _SortMenu extends ConsumerWidget {
  const _SortMenu({required this.order});

  final QueueHistoryOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final notifier = ref.read(queueHistoryOrderProvider.notifier);
    PopupMenuEntry<String> caption(String text) => PopupMenuItem<String>(
      enabled: false,
      height: 32,
      child: Text(text, style: t.micro.copyWith(color: t.textTertiary)),
    );
    return logTag(
      'queue_history.sort',
      PopupMenuButton<String>(
        icon: Icon(Icons.sort, color: t.textSecondary),
        tooltip: l10n.queueHistorySort,
        onSelected: (value) {
          if (value == 'asc' || value == 'desc') {
            notifier.set((by: order.by, ascending: value == 'asc'));
            return;
          }
          notifier.set((
            by: QueueHistorySort.values.byName(value),
            ascending: order.ascending,
          ));
        },
        itemBuilder: (context) => [
          caption(l10n.queueHistorySort),
          for (final s in QueueHistorySort.values)
            CheckedPopupMenuItem(
              value: s.name,
              checked: order.by == s,
              child: logTag(
                'queue_history.sort.${s.name}',
                Text(switch (s) {
                  QueueHistorySort.date => l10n.queueHistorySortDate,
                  QueueHistorySort.name => l10n.queueHistorySortName,
                  QueueHistorySort.printer => l10n.queueHistorySortPrinter,
                }),
              ),
            ),
          const PopupMenuDivider(),
          caption(l10n.printLogSortDirection),
          CheckedPopupMenuItem(
            value: 'desc',
            checked: !order.ascending,
            child: logTag(
              'queue_history.sort.desc',
              Text(l10n.queueHistoryNewestFirst),
            ),
          ),
          CheckedPopupMenuItem(
            value: 'asc',
            checked: order.ascending,
            child: logTag(
              'queue_history.sort.asc',
              Text(l10n.queueHistoryOldestFirst),
            ),
          ),
        ],
      ),
    );
  }
}

/// How each history status is marked (`STATUS_CONFIG`).
(IconData, Color) _statusLook(DashTokens t, QueueItemStatusKind kind) =>
    switch (kind) {
      QueueItemStatusKind.completed => (
        Icons.check_circle_outline,
        t.accentGreenInk,
      ),
      QueueItemStatusKind.failed => (Icons.highlight_off, t.dangerInk),
      QueueItemStatusKind.skipped => (Icons.skip_next, t.accentOrangeInk),
      _ => (Icons.block, t.textTertiary),
    };

/// `normalizeFilamentColor`: one colour, `RRGGBB` or `RRGGBBAA`; all zeros is
/// Bambu's "no filament", and a list of several gets no swatch at all.
Color? _swatchOf(String? raw) {
  final hex = (raw ?? '').replaceFirst(RegExp('^#'), '');
  if (!RegExp(r'^[0-9a-fA-F]{6,8}$').hasMatch(hex)) return null;
  if (RegExp(r'^0{6,8}$').hasMatch(hex)) return null;
  return colorFromHex(hex.substring(0, 6));
}

/// `CompactHistoryRow`: status, thumbnail, name, when, re-queue and remove;
/// below, the printer, the filament, how long it took and who queued it; and
/// for a failed or skipped item, why.
class _HistoryRow extends ConsumerWidget {
  const _HistoryRow({required this.item});

  final QueueItem item;

  static const _statusSize = 18.0;
  static const _thumbSize = 32.0;

  /// The meta and error lines start under the name, past the icon and
  /// thumbnail.
  static const _indent = _statusSize + DashSpace.sm + _thumbSize + DashSpace.sm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final (icon, ink) = _statusLook(t, item.statusKind);
    final me = ref.watch(currentUserProvider).valueOrNull;
    final canRequeue = ref.watch(permissionProvider(Permissions.queueCreate));
    final canRemove = canModifyOwned(
      me,
      all: Permissions.queueDeleteAll,
      own: Permissions.queueDeleteOwn,
      createdById: item.createdById,
    );
    final hasSource = item.archiveId != null || item.libraryFileId != null;
    final swatch = _swatchOf(item.filamentColor);
    final grams = item.filamentUsedGrams;
    final mass = grams == null || grams == 0 ? null : '${grams.round()} g';
    final filament = [?mass, ?item.filamentType].join(' ');
    final showError =
        (item.errorMessage ?? '').isNotEmpty &&
        (item.statusKind == QueueItemStatusKind.failed ||
            item.statusKind == QueueItemStatusKind.skipped);
    final meta = t.micro.copyWith(color: t.textTertiary);

    Widget metaItem(Widget lead, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        lead,
        const SizedBox(width: DashSpace.xs),
        Flexible(
          child: Text(
            text,
            style: meta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    return logTag(
      'queue_history.row',
      Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DashSpace.md,
          vertical: DashSpace.sm,
        ),
        decoration: BoxDecoration(
          gradient: t.cardGradient,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: _statusSize, color: ink),
                const SizedBox(width: DashSpace.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: item.archiveId == null && item.libraryFileId != null
                      ? LibraryThumbnail(
                          fileId: item.libraryFileId!,
                          hasThumbnail: item.libraryFileThumbnail != null,
                          size: _thumbSize,
                        )
                      : PrintThumbnail(
                          archiveId: item.archiveId,
                          size: _thumbSize,
                        ),
                ),
                const SizedBox(width: DashSpace.sm),
                Expanded(
                  child: Text(
                    item.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: DashSpace.xs),
                Text(
                  relativeTime(
                    l10n,
                    DateTimeFormats.of(context),
                    item.completedAt ?? item.createdAt,
                    now: DateTime.now(),
                  ),
                  style: meta,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: canRequeue
                      ? l10n.queueHistoryRequeue
                      : l10n.queueHistoryNoRequeue,
                  icon: Icon(Icons.refresh, color: t.accentGreenInk),
                  onPressed: canRequeue && hasSource
                      ? () => _requeue(context)
                      : null,
                ).tagged('queue_history.requeue'),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: canRemove
                      ? l10n.queueHistoryRemove
                      : l10n.queueHistoryNoRemove,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: canRemove ? () => _remove(context, ref) : null,
                ).tagged('queue_history.remove'),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: _indent),
              child: Wrap(
                spacing: DashSpace.md,
                runSpacing: DashSpace.xs,
                children: [
                  if (item.printerName case final printer?)
                    metaItem(
                      Icon(Icons.print_outlined, size: 12, color: meta.color),
                      printer,
                    ),
                  if (swatch != null || mass != null)
                    metaItem(
                      swatch == null
                          ? Icon(
                              Icons.scale_outlined,
                              size: 12,
                              color: meta.color,
                            )
                          : Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: swatch,
                                shape: BoxShape.circle,
                                border: Border.all(color: t.hairline),
                              ),
                            ),
                      filament,
                    ),
                  if (item.printTimeSeconds case final seconds?
                      when seconds > 0)
                    metaItem(
                      Icon(Icons.timer_outlined, size: 12, color: meta.color),
                      formatSeconds(l10n, seconds),
                    ),
                  if (item.createdByUsername case final user?)
                    Tooltip(
                      message: l10n.queueHistoryAddedBy(user),
                      child: metaItem(
                        Icon(Icons.person_outline, size: 12, color: meta.color),
                        user,
                      ),
                    ),
                ],
              ),
            ),
            if (showError)
              Padding(
                padding: const EdgeInsets.only(
                  left: _indent,
                  top: DashSpace.xs,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, size: 12, color: t.dangerInk),
                    const SizedBox(width: DashSpace.xs),
                    Expanded(
                      child: Text(
                        item.errorMessage!,
                        style: t.micro.copyWith(color: t.dangerInk),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The web opens its print dialog on the same file, starting afresh.
  Future<void> _requeue(BuildContext context) => openQueueCreate(
    context,
    draft: QueueItem.draft(
      archiveId: item.archiveId,
      libraryFileId: item.archiveId == null ? item.libraryFileId : null,
      name: item.displayName,
      thumbnail: item.archiveThumbnail ?? item.libraryFileThumbnail,
    ),
  );

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await confirmDialog(
      context,
      id: 'queue_history.remove_confirm',
      title: l10n.queueHistoryRemoveTitle,
      message: l10n.queueHistoryRemoveMessage(item.displayName),
      confirmLabel: l10n.queueHistoryRemove,
      destructive: true,
    );
    if (!ok) return;
    try {
      // `removeMutation`: a row a batch order still needs stays on screen,
      // cancelled, and without a word it would read as a failed delete.
      final deleted = await ref.read(queueRepositoryProvider).delete(item.id);
      messenger.snack(
        deleted ? l10n.queueHistoryRemoved : l10n.queueHistoryKeptForOrder,
      );
    } on AppApiException catch (e) {
      final text = queueWriteMessage(
        l10n,
        ActionOutcome.failed(e, action: 'queue_history.remove'),
      );
      if (text != null) messenger.snack(text);
    }
    await ref.read(queueHistoryProvider.notifier).refresh();
  }
}

/// A batch folded into one line with a count per status and its latest time;
/// unfolded, its items below.
class _BatchRow extends StatelessWidget {
  const _BatchRow({
    required this.row,
    required this.expanded,
    required this.onToggle,
  });

  final QueueHistoryRow row;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final items = row.batch;
    final latest = items
        .map((i) => i.completedAt ?? i.createdAt)
        .nonNulls
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    final counts = [
      for (final kind in const [
        QueueItemStatusKind.completed,
        QueueItemStatusKind.failed,
        QueueItemStatusKind.skipped,
        QueueItemStatusKind.cancelled,
      ])
        (kind, items.where((i) => i.statusKind == kind).length),
    ];
    final meta = t.micro.copyWith(color: t.textTertiary);
    return Container(
      decoration: BoxDecoration(
        gradient: t.cardGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DashSpace.md,
                vertical: DashSpace.sm,
              ),
              child: Row(
                children: [
                  Icon(
                    expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 18,
                    color: t.textTertiary,
                  ),
                  const SizedBox(width: DashSpace.xs),
                  Icon(
                    expanded ? Icons.inventory_2_outlined : Icons.inventory_2,
                    size: 18,
                    color: t.accentBlue,
                  ),
                  const SizedBox(width: DashSpace.sm),
                  Expanded(
                    child: Text(
                      row.batchName ?? l10n.queueHistoryBatch,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.body.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  for (final (kind, n) in counts)
                    if (n > 0) ...[
                      const SizedBox(width: DashSpace.sm),
                      Icon(
                        _statusLook(t, kind).$1,
                        size: 12,
                        color: _statusLook(t, kind).$2,
                      ),
                      Text(
                        ' $n',
                        style: meta.copyWith(color: _statusLook(t, kind).$2),
                      ),
                    ],
                  const SizedBox(width: DashSpace.sm),
                  Text(
                    latest == null
                        ? ''
                        : relativeTime(
                            l10n,
                            DateTimeFormats.of(context),
                            latest,
                            now: DateTime.now(),
                          ),
                    style: meta,
                  ),
                ],
              ),
            ),
          ).tagged('queue_history.batch', expanded: expanded),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DashSpace.sm,
                0,
                DashSpace.sm,
                DashSpace.sm,
              ),
              child: Column(
                children: [
                  for (final child in items)
                    Padding(
                      padding: const EdgeInsets.only(top: DashSpace.sm),
                      child: _HistoryRow(item: child),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
