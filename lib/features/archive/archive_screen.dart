import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/format/datetime_format.dart';
import '../../core/format/text_measure.dart';
import '../../core/models/archive.dart';
import '../../core/models/archive_purge.dart';
import '../../core/models/no_3mf_warning.dart';
import '../../core/models/project.dart';
import '../../core/models/queue_item.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import 'archive_media_sheet.dart';
import '../common/api_failure_snack.dart';
import '../gcode/gcode_viewer_route.dart';
import '../common/dash_async.dart';
import '../common/dash_search_field.dart';
import '../common/dash_sheet.dart';
import '../common/dash_snack.dart';
import '../common/filter_controls.dart';
import '../common/sheet_surface.dart';
import '../common/sliver_search_bar.dart';
import '../common/format_bytes.dart';
import '../common/print_thumbnail.dart';
import '../common/state_views.dart';
import '../projects/project_common.dart';
import '../queue/queue_edit_screen.dart';
import '../slicer/slice_providers.dart';
import '../slicer/slice_screen.dart';
import 'archive_filament_edit.dart';
import 'archive_providers.dart';
import '../common/hex_color.dart';

/// Archive screen for prints (M5): browsing with search and thumbnails,
/// reprint and add to queue (both require printer selection).
class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({super.key});

  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends ConsumerState<ArchiveScreen> {
  Timer? _debounce;

  /// Purge-stats choice from the delete dialog, carried from `confirmDismiss`
  /// to `onDismissed` (only one swipe is in flight at a time).
  bool _pendingPurge = false;

  /// Archive ids picked in multi-select mode. Non-empty → selection mode.
  final Set<int> _selected = {};

  bool get _selectionMode => _selected.isNotEmpty;

  void _toggleSelect(int id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  void _clearSelection() => setState(_selected.clear);

  /// Selects every archive currently passing the filters, not the whole list.
  void _selectAllVisible() {
    final all = ref.read(archiveProvider).valueOrNull ?? const [];
    final filters = ref.read(archiveFiltersProvider);
    final visible = applyArchiveFilters(all, filters);
    setState(() => _selected.addAll(visible.map((a) => a.id)));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Search is a client-side filter; debounce only to avoid re-filtering the
  /// whole list on every keystroke.
  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      final notifier = ref.read(archiveFiltersProvider.notifier);
      notifier.state = notifier.state.copyWith(query: q.trim());
    });
  }

  void _openFilters() {
    final all = ref.read(archiveProvider).valueOrNull ?? const [];
    dashSurfaceSheet<void>(
      context,
      builder: (_) => _ArchiveFilterSheet(archives: all),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(archiveProvider);
    final filters = ref.watch(archiveFiltersProvider);

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: _selectionMode
            ? dashAppBar(
                context,
                title: l10n.archiveSelectedCount(_selected.length),
                leading: logTag(
                  'archive.selection_clear',
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: l10n.cancel,
                    onPressed: _clearSelection,
                  ),
                ),
                actions: [
                  logTag(
                    'archive.select_all',
                    IconButton(
                      icon: const Icon(Icons.select_all),
                      tooltip: l10n.archiveSelectAll,
                      onPressed: _selectAllVisible,
                    ),
                  ),
                  logTag(
                    'archive.add_to_project',
                    IconButton(
                      icon: const Icon(Icons.folder_special_outlined),
                      tooltip: l10n.archiveAddToProject,
                      onPressed: _addSelectedToProject,
                    ),
                  ),
                  logTag(
                    'archive.delete_selected',
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: l10n.archiveDelete,
                      onPressed: _deleteSelected,
                    ),
                  ),
                ],
              )
            : dashAppBar(
                context,
                title: l10n.navArchive,
                actions: [
                  logTag(
                    'archive.menu',
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'purge') _purgeOlder();
                        if (v == 'print_log') context.push('/print-log');
                      },
                      // Tag on the child: a wrapped `PopupMenuItem` is no
                      // longer a `PopupMenuEntry`.
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'print_log',
                          child: logTag(
                            'archive.menu.print_log',
                            Text(l10n.printLogTitle),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'purge',
                          child: logTag(
                            'archive.menu.purge',
                            Text(l10n.archivePurgeOlder),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        body: dashAsync(
          context,
          async,
          onRetry: () => ref.read(archiveProvider.notifier).refresh(),
          data: (all) {
            final items = applyArchiveFilters(all, filters);
            return RefreshIndicator(
              onRefresh: () => ref.read(archiveProvider.notifier).refresh(),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  DashSliverSearchBar(
                    child: SizedBox(
                      height: 48,
                      child: Row(
                        children: [
                          Expanded(
                            child: DashSearchField(
                              id: 'archive.search',
                              hintText: l10n.archiveSearchHint,
                              onChanged: _onSearchChanged,
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilterButton(
                            count: filters.activeCount,
                            tooltip: l10n.archiveFilters,
                            id: 'archive.filters',
                            onTap: _openFilters,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Above the list, below the search bar — and never while
                  // multi-selecting, where the screen is a picker and every row
                  // pushed down is a row the user has to hunt for again.
                  if (!_selectionMode)
                    const SliverToBoxAdapter(child: _No3mfBanner()),
                  if (all.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyStateView(
                        message: l10n.archiveEmpty,
                        icon: Icons.inventory_2_outlined,
                      ),
                    )
                  else if (items.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyStateView(
                        message: l10n.archiveNoMatches,
                        icon: Icons.search_off,
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      sliver: SliverList.builder(
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final archive = items[i];
                          final card = _ArchiveCard(
                            archive: archive,
                            selected: _selected.contains(archive.id),
                            onTap: () => _selectionMode
                                ? _toggleSelect(archive.id)
                                : _openSheet(archive),
                            onLongPress: () => _toggleSelect(archive.id),
                            // No favorite toggle while multi-selecting — taps
                            // there belong to the selection gesture.
                            onToggleFavorite: _selectionMode
                                ? null
                                : () => _toggleFavorite(archive),
                          );
                          // No swipe-to-delete while multi-selecting.
                          return _selectionMode
                              ? card
                              : _deletable(archive, card);
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

  void _openSheet(Archive archive) {
    dashSheet<void>(
      context,
      builder: (_) => _ArchiveSheet(
        archive: archive,
        onReprint: () => _reprint(archive),
        onAddToQueue: () => _addToQueue(archive),
        onPreviewGcode: () => _previewGcode(archive),
        onMedia: () => _openMedia(archive),
        onSlice: () => _slice(archive),
        onDelete: () => _deleteFromSheet(archive),
      ),
    );
  }

  /// Toggle an archive's favorite flag (optimistic; the list live-updates).
  /// Only surfaces a message on failure — success is obvious from the star.
  Future<void> _toggleFavorite(Archive archive) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref
        .read(archiveProvider.notifier)
        .toggleFavorite(archive.id);
    if (!ok) {
      messenger.snack(l10n.archiveFavoriteFailed);
    }
  }

  /// Swipe-to-delete wrapper. Confirmation (with the purge-stats choice) runs
  /// in `confirmDismiss`; the actual delete runs in `onDismissed` so the
  /// notifier's optimistic removal stays in sync with the dismiss animation.
  Widget _deletable(Archive archive, Widget child) {
    final t = DashTokens.of(context);
    return Dismissible(
      key: ValueKey('archive_dismiss_${archive.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: t.danger.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: t.danger.withValues(alpha: 0.4)),
        ),
        child: Icon(Icons.delete_outline, color: t.danger),
      ),
      confirmDismiss: (_) async {
        final purge = await _askDelete(archive);
        if (purge == null) return false;
        _pendingPurge = purge;
        return true;
      },
      onDismissed: (_) => _deleteArchive(archive, _pendingPurge),
      child: child,
    ).tagged('archive.swipe_delete');
  }

  /// Slice from the bottom sheet: close it, open the slice modal.
  Future<void> _slice(Archive archive) async {
    Navigator.pop(context);
    await showSliceScreen(
      context,
      SliceTarget.archive(archive.id, archive.displayName),
    );
  }

  /// Delete from the bottom sheet: close it, confirm, then delete.
  Future<void> _deleteFromSheet(Archive archive) async {
    Navigator.pop(context);
    final purge = await _askDelete(archive);
    if (purge == null || !mounted) return;
    await _deleteArchive(archive, purge);
  }

  /// Confirmation dialog. Returns `null` on cancel, otherwise whether the print
  /// should also be purged from statistics (`purge_stats`).
  Future<bool?> _askDelete(Archive archive) {
    final l10n = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (_) => _DeleteArchiveDialog(
        title: l10n.archiveDeleteTitle,
        message: l10n.archiveDeleteBody(archive.displayName),
      ),
    );
  }

  Future<void> _deleteArchive(Archive archive, bool purgeStats) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref
        .read(archiveProvider.notifier)
        .delete(archive.id, purgeStats: purgeStats);
    messenger.snack(ok ? l10n.archiveDeleted : l10n.archiveDeleteFailed);
  }

  /// Delete all selected prints after one confirmation (with purge-stats
  /// choice). Clears selection regardless of per-item outcome.
  Future<void> _deleteSelected() async {
    final l10n = AppLocalizations.of(context);
    final count = _selected.length;
    final purge = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteArchiveDialog(
        title: l10n.archiveDeleteSelectedTitle(count),
        message: l10n.archiveDeleteSelectedBody,
      ),
    );
    if (purge == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final ids = Set<int>.from(_selected);
    final res = await ref
        .read(archiveProvider.notifier)
        .deleteMany(ids, purgeStats: purge);
    if (!mounted) return;
    _clearSelection();
    messenger.snack(res.failed == 0
              ? l10n.archiveDeletedCount(res.ok)
              : l10n.archiveDeleteSomeFailed(res.ok, res.failed));
  }

  /// Add the selected prints to a project: pick a project from a sheet, then
  /// `POST /projects/{id}/add-archives`. Clears selection on success.
  Future<void> _addSelectedToProject() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final List<ProjectListResponse> projects;
    try {
      projects = await ref.read(projectsRepositoryProvider).list();
    } on AppApiException catch (e) {
      showApiFailure(messenger, e, l10n, action: 'archive.add_to_project');
      return;
    }
    if (!mounted) return;
    if (projects.isEmpty) {
      messenger.snack(l10n.projectsEmpty);
      return;
    }

    final projectId = await dashSheet<int>(
      context,
      scrollControlled: false,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.projectPickTitle,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in projects)
                    ListTile(
                      leading: ProjectColorDot(color: p.color),
                      title: Text(p.name),
                      subtitle: Text(projectStatusLabel(l10n, p.status)),
                      onTap: () => Navigator.pop(ctx, p.id),
                    ).tagged('archive.project_option'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (projectId == null || !mounted) return;

    final ids = _selected.toList();
    try {
      await ref.read(projectsRepositoryProvider).addArchives(projectId, ids);
      if (!mounted) return;
      _clearSelection();
      messenger.snack(l10n.projectArchivesAdded);
    } on AppApiException catch (e) {
      showApiFailure(messenger, e, l10n, action: 'archive.add_to_project');
    }
  }

  /// Purge prints older than a chosen threshold: pick days + purge-stats,
  /// see a live preview, confirm → `POST /archives/purge`, then refresh.
  Future<void> _purgeOlder() async {
    final result = await showDialog<({int days, bool purgeStats})>(
      context: context,
      builder: (_) => const _PurgeOlderDialog(),
    );
    if (result == null || !mounted) return;

    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final deleted = await ref
          .read(archiveRepositoryProvider)
          .purge(olderThanDays: result.days, purgeStats: result.purgeStats);
      await ref.read(archiveProvider.notifier).refresh();
      messenger.snack(l10n.archivePurgeResult(deleted));
    } on AppApiException catch (e) {
      showApiFailure(messenger, e, l10n, action: 'archive.menu.purge');
    }
  }

  /// G-code preview: closes sheet and opens full-screen 3D viewer.
  /// Opens the preview on the plate this print ran, not on whichever plate the
  /// server would pick for a multi-plate file.
  void _previewGcode(Archive archive) {
    Navigator.pop(context);
    context.push(gcodeViewerRoute(
      archiveId: archive.id,
      plate: archive.plateId,
      title: archive.displayName,
    ));
  }

  /// Timelapse: closes the sheet and opens the full-screen player.
  void _openTimelapse(Archive archive) {
    Navigator.pop(context);
    final name = Uri.encodeQueryComponent(archive.displayName);
    context.push('/timelapse?archive=${archive.id}&name=$name');
  }

  /// Media: swaps this sheet for the one that lists everything the print has,
  /// on the server and on the printer.
  ///
  /// The printer search takes as long as five FTP listings, so it happens in
  /// the sheet it belongs to rather than behind the button that opens it — a
  /// tap that does nothing visible for half a minute reads as one that did
  /// nothing. The two viewers are still opened from here: `_openTimelapse` and
  /// `_openPhotos` pop whatever sheet is on top, which is now the media one.
  void _openMedia(Archive archive) {
    Navigator.pop(context);
    openArchiveMediaSheet(
      context,
      archive,
      onTimelapse: () => _openTimelapse(archive),
      onPhotos: () => _openPhotos(archive),
    );
  }

  /// Photos: closes the sheet and opens the full-screen viewer.
  void _openPhotos(Archive archive) {
    Navigator.pop(context);
    final name = Uri.encodeQueryComponent(archive.displayName);
    context.push('/archive/photos?archive=${archive.id}&name=$name');
  }

  /// Reprint: printer selection → confirmation → enqueue at top of the
  /// printer's queue (the scheduler starts it next). The direct `/reprint`
  /// endpoint was removed server-side; a reprint is now a top-priority queue
  /// item. Initiates a physical print, so always behind a confirmation dialog.
  /// Reprint: the print form, opened on ASAP so it goes ahead of the queue —
  /// the intent behind "reprint" is "print this one next".
  Future<void> _reprint(Archive archive) async {
    Navigator.pop(context);
    await openQueueCreate(
      context,
      draft: _draftFrom(archive),
      schedule: QueueScheduleType.asap,
    );
  }

  /// Add to queue: the same form, opened on Queue with manual start required.
  /// Configuring the job precedes its creation, so the scheduler can't take it
  /// mid-setup, and the start stays the user's decision.
  Future<void> _addToQueue(Archive archive) async {
    Navigator.pop(context);
    await openQueueCreate(
      context,
      draft: _draftFrom(archive, manualStart: true),
      schedule: QueueScheduleType.queue,
    );
  }

  /// The archive's own printer is a starting point, not a decision — the form
  /// lists every printer and the user can switch before anything is created.
  QueueItem _draftFrom(Archive archive, {bool manualStart = false}) =>
      QueueItem.draft(
        archiveId: archive.id,
        name: archive.displayName,
        thumbnail: archive.thumbnailPath,
        printerId: archive.printerId,
        filamentType: archive.filamentType,
        filamentColor: archive.filamentColor,
        slicedForModel: archive.slicedForModel,
        // The plate this print ran on, so a reprint runs the same one. Null on
        // a single-plate file and on servers that do not report it, which is
        // what the form and the server both read as plate 1.
        plateId: archive.plateId,
        manualStart: manualStart,
      );
}

/// "These prints archived without their 3MF" — and, since #2780, *why*.
///
/// Three causes with three different fixes, and the original single wording was
/// wrong for two of them: it sent H2-series and P2S owners to switch on a slicer
/// setting that was already on, and blamed the slicer when the real answer was
/// an empty card slot. An older server sends no reason at all, which is the
/// original case and keeps the original text.
///
/// Absent unless the server says there is something to say. Dismissal is
/// one-shot and permanent, as on the web: fixing the cause stops new fallbacks,
/// so there is nothing to come back to.
class _No3mfBanner extends ConsumerWidget {
  const _No3mfBanner();

  /// Where the wiki explains this cause, or null when there is nothing to link —
  /// "put a card in" is the whole fix for an empty slot.
  static String? _docsUrl(No3mfReason reason) => switch (reason) {
        No3mfReason.internalStorage =>
          'https://wiki.bambuddy.cool/reference/troubleshooting/#archive-card-has-only-a-name',
        No3mfReason.noExternalStorage => null,
        No3mfReason.slicerSetting =>
          'https://wiki.bambuddy.cool/getting-started/#step-4-enable-store-sent-files-on-external-storage',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Dismissal is read here as well as in the provider: the provider skips the
    // request on later app runs, but within this one it would keep serving the
    // answer it already has while it recomputes, and the banner has to go the
    // moment the X is tapped.
    if (ref.watch(no3mfDismissedProvider)) return const SizedBox.shrink();
    final warning = ref.watch(no3mfWarningProvider).valueOrNull;
    if (warning == null || !warning.hasFallback) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final reason = warning.reason;
    final (title, body) = switch (reason) {
      No3mfReason.internalStorage => (
          l10n.archiveNo3mfTitleInternal,
          l10n.archiveNo3mfBodyInternal,
        ),
      No3mfReason.noExternalStorage => (
          l10n.archiveNo3mfTitleNoStorage,
          l10n.archiveNo3mfBodyNoStorage,
        ),
      No3mfReason.slicerSetting => (
          l10n.archiveNo3mfTitle,
          l10n.archiveNo3mfBody,
        ),
    };
    final docs = _docsUrl(reason);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(
          color: t.accentOrange.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.accentOrange.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, size: 20, color: t.accentOrangeInk),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.bodyStrong),
                  const SizedBox(height: 4),
                  Text(body, style: t.labelSoft),
                  if (docs != null) ...[
                    const SizedBox(height: 6),
                    logTag(
                      'archive.no3mf_docs',
                      TextButton.icon(
                        onPressed: () => launchUrl(
                          Uri.parse(docs),
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.open_in_new, size: 14),
                        label: Text(
                          reason == No3mfReason.internalStorage
                              ? l10n.archiveNo3mfDocsWhy
                              : l10n.archiveNo3mfDocs,
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          visualDensity: VisualDensity.compact,
                          foregroundColor: t.accentOrangeInk,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            logTag(
              'archive.no3mf_dismiss',
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: l10n.archiveNo3mfDismiss,
                color: t.textTertiary,
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    ref.read(no3mfDismissedProvider.notifier).dismiss(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArchiveCard extends StatelessWidget {
  const _ArchiveCard({
    required this.archive,
    required this.onTap,
    this.onLongPress,
    this.onToggleFavorite,
    this.selected = false,
  });

  final Archive archive;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Tapping the star toggles favorite. Null hides the toggle (selection mode),
  /// falling back to a static star shown only when already a favorite.
  final VoidCallback? onToggleFavorite;

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final meta = <String>[
      // Only a run that printed a chosen plate of a multi-plate file carries
      // one, which is exactly when the name alone cannot tell two rows apart.
      //
      // Guarded on the value, not just on null: plates are numbered from 1
      // (`Metadata/plate_1.gcode` upward) and the server puts no lower bound on
      // the column, while 0 is what the slicer's own API means by "every plate".
      // Whatever wrote a 0 here, it did not print plate zero.
      if ((archive.plateId ?? 0) > 0)
        AppLocalizations.of(context).archivePlate(archive.plateId!),
      if (archive.filamentType != null) archive.filamentType!,
      if (archive.filamentUsedGrams != null)
        '${archive.filamentUsedGrams!.toStringAsFixed(0)} g',
      if (archive.createdAt != null)
        DateTimeFormats.of(context).date(archive.createdAt!),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: logTag(
          'archive.card',
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            onLongPress: onLongPress,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: selected
                    ? t.accentGreen.withValues(alpha: 0.14)
                    : t.subCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected
                      ? t.accentGreen.withValues(alpha: 0.5)
                      : t.subCardBorder,
                ),
              ),
              child: Row(
                children: [
                  selected
                      ? Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: t.accentGreen.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(Icons.check, color: t.accentGreenInk),
                        )
                      : Stack(
                          clipBehavior: Clip.none,
                          children: [
                            PrintThumbnail(archiveId: archive.id, size: 52),
                            Positioned(
                              right: -4,
                              bottom: -4,
                              child: _MediaBadges(archive: archive),
                            ),
                          ],
                        ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          archive.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleSm,
                        ),
                        if (meta.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            meta.join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.monoLabel,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (onToggleFavorite != null)
                    logTag(
                      'archive.favorite',
                      IconButton(
                        icon: Icon(
                          archive.isFavorite ? Icons.star : Icons.star_border,
                          size: 20,
                          color: archive.isFavorite
                              ? t.accentOrangeInk
                              : t.textTertiary,
                        ),
                        tooltip: archive.isFavorite
                            ? AppLocalizations.of(context).archiveUnfavorite
                            : AppLocalizations.of(context).archiveFavorite,
                        visualDensity: VisualDensity.compact,
                        onPressed: onToggleFavorite,
                      ),
                    )
                  else if (archive.isFavorite) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.star, size: 18, color: t.accentOrangeInk),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

}

/// Corner markers on a card's thumbnail for the media a print carries beyond
/// the model itself — a recorded timelapse, photos of the result. The point is
/// that the list answers "is there a video / a photo of this one?" without
/// opening every print, the way bambuddy's web cards do.
class _MediaBadges extends StatelessWidget {
  const _MediaBadges({required this.archive});

  final Archive archive;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final badges = <Widget>[
      if (archive.hasPhotos)
        _badge(
          Icons.photo_camera,
          t.accentBlue,
          l10n.archiveHasPhotos(archive.photos.length),
        ),
      if (archive.hasTimelapse)
        // `accentGreenInk`, not the vivid `accentGreen`: a 12 px mark that says
        // "there is a video of this one" is a meaningful control, and the vivid
        // swatch reads 2.1:1 on the pale card — under the 3:1 such a mark has
        // to clear. The blue beside it already does at 3.7:1.
        _badge(Icons.movie, t.accentGreenInk, l10n.archiveHasTimelapse),
    ];
    if (badges.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      decoration: BoxDecoration(
        color: t.subCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.subCardBorder),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: badges),
    );
  }

  Widget _badge(IconData icon, Color color, String label) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 1),
    child: Semantics(label: label, child: Icon(icon, size: 12, color: color)),
  );
}

class _ArchiveSheet extends StatelessWidget {
  const _ArchiveSheet({
    required this.archive,
    required this.onReprint,
    required this.onAddToQueue,
    required this.onPreviewGcode,
    required this.onMedia,
    required this.onSlice,
    required this.onDelete,
  });

  final Archive archive;
  final VoidCallback onReprint;
  final VoidCallback onAddToQueue;
  final VoidCallback onPreviewGcode;
  final VoidCallback onMedia;
  final VoidCallback onSlice;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return logTag(
      'sheet.archive_detail',
      SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PrintThumbnail(archiveId: archive.id, size: 72),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            archive.displayName,
                            style: theme.textTheme.titleMedium,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (archive.designer != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                archive.designer!,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          // Which plate ran. Only for a file that had a choice:
                          // on a single-plate print the server sends nothing,
                          // and "plate 1" would be noise on every card.
                          if (archive.plateId != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                l10n.archivePlateDetail(archive.plateId!),
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _SheetPrimaryActions(
                  onAddToQueue: onAddToQueue,
                  onReprint: onReprint,
                ),
                const SizedBox(height: 8),
                ArchiveFilamentRow(archive: archive),
                SizedBox(
                  width: double.infinity,
                  child: logTag(
                    'archive.preview_gcode',
                    OutlinedButton.icon(
                      icon: const Icon(Icons.view_in_ar_outlined),
                      label: Text(l10n.gcodeViewerOpen),
                      onPressed: onPreviewGcode,
                    ),
                  ),
                ),
                _ArchiveMediaButton(archive: archive, onMedia: onMedia),
                const SizedBox(height: 8),
                _SliceArchiveButton(archive: archive, onSlice: onSlice),
                SizedBox(
                  width: double.infinity,
                  child: logTag(
                    'archive.delete',
                    OutlinedButton.icon(
                      icon: const Icon(Icons.delete_outline),
                      label: Text(l10n.archiveDelete),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                      onPressed: onDelete,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      )
    );
  }
}

/// The sheet's two primary actions, side by side — but only while both labels
/// fit on one line. A wrapped label grows just its own button, leaving the pair
/// mismatched and taller than the full-width buttons below it, so on narrow
/// screens they stack full-width instead (which also unwraps the labels).
///
/// Whether a label fits depends on the locale, the user's text scale and the
/// button padding this app's theme sets, so the width each button needs for a
/// single-line label is measured from that resolved style rather than guessed
/// from a breakpoint.
class _SheetPrimaryActions extends StatelessWidget {
  const _SheetPrimaryActions({
    required this.onAddToQueue,
    required this.onReprint,
  });

  final VoidCallback onAddToQueue;
  final VoidCallback onReprint;

  /// Icon box and icon-to-label gap of a Material `*.icon` button — the only
  /// parts not exposed through [ButtonStyle].
  static const double _iconWidth = 18;
  static const double _iconGap = 8;

  /// A label has to fit with room to spare, not by a hair — measurement and
  /// rendering can round apart. Borderline pairs stack, which still looks
  /// right; a wrapped one does not.
  static const double _slack = 10;

  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final addToQueue = logTag(
      'archive.add_to_queue',
      OutlinedButton.icon(
        icon: const Icon(Icons.playlist_add),
        label: Text(l10n.archiveAddToQueue),
        onPressed: onAddToQueue,
      ),
    );
    final reprint = logTag(
      'archive.reprint',
      FilledButton.icon(
        icon: const Icon(Icons.print),
        label: Text(l10n.archiveReprint),
        onPressed: onReprint,
      ),
    );
    final widthNeeded = [
      _singleLineWidth(
        context,
        l10n.archiveReprint,
        FilledButtonTheme.of(context).style,
      ),
      _singleLineWidth(
        context,
        l10n.archiveAddToQueue,
        OutlinedButtonTheme.of(context).style,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final half = (constraints.maxWidth - _gap) / 2;
        final fitsSideBySide = widthNeeded.every((w) => w + _slack <= half);
        if (fitsSideBySide) {
          return Row(
            children: [
              Expanded(child: reprint),
              const SizedBox(width: _gap),
              Expanded(child: addToQueue),
            ],
          );
        }
        return Column(
          children: [
            SizedBox(width: double.infinity, child: reprint),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: addToQueue),
          ],
        );
      },
    );
  }

  /// Width the button needs to keep [label] on one line, taking the text style
  /// and padding from [style] — the very [ButtonStyle] the button will render
  /// with, so a theme tweak can't silently invalidate this.
  double _singleLineWidth(
    BuildContext context,
    String label,
    ButtonStyle? style,
  ) {
    const states = <WidgetState>{};
    final theme = Theme.of(context);
    final textStyle = (theme.textTheme.labelLarge ?? const TextStyle()).merge(
      style?.textStyle?.resolve(states),
    );
    final padding = style?.padding?.resolve(states)?.horizontal ?? 0;
    return padding +
        _iconWidth +
        _iconGap +
        textWidth(context, label, textStyle);
  }
}

/// Slice button shown only when the slicer sidecar is enabled AND this archive
/// is actually re-sliceable (retains a source/model — plain gcode.3mf prints
/// are not). Renders nothing otherwise, so the sheet is unchanged for the
/// common case.
class _SliceArchiveButton extends ConsumerWidget {
  const _SliceArchiveButton({required this.archive, required this.onSlice});

  final Archive archive;
  final VoidCallback onSlice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(slicerEnabledProvider).valueOrNull ?? false;
    if (!enabled) return const SizedBox.shrink();
    final caps = ref.watch(archiveCapabilitiesProvider(archive.id)).valueOrNull;
    if (caps == null || !caps.sliceable) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.layers_outlined),
          label: Text(AppLocalizations.of(context).sliceAction),
          onPressed: onSlice,
        ),
      ),
    );
  }
}

/// The one entry to everything the print has: the timelapse and photos the
/// server keeps, and whatever is still on the printer.
///
/// Absent for a print with none of the three. The printer half also needs a
/// server that has the search route — on an older one the sheet is still the
/// way to the timelapse and the photos, it simply has nothing to look for.
class _ArchiveMediaButton extends ConsumerWidget {
  const _ArchiveMediaButton({required this.archive, required this.onMedia});

  final Archive archive;
  final VoidCallback onMedia;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchable =
        ref.watch(archiveMediaSupportedProvider).valueOrNull ?? false;
    if (!archiveHasMedia(archive, printerSearchable: searchable)) {
      return const SizedBox.shrink();
    }
    return Padding(
      // The gap goes above, like every other row in the sheet — the slice
      // button is the one exception, and only because the delete button below
      // it brings none of its own.
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        width: double.infinity,
        child: logTag(
          'archive.media',
          OutlinedButton.icon(
            icon: const Icon(Icons.perm_media_outlined),
            label: Text(AppLocalizations.of(context).archiveMediaAction),
            onPressed: onMedia,
          ),
        ),
      ),
    );
  }
}

/// Delete-confirmation dialog with a "remove from statistics" choice. Shared
/// by single- and multi-delete (caller supplies [title]/[message]).
/// Returns `null` (cancel) or the `purge_stats` flag via `Navigator.pop`.
class _DeleteArchiveDialog extends StatefulWidget {
  const _DeleteArchiveDialog({required this.title, required this.message});

  final String title;
  final String message;

  @override
  State<_DeleteArchiveDialog> createState() => _DeleteArchiveDialogState();
}

class _DeleteArchiveDialogState extends State<_DeleteArchiveDialog> {
  bool _purgeStats = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: 8),
          logTag(
            'archive_delete.purge_stats',
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _purgeStats,
              onChanged: (v) => setState(() => _purgeStats = v ?? false),
              title: Text(l10n.archiveDeletePurgeStats),
              subtitle: Text(l10n.archiveDeletePurgeStatsHint),
            ),
          ),
        ],
      ),
      actions: [
        logTag(
          'archive_delete.cancel',
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
        ),
        logTag(
          'archive_delete.confirm',
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, _purgeStats),
            child: Text(l10n.archiveDelete),
          ),
        ),
      ],
    );
  }
}

/// "Purge older than" dialog: pick a day threshold + purge-stats choice, see a
/// live count/size preview, then confirm. Returns `(days, purgeStats)` or
/// `null` on cancel.
class _PurgeOlderDialog extends ConsumerStatefulWidget {
  const _PurgeOlderDialog();

  @override
  ConsumerState<_PurgeOlderDialog> createState() => _PurgeOlderDialogState();
}

class _PurgeOlderDialogState extends ConsumerState<_PurgeOlderDialog> {
  static const _dayOptions = [7, 30, 90, 180, 365];

  int _days = 90;
  bool _purgeStats = false;
  AsyncValue<ArchivePurgePreview> _preview = const AsyncValue.loading();

  @override
  void initState() {
    super.initState();
    _fetchPreview();
  }

  Future<void> _fetchPreview() async {
    setState(() => _preview = const AsyncValue.loading());
    try {
      final preview = await ref
          .read(archiveRepositoryProvider)
          .purgePreview(olderThanDays: _days, purgeStats: _purgeStats);
      if (mounted) setState(() => _preview = AsyncValue.data(preview));
    } on AppApiException catch (e, st) {
      if (mounted) setState(() => _preview = AsyncValue.error(e, st));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final canDelete = _preview.valueOrNull?.isEmpty == false;

    return AlertDialog(
      title: Text(l10n.archivePurgeTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(l10n.archivePurgeOlderThan)),
              logTag(
                'archive_purge.days',
                DropdownButton<int>(
                  value: _days,
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _days = v);
                    _fetchPreview();
                  },
                  items: [
                    for (final d in _dayOptions)
                      DropdownMenuItem(
                        value: d,
                        // Named per value: "purged 30 days" and "purged
                        // everything" are not the same report.
                        child: logTag('archive_purge.days.$d',
                            Text(l10n.archivePurgeDaysOption(d))),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _preview.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            ),
            error: (_, _) => Text(
              l10n.archivePurgePreviewError,
              style: TextStyle(color: theme.colorScheme.error),
            ),
            data: (p) => Text(
              p.isEmpty
                  ? l10n.archivePurgeNothing
                  : l10n.archivePurgePreview(
                      p.count,
                      formatBytes(p.totalBytes),
                    ),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          logTag(
            'archive_purge.purge_stats',
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _purgeStats,
              onChanged: (v) {
                setState(() => _purgeStats = v ?? false);
                _fetchPreview();
              },
              title: Text(l10n.archiveDeletePurgeStats),
              subtitle: Text(l10n.archiveDeletePurgeStatsHint),
            ),
          ),
        ],
      ),
      actions: [
        logTag(
          'archive_purge.cancel',
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
        ),
        logTag(
          'archive_purge.confirm',
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
            onPressed: canDelete
                ? () => Navigator.pop(context, (
                    days: _days,
                    purgeStats: _purgeStats,
                  ))
                : null,
            child: Text(l10n.archiveDelete),
          ),
        ),
      ],
    );
  }
}

/// Archive filter/sort sheet. All choices write straight to
/// [archiveFiltersProvider]; the list behind the sheet re-filters live.
/// Option sets (materials, colors) are derived from the loaded [archives] so
/// only values that actually occur are offered.
class _ArchiveFilterSheet extends ConsumerWidget {
  const _ArchiveFilterSheet({required this.archives});

  final List<Archive> archives;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final filters = ref.watch(archiveFiltersProvider);
    final notifier = ref.read(archiveFiltersProvider.notifier);
    final printers =
        ref.watch(printersForPickerProvider).valueOrNull ?? const [];

    final materials = <String>{
      for (final a in archives)
        ...?a.filamentType?.split(', ').map((m) => m.trim()),
    }..removeWhere((m) => m.isEmpty);
    final sortedMaterials = materials.toList()..sort();

    final colors = <String>{for (final a in archives) ...a.filamentColors};

    // Printer options limited to those with archives present.
    final usedPrinterIds = {
      for (final a in archives)
        if (a.printerId != null) a.printerId!,
    };

    return logTag(
      'sheet.archive_filters',
      DraggableSheetSurface(
        initialSize: 0.6,
        maxSize: 0.9,
        minSize: 0.35,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            // Fixed height so the header never resizes when the Clear button
            // toggles; the button keeps its slot via Visibility.maintainSize so
            // its appearance can't reflow the sheet content.
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  Text(l10n.archiveFilters, style: theme.textTheme.titleLarge),
                  const Spacer(),
                  Visibility(
                    visible: filters.activeCount > 0,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: TextButton(
                      onPressed: () => notifier.state = ArchiveFilters(
                        // Keep the current search + sort; only clear filters.
                        query: filters.query,
                        sort: filters.sort,
                      ),
                      child: Text(l10n.archiveFiltersClear),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            FilterGroupLabel(label: l10n.archiveSortLabel),
            _ChipWrap(
              children: [
                for (final s in ArchiveSort.values)
                  ChoiceChip(
                    label: Text(_sortLabel(l10n, s)),
                    selected: filters.sort == s,
                    onSelected: (_) =>
                        notifier.state = filters.copyWith(sort: s),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            FilterGroupLabel(label: l10n.archiveFilterFileType),
            _ChipWrap(
              children: [
                for (final f in ArchiveFileType.values)
                  ChoiceChip(
                    label: Text(_fileTypeLabel(l10n, f)),
                    selected: filters.fileType == f,
                    onSelected: (_) =>
                        notifier.state = filters.copyWith(fileType: f),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            FilterGroupLabel(label: l10n.archiveFilterFlags),
            _ChipWrap(
              children: [
                FilterChip(
                  avatar: Icon(
                    filters.favoritesOnly ? Icons.star : Icons.star_border,
                    size: 18,
                  ),
                  label: Text(l10n.archiveFilterFavorites),
                  selected: filters.favoritesOnly,
                  onSelected: (v) =>
                      notifier.state = filters.copyWith(favoritesOnly: v),
                ),
                FilterChip(
                  label: Text(l10n.archiveFilterHideFailed),
                  selected: filters.hideFailed,
                  onSelected: (v) =>
                      notifier.state = filters.copyWith(hideFailed: v),
                ),
                FilterChip(
                  label: Text(l10n.archiveFilterHideDuplicates),
                  selected: filters.hideDuplicates,
                  onSelected: (v) =>
                      notifier.state = filters.copyWith(hideDuplicates: v),
                ),
              ],
            ),

            if (usedPrinterIds.isNotEmpty) ...[
              const SizedBox(height: 16),
              FilterGroupLabel(label: l10n.archiveFilterPrinter),
              _ChipWrap(
                children: [
                  for (final p in printers)
                    if (usedPrinterIds.contains(p.id))
                      FilterChip(
                        label: Text(p.name),
                        selected: filters.printerId == p.id,
                        onSelected: (v) => notifier.state = v
                            ? filters.copyWith(printerId: p.id)
                            : filters.copyWith(clearPrinter: true),
                      ),
                ],
              ),
            ],

            if (sortedMaterials.isNotEmpty) ...[
              const SizedBox(height: 16),
              FilterGroupLabel(label: l10n.archiveFilterMaterial),
              _ChipWrap(
                children: [
                  for (final m in sortedMaterials)
                    FilterChip(
                      label: Text(m),
                      selected: filters.material == m,
                      onSelected: (v) => notifier.state = v
                          ? filters.copyWith(material: m)
                          : filters.copyWith(clearMaterial: true),
                    ),
                ],
              ),
            ],

            if (colors.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  FilterGroupLabel(label: l10n.archiveFilterColors),
                  const Spacer(),
                  if (filters.colors.length > 1)
                    // OR/AND only matters once several colors are picked.
                    SegmentedButton<ColorFilterMode>(
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                      segments: [
                        ButtonSegment(
                          value: ColorFilterMode.or,
                          label: Text(l10n.archiveColorModeAny),
                        ),
                        ButtonSegment(
                          value: ColorFilterMode.and,
                          label: Text(l10n.archiveColorModeAll),
                        ),
                      ],
                      selected: {filters.colorMode},
                      onSelectionChanged: (s) =>
                          notifier.state = filters.copyWith(colorMode: s.first),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              _ColorSwatchWrap(
                colors: colors.toList(),
                selected: filters.colors,
                onToggle: (c) {
                  final next = {...filters.colors};
                  if (!next.remove(c)) next.add(c);
                  notifier.state = filters.copyWith(colors: next);
                },
              ),
            ],
          ],
        ),
      )
    );
  }

  String _sortLabel(AppLocalizations l10n, ArchiveSort s) => switch (s) {
    ArchiveSort.dateDesc => l10n.archiveSortDateDesc,
    ArchiveSort.dateAsc => l10n.archiveSortDateAsc,
    ArchiveSort.nameAsc => l10n.archiveSortNameAsc,
    ArchiveSort.nameDesc => l10n.archiveSortNameDesc,
    ArchiveSort.sizeDesc => l10n.archiveSortSizeDesc,
    ArchiveSort.sizeAsc => l10n.archiveSortSizeAsc,
  };

  String _fileTypeLabel(AppLocalizations l10n, ArchiveFileType f) =>
      switch (f) {
        ArchiveFileType.all => l10n.archiveFileTypeAll,
        ArchiveFileType.gcode => l10n.archiveFileTypeGcode,
        ArchiveFileType.source => l10n.archiveFileTypeSource,
      };
}

class _ChipWrap extends StatelessWidget {
  const _ChipWrap({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 8, runSpacing: 4, children: children);
}

/// Row of filament-color swatches; tapping one toggles it in the color filter.
class _ColorSwatchWrap extends StatelessWidget {
  const _ColorSwatchWrap({
    required this.colors,
    required this.selected,
    required this.onToggle,
  });

  final List<String> colors;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final hex in colors)
          _ColorSwatch(
            color: colorFromHex(hex),
            selected: selected.contains(hex),
            accent: t.accentGreen,
            border: t.subCardBorder,
            onTap: () => onToggle(hex),
          ),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.accent,
    required this.border,
    required this.onTap,
  });

  final Color? color;
  final bool selected;
  final Color accent;
  final Color border;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Pick a readable check color for the swatch's own luminance.
    final checkColor = (color != null && color!.computeLuminance() > 0.5)
        ? Colors.black
        : Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? accent : border,
            width: selected ? 3 : 1,
          ),
        ),
        child: color == null
            ? Icon(Icons.help_outline, size: 18, color: checkColor)
            : (selected
                  ? Icon(Icons.check, size: 18, color: checkColor)
                  : null),
      ),
    );
  }
}

