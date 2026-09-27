import 'dart:async';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/format/datetime_format.dart';
import '../../core/format/duration_format.dart';
import '../../core/models/current_user.dart';
import '../../core/models/print_batch.dart';
import '../../core/theme/dash_theme.dart';
import '../../data/batch_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/server_refusal.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import '../common/currency_symbol.dart';
import '../common/dash_async.dart';
import '../common/dash_progress_bar.dart';
import '../common/refresh_when_shown.dart';
import '../queue/queue_providers.dart';
import '../stats/stats_common.dart' show fmtNum;
import 'orders_group_sheet.dart';
import 'orders_providers.dart';

/// Batch orders (#342): what was asked for against what has been produced.
///
/// An order outlives the queue it spawned — finished runs leave the queue, so
/// neither the queue nor the archive shows how far along it is. This is the
/// one place that does, and the one that queues the runs still owed.
class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

/// The filter row: the three statuses and, last, every status (null).
const _filters = <PrintBatchStatus?>[
  PrintBatchStatus.active,
  PrintBatchStatus.completed,
  PrintBatchStatus.cancelled,
  null,
];

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  PrintBatchStatus? _filter = PrintBatchStatus.active;

  Future<void> _refresh() => ref.refresh(batchesProvider(_filter).future);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(batchesProvider(_filter));

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(context, title: l10n.ordersTitle),
        floatingActionButton:
            ref.watch(batchGroupingProvider).orFalse &&
                ref.watch(permissionProvider(Permissions.queueCreate))
            ? FloatingActionButton.extended(
                onPressed: () => showGroupSheet(context),
                icon: const Icon(Icons.library_add_outlined),
                label: Text(l10n.ordersGroup),
              ).tagged('orders.group')
            : null,
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final f in _filters)
                      ChoiceChip(
                        label: Text(_filterLabel(l10n, f)),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ).tagged('orders.filter.${f?.name ?? 'all'}'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: RefreshWhenShown(
                onRefresh: _refresh,
                child: dashAsync(
                  context,
                  async,
                  onRetry: _refresh,
                  data: (batches) => RefreshIndicator(
                    onRefresh: _refresh,
                    child: batches.isEmpty
                        ? EmptyStateView(
                            message: l10n.ordersEmpty,
                            icon: Icons.inventory_2_outlined,
                          )
                        : ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(bottom: 88),
                            children: [
                              for (final b in batches)
                                _OrderCard(key: ValueKey(b.id), batch: b),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _filterLabel(AppLocalizations l10n, PrintBatchStatus? f) =>
      switch (f) {
        PrintBatchStatus.active => l10n.ordersFilterActive,
        PrintBatchStatus.completed => l10n.ordersFilterCompleted,
        PrintBatchStatus.cancelled => l10n.ordersFilterCancelled,
        _ => l10n.ordersFilterAll,
      };
}

/// A refused batch write, in the user's words.
///
/// A 404 is the batch gone — or someone else's, which the server will not
/// confirm. The mapper keeps a detail for a 400 or 422 only, so it is told by
/// the status. The stranded-plate 400 names the plates, and
/// that is the part worth keeping. [rules] go before the shared ones.
String orderRefusal(
  AppLocalizations l10n,
  AppApiException e, [
  List<RefusalRule> rules = const [],
]) {
  if (e.statusCode == 404) return l10n.ordersErrGone;
  final stranded = _strandedPlates.firstMatch(e.detail ?? '')?.group(1);
  if (stranded != null) return l10n.ordersErrStranded(stranded);
  return serverRefusal(l10n, e, [
    ...rules,
    (['cancelled batch'], (l) => l.ordersErrCancelled),
  ]);
}

/// `print_batch.py::dispatch_remaining`: "Rings, Plate 3 have no queued or
/// finished run to copy settings from. …"
final _strandedPlates = RegExp(r'^(.+?) (?:has|have) no queued or finished');

class _OrderCard extends ConsumerStatefulWidget {
  const _OrderCard({super.key, required this.batch});

  final PrintBatch batch;

  @override
  ConsumerState<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends ConsumerState<_OrderCard> {
  PrintBatch get _b => widget.batch;

  /// Sends [send], says [done] or the refusal, then re-reads the orders and
  /// the queue: a dispatch or a cancel changes both.
  Future<void> _run(
    Future<Object?> Function(BatchRepository repo) send, {
    required String action,
    required String Function(Object? answer) done,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final providers = ProviderScope.containerOf(context, listen: false);
    final inFlight = providers.read(ordersInFlightProvider.notifier);
    final id = _b.id;
    // Checked and taken in the same turn, so two taps in one frame are one.
    if (inFlight.state.contains(id)) return;
    inFlight.state = {...inFlight.state, id};
    try {
      final answer = await send(providers.read(batchRepositoryProvider));
      messenger.snack(done(answer));
    } on AppApiException catch (e) {
      showApiFailure(
        messenger,
        e,
        l10n,
        action: action,
        message: orderRefusal(l10n, e),
      );
    } finally {
      inFlight.state = {...inFlight.state}..remove(id);
    }
    providers.invalidate(batchesProvider);
    unawaited(providers.read(queueProvider.notifier).refresh());
  }

  Future<void> _dispatch([PrintBatchPlate? plate]) {
    final l10n = AppLocalizations.of(context);
    return _run(
      (repo) => repo.dispatch(_b.id, plate: plate),
      action: plate == null ? 'orders.dispatch' : 'orders.dispatch_plate',
      done: (_) => plate == null
          ? l10n.ordersDispatched(_b.name)
          : l10n.ordersPlateDispatched(batchPlateLabel(l10n, plate), _b.name),
    );
  }

  Future<void> _cancel() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await confirmDialog(
      context,
      id: 'orders.cancel_confirm',
      title: l10n.ordersCancelTitle,
      message: l10n.ordersCancelBody,
      confirmLabel: l10n.ordersCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _run(
      (repo) => repo.cancel(_b.id),
      action: 'orders.action.cancel',
      done: (_) => l10n.ordersCancelled,
    );
  }

  Future<void> _reopen() {
    final l10n = AppLocalizations.of(context);
    return _run(
      (repo) => repo.update(_b.id, reopen: true),
      action: 'orders.action.reopen',
      done: (_) => l10n.ordersReopened,
    );
  }

  Future<void> _ungroup() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await confirmDialog(
      context,
      id: 'orders.ungroup_confirm',
      title: l10n.ordersUngroupTitle,
      message: _b.hasTargets
          ? l10n.ordersUngroupOrderBody
          : l10n.ordersUngroupBody,
      confirmLabel: l10n.ordersUngroup,
      destructive: _b.hasTargets,
    );
    if (!confirmed || !mounted) return;
    await _run(
      (repo) => repo.ungroup(_b.id),
      action: 'orders.action.ungroup',
      done: (count) => l10n.ordersUngrouped(count as int),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final b = _b;
    final busy = ref.watch(
      ordersInFlightProvider.select((s) => s.contains(b.id)),
    );
    final open = b.status != PrintBatchStatus.cancelled;
    // Every write but cancel looks the batch up for its owner, and answers
    // someone else's with a 404 unless the caller may change all of them.
    // Unknown identity: offered, and the server decides.
    final me = ref.watch(currentUserProvider).valueOrNull;
    final canTouch =
        b.createdById == null ||
        me == null ||
        b.createdById == me.id ||
        ref.watch(permissionProvider(Permissions.queueUpdateAll));
    final canQueue =
        open &&
        canTouch &&
        ref.watch(permissionProvider(Permissions.queueCreate));
    final canCancel =
        b.status == PrintBatchStatus.active &&
        ref.watch(permissionProvider(Permissions.queueDeleteAll));
    final canUpdate =
        canTouch && ref.watch(permissionProvider(Permissions.queueUpdateOwn));
    final orders = ref.watch(batchOrdersProvider).orFalse;
    final actions = <_MenuAction>[
      // PATCH, so 1.2.5.3+ even for a grouping, which has a name and notes too.
      if (canUpdate && orders)
        (
          id: 'orders.action.edit',
          icon: Icons.edit_outlined,
          label: l10n.ordersEdit,
          onTap: () => context.push('/orders/${b.id}/edit'),
        ),
      // Only an order that still owes runs: a grouping, or an order already
      // fulfilled, would be completed again by the server on the spot.
      if (canUpdate && orders && b.hasTargets && !open && b.remainingCount > 0)
        (
          id: 'orders.action.reopen',
          icon: Icons.restart_alt,
          label: l10n.ordersReopen,
          onTap: _reopen,
        ),
      if (canCancel)
        (
          id: 'orders.action.cancel',
          icon: Icons.cancel_outlined,
          label: l10n.ordersCancel,
          onTap: _cancel,
        ),
      if (canUpdate && ref.watch(batchGroupingProvider).orFalse)
        (
          id: 'orders.action.ungroup',
          icon: Icons.call_split,
          label: l10n.ordersUngroup,
          onTap: _ungroup,
        ),
    ];
    final total = b.progressTotal;

    return logTag(
      'orders.card',
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
        decoration: t.cardBox,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _Header(batch: b)),
                if (actions.isNotEmpty)
                  _OrderMenu(enabled: !busy, actions: actions),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: DashProgressBar(
                      value: total > 0
                          ? (b.completedCount / total).clamp(0.0, 1.0)
                          : 0,
                      height: 6,
                      color: b.status == PrintBatchStatus.completed
                          ? null
                          : t.accentBlue,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    l10n.ordersProgress(b.completedCount, total),
                    style: t.monoLabel,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            _Numbers(batch: b, open: open),
            if (open && b.stranded > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 8),
                child: Text(
                  l10n.ordersStrandedNotice(b.stranded, b.remainingCount),
                  style: t.bodySoft.copyWith(color: t.accentOrangeInk),
                ),
              ),
            if (b.hasTargets && b.plates.isNotEmpty) ...[
              const SizedBox(height: 8),
              Divider(height: 1, color: t.hairline),
              for (final p in b.plates)
                _PlateRow(
                  plate: p,
                  offerDispatch: canQueue && !busy,
                  showOwed: open,
                  onDispatch: () => _dispatch(p),
                ),
            ],
            if (canQueue && b.dispatchable > 0)
              Padding(
                padding: const EdgeInsets.only(top: 10, right: 8),
                child: FilledButton.icon(
                  onPressed: busy ? null : _dispatch,
                  icon: const Icon(Icons.playlist_add),
                  label: Text(l10n.ordersDispatchRemaining(b.dispatchable)),
                ).tagged('orders.dispatch'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.batch});

  final PrintBatch batch;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final b = batch;
    final due = b.dueDate;
    final overdue = b.isOverdue(DateTime.now());
    final who = b.createdByUsername;
    final (statusLabel, accent, ink) = switch (b.status) {
      PrintBatchStatus.active => (
        l10n.ordersStatusActive,
        t.accentBlue,
        t.accentBlue,
      ),
      PrintBatchStatus.completed => (
        l10n.ordersStatusCompleted,
        t.accentGreen,
        t.accentGreenInk,
      ),
      PrintBatchStatus.cancelled => (
        l10n.ordersStatusCancelled,
        t.textTertiary,
        t.textTertiary,
      ),
      PrintBatchStatus.unknown => (
        l10n.ordersStatusUnknown,
        t.textTertiary,
        t.textTertiary,
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          b.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: t.titleMd,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            DashPill(
              label: statusLabel,
              accent: accent,
              accentInk: ink,
              dense: true,
            ),
            if (!b.hasTargets)
              DashPill(
                label: l10n.ordersGroupingOnly,
                accent: t.textTertiary,
                dense: true,
              ),
            if (b.externalSource != null)
              DashPill(
                label: [b.externalSource!, ?b.externalRef].join(' · '),
                accent: t.textSecondary,
                icon: Icons.storefront_outlined,
                dense: true,
              ),
          ],
        ),
        if (who != null || due != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text.rich(
              TextSpan(
                style: t.bodySoft,
                children: [
                  if (who != null) TextSpan(text: l10n.ordersBy(who)),
                  if (who != null && due != null) const TextSpan(text: ' · '),
                  if (due != null)
                    TextSpan(
                      text: l10n.ordersDue(
                        DateTimeFormats.of(context).date(due),
                      ),
                      style: overdue
                          ? TextStyle(color: t.accentOrangeInk)
                          : null,
                    ),
                ],
              ),
            ),
          ),
        if (b.notes != null && b.notes!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              b.notes!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: t.bodySoft,
            ),
          ),
      ],
    );
  }
}

/// Counts, time and cost in one wrapped line, each shown only when it says
/// something — as the web does.
class _Numbers extends ConsumerWidget {
  const _Numbers({required this.batch, required this.open});

  final PrintBatch batch;

  /// False on a cancelled order, which owes nothing any more.
  final bool open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final b = batch;
    final currency = ref.watch(currencySymbolProvider);
    String money(double v) => formatMoney(currency, v.toStringAsFixed(2));
    final parts = <String>[
      if (b.printingCount > 0) l10n.ordersPrinting(b.printingCount),
      if (b.pendingCount > 0) l10n.ordersPending(b.pendingCount),
      if (b.failedCount > 0) l10n.ordersFailed(b.failedCount),
      if (open && b.hasTargets && b.remainingCount > 0)
        l10n.ordersOwed(b.remainingCount),
      if (b.printTimeSeconds > 0) formatSeconds(l10n, b.printTimeSeconds),
      if (b.actualCost != null) l10n.ordersCostSoFar(money(b.actualCost!)),
      if (open && b.actualCost != null && (b.estimatedRemainingCost ?? 0) > 0)
        l10n.ordersCostToGo(money(b.estimatedRemainingCost!)),
      if (b.filamentUsedGrams != null && b.filamentUsedGrams! > 0)
        '${fmtNum(b.filamentUsedGrams!)} g',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Text(parts.join(' · '), style: t.monoLabel),
    );
  }
}

class _PlateRow extends StatelessWidget {
  const _PlateRow({
    required this.plate,
    required this.offerDispatch,
    required this.showOwed,
    required this.onDispatch,
  });

  final PrintBatchPlate plate;
  final bool offerDispatch;

  /// False on a cancelled order: it owes nothing any more.
  final bool showOwed;
  final VoidCallback onDispatch;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final p = plate;
    final owed = showOwed && p.remaining > 0;
    final detail = [
      l10n.ordersPlateProgress(p.completedCount, p.quantityTarget),
      if (p.failedCount > 0) l10n.ordersFailed(p.failedCount),
      if (owed) l10n.ordersOwed(p.remaining),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(Icons.layers_outlined, size: 18, color: t.textTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  batchPlateLabel(l10n, p),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyStrong,
                ),
                Text(detail, style: t.monoMicro),
                if (owed && !p.dispatchable)
                  Text(
                    l10n.ordersStrandedPlate,
                    style: t.microSoft.copyWith(color: t.accentOrangeInk),
                  ),
              ],
            ),
          ),
          if (owed && p.dispatchable && offerDispatch)
            TextButton(
              onPressed: onDispatch,
              child: Text(l10n.ordersDispatchPlate),
            ).tagged('orders.dispatch_plate'),
        ],
      ),
    );
  }
}

/// A plate's name as the order stored it, else its number, else "whole file"
/// for the single-plate file whose `plate_id` is null.
String batchPlateLabel(AppLocalizations l10n, PrintBatchPlate p) =>
    p.plateName ??
    (p.plateId != null ? l10n.archivePlate(p.plateId!) : l10n.ordersWholeFile);

/// One row of an order's ⋮ menu; [id] names the row in the diagnostic log.
typedef _MenuAction = ({
  String id,
  IconData icon,
  String label,
  VoidCallback onTap,
});

class _OrderMenu extends StatelessWidget {
  const _OrderMenu({required this.enabled, required this.actions});

  final bool enabled;
  final List<_MenuAction> actions;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return logTag(
      'orders.actions',
      PopupMenuButton<_MenuAction>(
        enabled: enabled,
        icon: Icon(Icons.more_vert, color: t.textSecondary),
        onSelected: (a) => a.onTap(),
        itemBuilder: (_) => [
          for (final a in actions)
            PopupMenuItem(
              value: a,
              child: logTag(
                a.id,
                ListTile(
                  leading: Icon(a.icon),
                  title: Text(a.label),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
