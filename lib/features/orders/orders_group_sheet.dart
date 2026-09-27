import 'dart:async';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/current_user.dart';
import '../../core/models/queue_item.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import '../common/dash_async.dart';
import '../queue/queue_providers.dart';
import 'orders_providers.dart';
import 'orders_screen.dart';

/// Waiting jobs this session may group — the only ones `POST /queue/batches`
/// assigns; it skips the rest without saying so: those already in a batch,
/// and without `queue:update_all` any not the caller's own, ownerless ones
/// included (`core/auth.py`: an ownerless item needs the all-permission).
final _groupableProvider = FutureProvider.autoDispose<List<QueueItem>>((
  ref,
) async {
  final me = ref.watch(currentUserProvider).valueOrNull;
  final anyone =
      me == null || ref.watch(permissionProvider(Permissions.queueUpdateAll));
  final pending = await ref
      .watch(queueRepositoryProvider)
      .fetch(status: 'pending');
  return [
    for (final i in pending)
      if (i.batchId == null && (anyone || i.createdById == me.id)) i,
  ];
});

/// Groups waiting queue items into a batch by hand (v0.2.4.8+) — the web
/// queue's "Group as batch".
Future<void> showGroupSheet(BuildContext context) =>
    dashSheet<void>(context, builder: (_) => const _GroupSheet());

class _GroupSheet extends ConsumerStatefulWidget {
  const _GroupSheet();

  @override
  ConsumerState<_GroupSheet> createState() => _GroupSheetState();
}

class _GroupSheetState extends ConsumerState<_GroupSheet> {
  final _name = TextEditingController();
  final _picked = <int>{};
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _ready =>
      !_saving && _picked.length >= 2 && _name.text.trim().isNotEmpty;

  Future<void> _group() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final providers = ProviderScope.containerOf(context, listen: false);
    setState(() => _saving = true);
    try {
      final batch = await providers
          .read(batchRepositoryProvider)
          .create(name: _name.text.trim(), itemIds: _picked.toList());
      // The items the batch holds now, not `quantity`, which the server
      // floors at 1: a pick that started or was grouped elsewhere since this
      // list was read is skipped, and all of them can be.
      final grouped = batch.pendingCount + batch.printingCount;
      if (grouped == 0) {
        // The server made the batch anyway; with no items and no targets it
        // is hidden from the list, and ungrouping deletes it outright.
        try {
          await providers.read(batchRepositoryProvider).ungroup(batch.id);
        } on AppApiException {
          // The outcome below is what the user has to hear.
        }
      }
      providers.invalidate(batchesProvider);
      unawaited(providers.read(queueProvider.notifier).refresh());
      messenger.snack(
        grouped == 0
            ? l10n.ordersGroupedNone
            : l10n.ordersGrouped(grouped, batch.name),
      );
      navigator.pop();
    } on AppApiException catch (e) {
      showApiFailure(
        messenger,
        e,
        l10n,
        action: 'orders_group.confirm',
        message: orderRefusal(l10n, e),
      );
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final async = ref.watch(_groupableProvider);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(l10n.ordersGroup, style: t.titleMd),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(l10n.ordersGroupHint, style: t.bodySoft),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _name,
                style: t.bodyStrong,
                onChanged: (_) => setState(() {}),
                decoration: dashFieldDecoration(
                  t,
                  labelText: l10n.ordersGroupName,
                ),
              ).tagged('orders_group.name'),
            ),
            Flexible(
              child: dashAsync(
                context,
                async,
                onRetry: () => ref.invalidate(_groupableProvider),
                data: (items) => items.length < 2
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(l10n.ordersGroupEmpty, style: t.body),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final i in items)
                            CheckboxListTile(
                              value: _picked.contains(i.id),
                              onChanged: (on) => setState(
                                () => on == true
                                    ? _picked.add(i.id)
                                    : _picked.remove(i.id),
                              ),
                              title: Text(
                                i.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.bodyStrong,
                              ),
                              subtitle: i.printerName == null
                                  ? null
                                  : Text(i.printerName!, style: t.monoMicro),
                              controlAffinity: ListTileControlAffinity.leading,
                              activeColor: t.accentGreen,
                            ).tagged('orders_group.item'),
                        ],
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton(
                onPressed: _ready ? _group : null,
                child: Text(l10n.ordersGroupConfirm),
              ).tagged('orders_group.confirm'),
            ),
          ],
        ),
      ),
    );
  }
}
