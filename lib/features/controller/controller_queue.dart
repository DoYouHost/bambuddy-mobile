import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/datetime_format.dart';
import '../../core/format/duration_format.dart';
import '../../core/models/queue_item.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../dashboard/ws_providers.dart';
import '../queue/queue_actions.dart';
import '../queue/queue_item_view.dart';
import '../queue/queue_providers.dart';
import '../queue/queue_removal.dart';
import '../stats/stats_common.dart';
import 'controller_detail_dialog.dart';
import 'controller_list_parts.dart';
import 'controller_providers.dart';
import 'scale_to_fit.dart';

/// The jobs [printerId] will print: those pinned to it, and those queued for
/// any printer of its [model] — the server's own per-printer filter
/// (`print_queue.py::list_queue`), down to its case-insensitive model match and
/// its blindness to the alternatives of a cross-model job, whose `target_model`
/// is its first candidate. With no model known, only the pinned ones. The order
/// is the queue's.
List<QueueItem> queueForPrinter(
  List<QueueItem> items, {
  required int printerId,
  required String? model,
}) {
  final wanted = model?.toLowerCase();
  return [
    for (final item in items)
      if (item.printerId == printerId ||
          (item.printerId == null &&
              wanted != null &&
              item.targetModel?.toLowerCase() == wanted))
        item,
  ];
}

/// The queue screen polls as often; nothing pushes a queue change.
const _poll = Duration(seconds: 10);

/// The Queue view of the Prints tab: what waits for this printer, in the order
/// it will print ([docs/single-printer-controller.md] §8). Start and Remove are
/// the queue screen's own flows; editing, reordering and picking several stay
/// on the phone screens.
class ControllerQueue extends ConsumerStatefulWidget {
  const ControllerQueue({super.key, required this.printerId});

  final int printerId;

  @override
  ConsumerState<ControllerQueue> createState() => _ControllerQueueState();
}

class _ControllerQueueState extends ConsumerState<ControllerQueue> {
  Timer? _timer;
  late final AppLifecycleListener _lifecycle;
  late final _providers = ProviderScope.containerOf(context, listen: false);

  @override
  void initState() {
    super.initState();
    _timer = pollQueue(_providers, _poll);
    _lifecycle = AppLifecycleListener(
      onShow: () {
        _timer?.cancel();
        _timer = pollQueue(_providers, _poll);
      },
      onHide: () => _timer?.cancel(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(queueProvider);
    final model = ref.watch(
      controllerPrinterProvider(
        widget.printerId,
      ).select((p) => p.item?.printer.model),
    );
    final items = async.valueOrNull == null
        ? null
        : queueForPrinter(
            async.valueOrNull!,
            printerId: widget.printerId,
            model: model,
          );
    final seconds = items?.fold<int>(
      0,
      (sum, i) => sum + (i.printTimeSeconds ?? 0),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: ControllerHeaderCard(
                title: items == null
                    ? l10n.navQueue
                    : l10n.controllerQueueCount(items.length),
                fact: seconds == null || seconds == 0
                    ? null
                    : formatSeconds(l10n, seconds),
              ),
            ),
            const SizedBox(width: DashSpace.sm),
            ControllerHeaderButton(
              id: 'controller.queue.refresh',
              tooltip: l10n.pfmRefreshTooltip,
              icon: Icons.refresh_rounded,
              onPressed: async.isLoading
                  ? null
                  : ref.read(queueProvider.notifier).refresh,
            ),
          ],
        ),
        const SizedBox(height: DashSpace.md),
        Expanded(
          child: Container(
            decoration: t.cardBox,
            padding: const EdgeInsets.all(DashSpace.sm),
            child: switch ((items, async)) {
              (final list?, _) => _Grid(
                items: list,
                printerId: widget.printerId,
                refreshing: async.isLoading,
              ),
              (_, AsyncError(:final error)) => ControllerListFailure(
                error: error,
                retryId: 'controller.queue.retry',
                onRetry: ref.read(queueProvider.notifier).refresh,
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ),
      ],
    );
  }
}

class _Grid extends ConsumerWidget {
  const _Grid({
    required this.items,
    required this.printerId,
    required this.refreshing,
  });

  final List<QueueItem> items;
  final int printerId;
  final bool refreshing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (items.isEmpty) {
      return ControllerListMessage(
        icon: Icons.playlist_add_check_rounded,
        text: l10n.controllerQueueEmpty,
      );
    }
    return Column(
      children: [
        if (refreshing) const LinearProgressIndicator(),
        Expanded(
          child: GridView.builder(
            gridDelegate: controllerTileGrid,
            itemCount: items.length,
            itemBuilder: (context, i) => _QueueTile(
              item: items[i],
              place: i + 1,
              onTap: () => _open(context, ref, items[i], i + 1),
            ),
          ),
        ),
      ],
    );
  }

  /// The job's dialog, then what was chosen in it once it is gone. The queue
  /// is read again after the dialog: the job may have started or left meanwhile.
  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    QueueItem item,
    int place,
  ) async {
    final l10n = AppLocalizations.of(context);
    final scale = ControllerScale.of(context);
    final choice = await showControllerDetailDialog<ControllerQueueChoice>(
      context,
      (scale) => _QueueDialog(
        scale: scale,
        printerId: printerId,
        item: item,
        place: place,
      ),
    );
    if (choice == null || !context.mounted) return;
    // What the dialog offered held when it opened. The job may have started,
    // left, or been put on another printer since, and then Remove would stop a
    // running print and Start would start it somewhere else.
    final current = ref
        .read(queueProvider)
        .valueOrNull
        ?.where((i) => i.id == item.id)
        .firstOrNull;
    final model = ref
        .read(controllerPrinterProvider(printerId))
        .item
        ?.printer
        .model;
    if (current == null ||
        !_waiting(current) ||
        queueForPrinter(
          [current],
          printerId: printerId,
          model: model,
        ).isEmpty) {
      return;
    }
    switch (choice) {
      case ControllerQueueChoice.start:
        await startQueueItem(
          context,
          ref,
          current,
          l10n,
          onPrinter: printerId,
          dialogScale: scale,
        );
      case ControllerQueueChoice.remove:
        await removeFromQueue(
          context,
          ref.read(queueProvider.notifier),
          ScaffoldMessenger.of(context),
          l10n,
          item: current,
          removal: _removal(ref, current),
        );
    }
  }
}

/// A job that has not started: the only kind the dialog offers to act on.
bool _waiting(QueueItem item) =>
    item.statusKind == QueueItemStatusKind.pending ||
    item.statusKind == QueueItemStatusKind.scheduled;

/// Which route takes [item] out of the queue, as the queue screen picks it.
QueueRemoval _removal(WidgetRef ref, QueueItem item) {
  final printerId = item.printerId;
  return queueRemovalFor(
    item.statusKind,
    printerBusy:
        printerId != null &&
        ref.read(printerStatusesProvider)[printerId]?.isPrinting == true,
  );
}

class _QueueTile extends ConsumerWidget {
  const _QueueTile({
    required this.item,
    required this.place,
    required this.onTap,
  });

  final QueueItem item;

  /// Where the job stands in this printer's queue, from 1. Not the server's
  /// `position`, which numbers the whole queue and defaults to 1 everywhere.
  final int place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final (status, ink) = queueStatusLabel(l10n, t, item);
    final meta = [
      if (item.printTimeSeconds case final s?) formatSeconds(l10n, s),
      if (item.filamentUsedGrams case final g?) fmtGrams(g),
    ];
    return ControllerTileFrame(
      id: 'controller.queue.job',
      onTap: onTap,
      highlighted: item.statusKind == QueueItemStatusKind.printing,
      leading: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(DashSpace.md),
            child: QueueThumbnail(item: item, size: controllerThumbSize),
          ),
          Positioned(
            left: DashSpace.xs,
            top: DashSpace.xs,
            child: _Place(place),
          ),
        ],
      ),
      children: [
        Text(
          item.displayName,
          style: t.titleSm,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: DashSpace.xs),
        Row(
          children: [
            Flexible(
              child: ControllerChip(label: status, ink: ink),
            ),
            if (item.manualStart) ...[
              const SizedBox(width: DashSpace.xs),
              Flexible(
                child: ControllerChip(
                  label: queueStagedLabel(
                    l10n,
                    awaitingReview: ref.watch(awaitingReviewProvider),
                  ),
                  ink: t.warningInk,
                ),
              ),
            ],
            if (item.printerId == null) ...[
              const SizedBox(width: DashSpace.xs),
              Flexible(
                child: ControllerChip(
                  label: queueTargetLabel(l10n, item),
                  ink: t.accentBlue,
                ),
              ),
            ],
          ],
        ),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: DashSpace.xs),
          Text(
            meta.join(' · '),
            style: t.monoLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

class _Place extends StatelessWidget {
  const _Place(this.place);

  final int place;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DashSpace.xs),
      decoration: BoxDecoration(
        color: t.overlaySurface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(DashSpace.xs),
      ),
      child: Text('$place', style: t.monoLabel),
    );
  }
}

/// What a job's dialog closed with. Anything else closes with null.
enum ControllerQueueChoice { start, remove }

class _QueueDialog extends ConsumerWidget {
  const _QueueDialog({
    required this.scale,
    required this.printerId,
    required this.item,
    required this.place,
  });

  final double scale;
  final int printerId;
  final QueueItem item;
  final int place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final formats = DateTimeFormats.of(context);
    final printerKnown =
        ref.watch(controllerPrinterProvider(printerId).select((p) => p.item)) !=
        null;
    final waiting = _waiting(item);
    // The gate takes the job's own printer, not this one: an ownerless job for
    // any printer of a model is one an update-own user may not put a printer
    // on (the PATCH answers 403), so it is not theirs to start either.
    final mayStart = ref.watch(
      mayStartQueueItemProvider((
        createdById: item.createdById,
        printerId: item.printerId,
      )),
    );
    final awaitingReview = ref.watch(awaitingReviewProvider);
    final (status, ink) = queueStatusLabel(l10n, t, item);
    final startBlock = !printerKnown
        ? l10n.controllerPrinterGone
        : item.isCrossModel
        ? l10n.controllerQueueCrossModel
        : mayStart
        ? null
        : awaitingReview
        ? l10n.queueAwaitingReviewRefused
        : l10n.controllerQueueNoStart;
    return ControllerDetailDialog(
      scale: scale,
      closeId: 'controller.queue.dialog.close',
      thumbnail: QueueThumbnail(
        item: item,
        size: ControllerDetailDialog.thumbSize,
      ),
      title: item.displayName,
      facts: [
        ControllerFact(Icons.format_list_numbered_rounded, '#$place'),
        ControllerFact(Icons.circle, status, ink: ink),
        if (item.printerId == null)
          ControllerFact(
            Icons.print_outlined,
            queueTargetLabel(l10n, item),
            ink: t.accentBlue,
          ),
        if (item.printTimeSeconds case final s?)
          ControllerFact(Icons.schedule_rounded, formatSeconds(l10n, s)),
        if (item.filamentUsedGrams case final g?)
          ControllerFact(Icons.scale_outlined, fmtGrams(g)),
        if (item.scheduledTime case final at?)
          ControllerFact(Icons.event_outlined, formats.dateTime(at)),
        if (item.createdByUsername case final who?)
          ControllerFact(Icons.person_outline_rounded, who),
        if (item.waitingReason case final why? when why.isNotEmpty)
          ControllerFact(Icons.hourglass_empty_rounded, why),
      ],
      reason: waiting ? startBlock : null,
      // A job on the plate is stopped from Overview, where the print is.
      actions: waiting
          ? [
              ControllerDialogAction(
                id: 'controller.queue.dialog.remove',
                icon: Icons.delete_outline_rounded,
                label: l10n.queueRemove,
                tone: t.danger,
                ink: t.dangerInk,
                onPressed: () =>
                    Navigator.of(context).pop(ControllerQueueChoice.remove),
              ),
              ControllerDialogAction(
                id: 'controller.queue.dialog.start',
                icon: Icons.play_arrow_rounded,
                label: l10n.queueStart,
                tone: t.accentGreen,
                ink: t.accentGreenInk,
                onPressed: startBlock == null
                    ? () =>
                          Navigator.of(context).pop(ControllerQueueChoice.start)
                    : null,
              ),
            ]
          : const [],
    );
  }
}
