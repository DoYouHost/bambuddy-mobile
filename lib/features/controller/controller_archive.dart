import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/format/datetime_format.dart';
import '../../core/format/duration_format.dart';
import '../../core/models/archive.dart';
import '../../core/printers/gcode_compat.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../archive/archive_providers.dart';
import '../common/print_run_labels.dart';
import '../common/print_thumbnail.dart';
import '../queue/queue_drafts.dart';
import '../stats/stats_common.dart';
import 'controller_controls.dart';
import 'controller_detail_dialog.dart';
import 'controller_list_parts.dart';
import 'controller_print.dart';
import 'controller_providers.dart';

/// Rows a request asks for: the server's own default (`archives.py`,
/// `list_archives`), and enough to fill the grid several times over.
const controllerArchivePageSize = 50;

/// One printer's archive as far as it has been read, newest first.
class ControllerArchivePage {
  const ControllerArchivePage({
    required this.items,
    required this.fetched,
    required this.hasMore,
    this.loadingMore = false,
    this.moreFailed,
  });

  final List<Archive> items;

  /// Rows the server has handed over: the next page's offset. Not
  /// `items.length`, which a duplicate dropped from a page makes shorter.
  final int fetched;

  /// The last page was full, so there may be another.
  final bool hasMore;
  final bool loadingMore;

  /// Why the last next page did not come; the rows already read stay.
  final AppApiException? moreFailed;
}

/// [printerId]'s archive, read [controllerArchivePageSize] rows at a time with
/// the server's own printer filter. Read again on every visit to the view.
final controllerArchiveProvider = AsyncNotifierProvider.autoDispose
    .family<ControllerArchiveNotifier, ControllerArchivePage, int>(
      ControllerArchiveNotifier.new,
    );

class ControllerArchiveNotifier
    extends AutoDisposeFamilyAsyncNotifier<ControllerArchivePage, int> {
  /// Bumped by every build, refresh and dispose: an answer that comes back
  /// under another generation describes a listing no longer on screen. A flag
  /// would not do — a rebuild runs on this same instance after its dispose.
  int _generation = 0;

  @override
  Future<ControllerArchivePage> build(int printerId) async {
    ref.watch(serverProfileProvider);
    _generation++;
    ref.onDispose(() => _generation++);
    return _first();
  }

  Future<ControllerArchivePage> _first() async {
    final rows = await _page(0);
    return ControllerArchivePage(
      items: rows,
      fetched: rows.length,
      hasMore: rows.length == controllerArchivePageSize,
    );
  }

  Future<List<Archive>> _page(int offset) => ref
      .read(archiveRepositoryProvider)
      .list(printerId: arg, limit: controllerArchivePageSize, offset: offset);

  /// The next page, one at a time. A print that finished meanwhile moves every
  /// row down by one, so the new page can repeat the last row read: kept once.
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (state.isLoading ||
        current == null ||
        !current.hasMore ||
        current.loadingMore) {
      return;
    }
    final generation = _generation;
    state = AsyncData(
      ControllerArchivePage(
        items: current.items,
        fetched: current.fetched,
        hasMore: true,
        loadingMore: true,
      ),
    );
    try {
      final rows = await _page(current.fetched);
      if (generation != _generation) return;
      final seen = {for (final a in current.items) a.id};
      state = AsyncData(
        ControllerArchivePage(
          items: [
            ...current.items,
            for (final a in rows)
              if (seen.add(a.id)) a,
          ],
          fetched: current.fetched + rows.length,
          hasMore: rows.length == controllerArchivePageSize,
        ),
      );
    } on AppApiException catch (e) {
      if (generation != _generation) return;
      state = AsyncData(
        ControllerArchivePage(
          items: current.items,
          fetched: current.fetched,
          hasMore: true,
          moreFailed: e,
        ),
      );
    }
  }

  /// From the newest again.
  Future<void> refresh() async {
    final generation = ++_generation;
    state = const AsyncLoading<ControllerArchivePage>().copyWithPrevious(state);
    final next = await AsyncValue.guard(_first);
    if (generation == _generation) state = next;
  }
}

/// The Archive view of the Prints tab: what this printer printed, newest
/// first, and a print of it again ([docs/single-printer-controller.md] §8).
class ControllerArchive extends ConsumerWidget {
  const ControllerArchive({super.key, required this.printerId});

  final int printerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final provider = controllerArchiveProvider(printerId);
    final async = ref.watch(provider);
    final page = async.valueOrNull;
    final notifier = ref.read(provider.notifier);
    return RefreshWhenShown(
      onRefresh: notifier.refresh,
      // The server announces an archive it changed, not one it added.
      announced: ref.watch(archiveChangedProvider),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: ControllerHeaderCard(title: l10n.navArchive)),
              const SizedBox(width: DashSpace.sm),
              ControllerHeaderButton(
                id: 'controller.archive.refresh',
                tooltip: l10n.pfmRefreshTooltip,
                icon: Icons.refresh_rounded,
                onPressed: async.isLoading ? null : notifier.refresh,
              ),
            ],
          ),
          const SizedBox(height: DashSpace.md),
          Expanded(
            child: Container(
              decoration: t.cardBox,
              padding: const EdgeInsets.all(DashSpace.sm),
              child: switch ((page, async)) {
                (_, AsyncError(:final error)) => ControllerListFailure(
                  error: error,
                  retryId: 'controller.archive.retry',
                  onRetry: notifier.refresh,
                ),
                (final p?, _) => _Grid(
                  page: p,
                  printerId: printerId,
                  refreshing: async.isLoading,
                  onMore: notifier.loadMore,
                ),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Grid extends ConsumerWidget {
  const _Grid({
    required this.page,
    required this.printerId,
    required this.refreshing,
    required this.onMore,
  });

  final ControllerArchivePage page;
  final int printerId;
  final bool refreshing;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final model = ref.watch(
      controllerPrinterProvider(printerId).select((p) => p.item?.printer.model),
    );
    if (page.items.isEmpty) {
      return ControllerListMessage(
        icon: Icons.history_rounded,
        text: l10n.controllerArchiveEmpty,
      );
    }
    return Column(
      children: [
        if (refreshing) const LinearProgressIndicator(),
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverGrid.builder(
                gridDelegate: controllerTileGrid(context),
                itemCount: page.items.length,
                // The grid's context, not the tile's: a refresh while the
                // dialog is open may take the tile away.
                itemBuilder: (_, i) {
                  // The grid builds a tile only as it comes near the screen,
                  // so building one of the last two rows is the end coming
                  // near. The notifier asks one page at a time; after a
                  // failure the footer's Retry does.
                  if (page.hasMore &&
                      page.moreFailed == null &&
                      i >= page.items.length - controllerGridColumns * 2) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => onMore(),
                    );
                  }
                  return _ArchiveTile(
                    archive: page.items[i],
                    printerModel: model,
                    onTap: () => _open(context, ref, page.items[i]),
                  );
                },
              ),
              if (page.hasMore)
                SliverToBoxAdapter(
                  child: _More(page: page, onMore: onMore),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// The print's dialog, then the print screen once it is gone, as the Files
  /// view does. The printer is read after the dialog: the roster may have lost
  /// it meanwhile.
  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    Archive archive,
  ) async {
    final again = await showControllerDetailDialog<bool>(
      context,
      (scale) =>
          _ArchiveDialog(scale: scale, printerId: printerId, archive: archive),
    );
    if (again != true || !context.mounted) return;
    final printer = ref
        .read(controllerPrinterProvider(printerId))
        .item
        ?.printer;
    if (printer == null) return;
    await openControllerPrint(
      context,
      printer: printer,
      draft: archiveQueueDraft(archive),
    );
  }
}

/// The end of the grid while older prints exist: the next page on its way, or
/// the failure of the last one with a retry.
class _More extends StatelessWidget {
  const _More({required this.page, required this.onMore});

  final ControllerArchivePage page;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: DashSpace.sm),
      child: SizedBox(
        height: controllerButtonHeight,
        child: page.moreFailed == null
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox.square(
                    dimension: DashSpace.xl,
                    child: CircularProgressIndicator(),
                  ),
                  const SizedBox(width: DashSpace.md),
                  Text(l10n.controllerArchiveLoadingMore, style: t.bodySoft),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(l10n.connectFailed, style: t.bodySoft),
                  const SizedBox(width: DashSpace.md),
                  ControllerDialogAction(
                    id: 'controller.archive.more_retry',
                    icon: Icons.refresh_rounded,
                    label: l10n.retry,
                    onPressed: onMore,
                  ),
                ],
              ),
      ),
    );
  }
}

class _ArchiveTile extends StatelessWidget {
  const _ArchiveTile({
    required this.archive,
    required this.printerModel,
    required this.onTap,
  });

  final Archive archive;
  final String? printerModel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final (_, ink) = printRunTone(t, archive.status);
    final seconds = archive.shownTimeSeconds;
    final grams = archive.filamentUsedGrams;
    final meta = [
      if (archive.createdAt case final at?)
        DateTimeFormats.of(context).date(at),
      if (seconds != null && seconds > 0) formatSeconds(l10n, seconds),
      if (grams != null && grams > 0) fmtGrams(grams),
    ];
    return ControllerTileFrame(
      id: 'controller.archive.print',
      onTap: onTap,
      // Quieter where it cannot be printed again here, as a file's tile is.
      dimmed:
          !archive.isSliced ||
          !isGcodeCompatible(archive.slicedForModel, printerModel),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(DashSpace.md),
        child: PrintThumbnail(archiveId: archive.id, size: controllerThumbSize),
      ),
      children: [
        Text(
          archive.displayName,
          style: t.titleSm,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: DashSpace.xs),
        Row(
          children: [
            ControllerChip(
              label: printRunStatusLabel(l10n, archive.status),
              ink: ink,
            ),
            if (meta.isNotEmpty) ...[
              const SizedBox(width: DashSpace.sm),
              Flexible(
                child: Text(
                  meta.join(' · '),
                  style: t.monoLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// A print's dialog: what it was, and Print again. Closes with true when that
/// was chosen.
class _ArchiveDialog extends ConsumerWidget {
  const _ArchiveDialog({
    required this.scale,
    required this.printerId,
    required this.archive,
  });

  final double scale;
  final int printerId;
  final Archive archive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final printer = ref.watch(
      controllerPrinterProvider(printerId).select((p) => p.item?.printer),
    );
    final block = controllerPrintBlock(
      printerKnown: printer != null,
      refused: ref.watch(archiveReprintBlockProvider(archive.createdById)),
      printable: archive.isSliced,
      slicedForModel: archive.slicedForModel,
      printerModel: printer?.model,
    );
    final (fill, ink) = printRunTone(t, archive.status);
    final wrongModel = block == ControllerPrintBlock.wrongModel;
    final seconds = archive.shownTimeSeconds;
    final grams = archive.filamentUsedGrams;
    return ControllerDetailDialog(
      scale: scale,
      closeId: 'controller.archive.dialog.close',
      thumbnail: PrintThumbnail(
        archiveId: archive.id,
        size: ControllerDetailDialog.thumbSize,
      ),
      title: archive.displayName,
      facts: [
        ControllerFact(
          Icons.flag_outlined,
          printRunStatusLabel(l10n, archive.status),
          ink: ink,
          fill: fill,
        ),
        if (archive.createdAt case final at?)
          ControllerFact(
            Icons.event_outlined,
            DateTimeFormats.of(context).dateTime(at),
          ),
        if (seconds != null && seconds > 0)
          ControllerFact(Icons.schedule_rounded, formatSeconds(l10n, seconds)),
        if (grams != null && grams > 0)
          ControllerFact(Icons.scale_outlined, fmtGrams(grams)),
        if (archive.plateId case final plate?)
          ControllerFact(
            Icons.layers_outlined,
            l10n.queueEditPlateSelected(plate),
          ),
        if (archive.slicedForModel case final model?)
          ControllerFact(
            Icons.print_outlined,
            model,
            ink: wrongModel ? t.warningInk : null,
            fill: wrongModel ? t.warning : null,
          ),
      ],
      reason: block?.reason(l10n, slicedForModel: archive.slicedForModel),
      actions: [
        ControllerDialogAction(
          id: 'controller.archive.dialog.print',
          icon: Icons.print_rounded,
          label: l10n.archiveReprint,
          tone: t.accentGreen,
          ink: t.accentGreenInk,
          onPressed: block == null
              ? () => Navigator.of(context).pop(true)
              : null,
        ),
      ],
    );
  }
}
