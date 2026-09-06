import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/models/library_file.dart';
import '../../core/models/library_folder.dart';
import '../../core/models/queue_item.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import '../common/confirm_dialog.dart';
import '../common/dash_async.dart';
import '../common/dash_progress.dart';
import '../common/dash_sheet.dart';
import '../common/dash_snack.dart';
import '../gcode/gcode_viewer_route.dart';
import '../common/device_files.dart';
import '../common/prompt_name_dialog.dart';
import '../common/dash_search_field.dart';
import '../common/sliver_search_bar.dart';
import '../common/format_bytes.dart' show formatBytes;
import '../common/state_views.dart';
import '../queue/queue_edit_screen.dart';
import '../slicer/slice_providers.dart';
import '../../data/pipelines_repository.dart' show PipelineSource;
import '../pipelines/pipeline_run_screen.dart';
import '../pipelines/pipelines_providers.dart' show canRunPipelinesProvider;
import '../slicer/slice_screen.dart';
import 'file_manager_providers.dart';
import 'library_thumbnail.dart';
import 'tag_sheets.dart';

/// File manager (library): folder navigation, thumbnails, file actions (print, queue,
/// rename, move, delete), folder CRUD, upload, and trash. UI pattern consistent with archive screen.
class FileManagerScreen extends ConsumerStatefulWidget {
  const FileManagerScreen({super.key});

  @override
  ConsumerState<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends ConsumerState<FileManagerScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  AppLocalizations get _l10n => AppLocalizations.of(context);
  ScaffoldMessengerState get _messenger => ScaffoldMessenger.of(context);

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      ref.read(fileManagerProvider.notifier).setQuery(q.trim());
    });
  }

  void _snack(String msg) => _messenger.snack(msg);

  /// Both halves of a failed action: the sentence, and the record that somebody
  /// was stopped. Unmounted — the screen was left while the request was in
  /// flight — there is neither a messenger nor an `l10n` to resolve, so only
  /// the record is written, marked as one that reached nobody.
  void _failed(AppApiException e, String action) => mounted
      ? showApiFailure(_messenger, e, _l10n, action: action)
      : recordActionFailure(e, action: action, shown: false);

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n;
    final t = DashTokens.of(context);
    final async = ref.watch(fileManagerProvider);
    // Warm the slice gate so the per-file sheet can read it synchronously.
    ref.watch(slicerEnabledProvider);
    final state = async.valueOrNull;
    final selectionMode = state?.selectionMode ?? false;

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: selectionMode
            ? _selectionAppBar(state!)
            : dashAppBar(
                context,
                title: l10n.fileManagerTitle,
                actions: [
                  logTag(
                    'files.sort',
                    IconButton(
                      tooltip: l10n.fmSortBy,
                      icon: const Icon(Icons.sort),
                      onPressed: state == null
                          ? null
                          : () => _openSortSheet(state),
                    ),
                  ),
                  logTag(
                    'files.trash',
                    IconButton(
                      tooltip: l10n.fmTrash,
                      icon: const Icon(Icons.recycling),
                      onPressed: () => context.push('/files/trash'),
                    ),
                  ),
                ],
              ),
        floatingActionButton: selectionMode
            ? null
            : logTag(
                'files.create',
                FloatingActionButton(
                  backgroundColor: t.accentGreen,
                  foregroundColor: const Color(0xFF0A0C08),
                  onPressed: state == null
                      ? null
                      : () => _openCreateSheet(state),
                  child: const Icon(Icons.add),
                ),
              ),
        body: dashAsync(
          context,
          async,
          onRetry: () => ref.invalidate(fileManagerProvider),
          // Stats + breadcrumb stay pinned; the search/filter row rolls away
          // with the scrollable list below it.
          data: (s) => Column(
            children: [
              const _StatsBar(),
              _Breadcrumb(
                state: s,
                onOpen: (id) =>
                    ref.read(fileManagerProvider.notifier).openFolder(id),
              ),
              Expanded(child: _body(s)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(FileManagerState s) {
    final l10n = _l10n;
    // Search and the tag filter are both library-wide — folders of the current
    // directory would be noise next to results from everywhere.
    final folders = s.isSearching || s.isTagFiltering ? const [] : s.subfolders;
    final files = s.visibleFiles;
    final notifier = ref.read(fileManagerProvider.notifier);

    final Widget content;
    if (s.searching && files.isEmpty) {
      // Fetching search index, no results yet.
      content = const SliverFillRemaining(
        hasScrollBody: false,
        child: DashLoading(),
      );
    } else if (folders.isEmpty && files.isEmpty) {
      content = SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyStateView(
          message: s.fetchFailed
              ? l10n.connectFailed
              : s.isSearching || s.isTagFiltering || s.typeFilter != null
              ? l10n.fmNoMatches
              : l10n.fmEmpty,
          icon: s.fetchFailed ? Icons.cloud_off : Icons.folder_open_outlined,
        ),
      );
    } else {
      content = SliverPadding(
        padding: const EdgeInsets.only(top: 8, bottom: 88),
        sliver: SliverList.list(
          children: [
            for (final f in folders)
              _FolderTile(
                folder: f,
                onOpen: () => notifier.openFolder(f.id),
                onRename: () => _renameFolder(f),
                onDelete: () => _deleteFolder(f),
              ),
            for (final f in files)
              _FileTile(
                file: f,
                selected: s.selected.contains(f.id),
                selectionMode: s.selectionMode,
                // Show folder location in global search results (root when none).
                folderLabel: s.isSearching
                    ? (s.folderName(f.folderId) ?? l10n.fmRoot)
                    : null,
                onTap: () {
                  if (s.selectionMode) {
                    notifier.toggleSelect(f.id);
                  } else {
                    _openFileSheet(f);
                  }
                },
                onLongPress: () => notifier.toggleSelect(f.id),
              ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: notifier.refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          DashSliverSearchBar(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: _FilterRow(
              state: s,
              controller: _searchController,
              onSearch: _onSearchChanged,
            ),
          ),
          content,
        ],
      ),
    );
  }

  // --- AppBar trybu zaznaczania ---

  PreferredSizeWidget _selectionAppBar(FileManagerState s) {
    final l10n = _l10n;
    final notifier = ref.read(fileManagerProvider.notifier);
    return dashAppBar(
      context,
      title: l10n.fmSelectedCount(s.selected.length),
      leading: logTag(
        'files.selection_clear',
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: notifier.clearSelection,
        ),
      ),
      actions: [
        if (libraryTagsSupported(ref.watch(libraryTagsProvider)))
          logTag(
            'files.tag_selected',
            IconButton(
              tooltip: l10n.fmTags,
              icon: const Icon(Icons.sell_outlined),
              onPressed: s.selected.isEmpty ? null : () => _tagSelected(s),
            ),
          ),
        // Server 1.2.6+ only, and meaningless below two files — a group of one
        // expresses no choice and the server refuses it.
        if (ref
            .watch(crossModelVariantsProvider)
            .maybeWhen(data: (v) => v, orElse: () => false))
          logTag(
            'files.group_variants',
            IconButton(
              tooltip: l10n.fmGroupAsVariants,
              icon: const Icon(Icons.alt_route),
              onPressed: s.selected.length < 2
                  ? null
                  : () => _groupAsVariants(s),
            ),
          ),
        logTag(
          'files.add_to_queue',
          IconButton(
            tooltip: l10n.fmAddToQueue,
            icon: const Icon(Icons.playlist_add),
            onPressed: s.selected.isEmpty ? null : () => _addSelectedToQueue(s),
          ),
        ),
        logTag(
          'files.delete_selected',
          IconButton(
            tooltip: l10n.fmDelete,
            icon: const Icon(Icons.delete_outline),
            onPressed: s.selected.isEmpty ? null : () => _deleteSelected(s),
          ),
        ),
      ],
    );
  }

  void _openCreateSheet(FileManagerState s) {
    final l10n = _l10n;
    dashSheet<void>(
      context,
      scrollControlled: false,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: Text(l10n.fmNewFolder),
              onTap: () {
                Navigator.pop(ctx);
                _createFolder(s);
              },
            ).tagged('files.new_folder'),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: Text(l10n.fmUpload),
              onTap: () {
                Navigator.pop(ctx);
                _uploadFile(s);
              },
            ).tagged('files.upload'),
          ],
        ),
      ),
    );
  }

  void _openSortSheet(FileManagerState s) {
    final l10n = _l10n;
    final notifier = ref.read(fileManagerProvider.notifier);
    dashSheet<void>(
      context,
      scrollControlled: false,
      builder: (ctx) => SafeArea(
        // Six options fit at the default text scale and stop fitting well before
        // the largest one, so this scrolls for the same reason the file sheet
        // above does.
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final entry in <(FileSort, String)>[
              (FileSort.dateDesc, l10n.fmSortDateNewest),
              (FileSort.dateAsc, l10n.fmSortDateOldest),
              (FileSort.nameAsc, l10n.fmSortNameAZ),
              (FileSort.nameDesc, l10n.fmSortNameZA),
              (FileSort.sizeDesc, l10n.fmSortSizeLargest),
              (FileSort.sizeAsc, l10n.fmSortSizeSmallest),
            ])
              ListTile(
                leading: Icon(
                  s.sort == entry.$1
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(entry.$2),
                onTap: () {
                  notifier.setSort(entry.$1);
                  Navigator.pop(ctx);
                },
              ).tagged('files.sort_option'),
          ],
        ),
      ),
    );
  }

  void _openFileSheet(LibraryFile file) {
    final l10n = _l10n;
    // Slicing only applies to un-sliced models (not gcode), and only when the
    // server's slicer sidecar is enabled.
    final canSlice =
        ref.read(slicerEnabledProvider).orFalse && !file.isPrintable;
    final tagsSupported = libraryTagsSupported(ref.read(libraryTagsProvider));
    dashSheet<void>(
      context,
      scrollControlled: false,
      builder: (ctx) => SafeArea(
        // Scrollable, not a Column: this sheet reaches nine tiles plus the
        // thumbnail header (print + preview *or* slice, two for variants, tags,
        // and three more for a local file), which is taller than the half-screen
        // a bottom sheet gets. As a Column that is a RenderFlex overflow with the
        // last actions simply unreachable.
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  LibraryThumbnail(
                    fileId: file.id,
                    hasThumbnail: file.thumbnailPath != null,
                    size: 56,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      file.displayName,
                      style: Theme.of(ctx).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (file.isPrintable) ...[
              ListTile(
                leading: const Icon(Icons.print_outlined),
                title: Text(l10n.fmPrint),
                onTap: () {
                  Navigator.pop(ctx);
                  _printFile(file);
                },
              ).tagged('file_actions.print'),
              ListTile(
                leading: const Icon(Icons.view_in_ar_outlined),
                title: Text(l10n.gcodeViewerOpen),
                onTap: () {
                  Navigator.pop(ctx);
                  _previewGcode(file);
                },
              ).tagged('file_actions.preview_gcode'),
            ],
            // Only for a file that is actually grouped, so the action never
            // appears on a server that has no variant groups at all.
            if (file.hasVariants) ...[
              ListTile(
                leading: const Icon(Icons.alt_route),
                title: Text(l10n.fmQueueAsVariants),
                subtitle: Text(l10n.fmVariantsMemberCount(file.variantCount)),
                onTap: () {
                  Navigator.pop(ctx);
                  _queueAsVariants(file);
                },
              ).tagged('file_actions.queue_variants'),
              ListTile(
                leading: const Icon(Icons.call_split),
                title: Text(l10n.fmUngroupVariants),
                onTap: () {
                  Navigator.pop(ctx);
                  _ungroupVariants(file);
                },
              ).tagged('file_actions.ungroup_variants'),
            ],
            if (canSlice)
              ListTile(
                leading: const Icon(Icons.layers_outlined),
                title: Text(l10n.sliceAction),
                onTap: () {
                  Navigator.pop(ctx);
                  _sliceFile(file);
                },
              ).tagged('file_actions.slice'),
            // Slice and dispatch in one go, using a saved bundle. Sits next to
            // Slice because it needs the same source and the same permission
            // to produce a print — only the picking of profiles differs.
            //
            // Its own [Consumer], where every other row here reads with
            // `ref.read`: this gate is the one that is not settled yet. It is a
            // probe of the server's routes, so it resolves after the first
            // frames — and the screen's `ref` cannot rebuild a sheet that lives
            // in its own route, which left the action missing on a server that
            // does have pipelines.
            if (canSlice)
              Consumer(
                builder: (_, sheetRef, _) =>
                    sheetRef.watch(canRunPipelinesProvider).orFalse
                    ? ListTile(
                        leading: const Icon(Icons.account_tree_outlined),
                        title: Text(l10n.pipelineRun),
                        onTap: () {
                          Navigator.pop(ctx);
                          _runPipeline(file);
                        },
                      ).tagged('file_actions.run_pipeline')
                    : const SizedBox.shrink(),
              ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: Text(l10n.fmAddToQueue),
              onTap: () {
                Navigator.pop(ctx);
                _addToQueue(file);
              },
            ).tagged('file_actions.add_to_queue'),
            // Offered for external files too: a tag is a row in the server's
            // database, not a change to the file on the host's disk.
            if (tagsSupported)
              ListTile(
                leading: const Icon(Icons.sell_outlined),
                title: Text(l10n.fmTags),
                subtitle: Text(
                  file.tags.isEmpty
                      ? l10n.fmTagsNone
                      : file.tagNames.join(', '),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _tagFile(file);
                },
              ).tagged('file_actions.tags'),
            if (!file.isExternal) ...[
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: Text(l10n.fmRename),
                onTap: () {
                  Navigator.pop(ctx);
                  _renameFile(file);
                },
              ).tagged('file_actions.rename'),
              ListTile(
                leading: const Icon(Icons.drive_file_move_outline),
                title: Text(l10n.fmMoveTo),
                onTap: () {
                  Navigator.pop(ctx);
                  _moveFile(file);
                },
              ).tagged('file_actions.move'),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(l10n.fmDelete),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteFile(file);
                },
              ).tagged('file_actions.delete'),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _createFolder(FileManagerState s) async {
    final name = await _promptName(
      title: _l10n.fmNewFolder,
      label: _l10n.fmFolderName,
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await ref
          .read(libraryRepositoryProvider)
          .createFolder(name, parentId: s.currentFolderId);
      if (!mounted) return;
      await ref.read(fileManagerProvider.notifier).refresh();
      if (!mounted) return;
      _snack(_l10n.fmFolderCreated);
    } on AppApiException catch (e) {
      _failed(e, 'files.new_folder');
    }
  }

  Future<void> _renameFolder(LibraryFolder folder) async {
    final name = await _promptName(
      title: _l10n.fmRenameFolder,
      label: _l10n.fmFolderName,
      initial: folder.name,
    );
    if (name == null || name.isEmpty || name == folder.name || !mounted) {
      return;
    }
    try {
      await ref.read(libraryRepositoryProvider).renameFolder(folder.id, name);
      if (!mounted) return;
      await ref.read(fileManagerProvider.notifier).refresh();
      if (!mounted) return;
      _snack(_l10n.fmRenamed);
    } on AppApiException catch (e) {
      _failed(e, 'files.folder.rename');
    }
  }

  Future<void> _deleteFolder(LibraryFolder folder) async {
    final ok = await confirmDialog(
      context,
      id: 'files.folder_delete_confirm',
      title: _l10n.fmDeleteFolder,
      message: _l10n.fmDeleteFolderConfirm(folder.name),
      confirmLabel: _l10n.fmDelete,
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(libraryRepositoryProvider).deleteFolder(folder.id);
      if (!mounted) return;
      await ref.read(fileManagerProvider.notifier).refresh();
      if (!mounted) return;
      _snack(_l10n.fmDeleted);
    } on AppApiException catch (e) {
      _failed(e, 'files.folder.delete');
    }
  }

  Future<void> _renameFile(LibraryFile file) async {
    final name = await _promptName(
      title: _l10n.fmRenameFile,
      label: _l10n.fmFileName,
      initial: file.filename,
    );
    if (name == null || name.isEmpty || name == file.filename || !mounted) {
      return;
    }
    try {
      await ref.read(libraryRepositoryProvider).renameFile(file.id, name);
      if (!mounted) return;
      await ref.read(fileManagerProvider.notifier).refresh();
      if (!mounted) return;
      _snack(_l10n.fmRenamed);
    } on AppApiException catch (e) {
      _failed(e, 'file_actions.rename');
    }
  }

  Future<void> _moveFile(LibraryFile file) async {
    final state = ref.read(fileManagerProvider).valueOrNull;
    if (state == null) return;
    final target = await _pickFolder(state, excludeFolderId: null);
    if (target == null || !mounted) return; // anulowano
    try {
      await ref.read(libraryRepositoryProvider).moveFiles([
        file.id,
      ], folderId: target.moveTargetId);
      if (!mounted) return;
      await ref.read(fileManagerProvider.notifier).refresh();
      if (!mounted) return;
      _snack(_l10n.fmMoved);
    } on AppApiException catch (e) {
      _failed(e, 'file_actions.move');
    }
  }

  Future<void> _deleteFile(LibraryFile file) async {
    final ok = await confirmDialog(
      context,
      id: 'files.delete_confirm',
      title: _l10n.fmDeleteFile,
      message: _l10n.fmDeleteFileConfirm(file.displayName),
      confirmLabel: _l10n.fmDelete,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(libraryRepositoryProvider).deleteFile(file.id);
      if (!mounted) return;
      await ref.read(fileManagerProvider.notifier).refresh();
      if (!mounted) return;
      _snack(_l10n.fmDeleted);
    } on AppApiException catch (e) {
      _failed(e, 'file_actions.delete');
    }
  }

  Future<void> _deleteSelected(FileManagerState s) async {
    final ids = s.selected.toList();
    final ok = await confirmDialog(
      context,
      id: 'files.bulk_delete_confirm',
      title: _l10n.fmDelete,
      message: _l10n.fmDeleteSelectedConfirm(ids.length),
      confirmLabel: _l10n.fmDelete,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(libraryRepositoryProvider).bulkDelete(fileIds: ids);
      if (!mounted) return;
      ref.read(fileManagerProvider.notifier).clearSelection();
      await ref.read(fileManagerProvider.notifier).refresh();
      if (!mounted) return;
      _snack(_l10n.fmDeleted);
    } on AppApiException catch (e) {
      _failed(e, 'files.delete_selected');
    }
  }

  /// Bulk tagging. Selection survives on purpose when nothing was applied
  /// (cancelled sheet), so a mis-tap doesn't cost the user their selection.
  Future<void> _tagSelected(FileManagerState s) async {
    final changed = await showBulkTagsSheet(context, s.selected.toList());
    if (!changed || !mounted) return;
    ref.read(fileManagerProvider.notifier).clearSelection();
    await ref.read(fileManagerProvider.notifier).refresh();
  }

  Future<void> _tagFile(LibraryFile file) async {
    final changed = await showFileTagsSheet(context, file);
    if (!changed || !mounted) return;
    await ref.read(fileManagerProvider.notifier).refresh();
    if (mounted) _snack(_l10n.fmTagsSaved);
  }

  /// Group the selection as cross-model alternatives (server #671).
  ///
  /// Two files minimum, and the selection order is the priority order the
  /// scheduler will use. The server refuses a file that already belongs to
  /// another group (409) — surfaced as-is rather than pre-checked, because the
  /// listing we hold can be stale and the server's answer cannot.
  Future<void> _groupAsVariants(FileManagerState s) async {
    final ids = s.selected.toList();
    try {
      final group = await ref
          .read(libraryRepositoryProvider)
          .createVariantGroup(ids);
      if (!mounted) return;
      ref.read(fileManagerProvider.notifier).clearSelection();
      await ref.read(fileManagerProvider.notifier).refresh();
      if (!mounted) return;
      _snack(_l10n.fmVariantsGrouped(group.members.length));
    } on AppApiException catch (e) {
      _failed(e, 'files.group_variants');
    }
  }

  /// Queue [file]'s whole group as one cross-model job — the point of grouping.
  ///
  /// Fetches the group first rather than trusting the cached row: the listing
  /// carries only a count, and the scheduler needs the members in their
  /// priority order. A group that vanished between listing and tap comes back
  /// as null, which is the same "nothing to queue" as an ungrouped file.
  Future<void> _queueAsVariants(LibraryFile file) async {
    try {
      final group = await ref
          .read(libraryRepositoryProvider)
          .variantGroupForFile(file.id);
      if (group == null || group.members.length < 2) {
        if (!mounted) return;
        _snack(_l10n.fmVariantsGone);
        return;
      }
      await ref.read(queueRepositoryProvider).addCrossModel([
        for (final m in group.members) m.libraryFileId,
      ]);
      if (!mounted) return;
      _snack(_l10n.fmAddedToQueue);
    } on AppApiException catch (e) {
      _failed(e, 'file_actions.queue_variants');
    }
  }

  /// Dissolve the group [file] belongs to, so each file stands alone again.
  Future<void> _ungroupVariants(LibraryFile file) async {
    final groupId = file.variantGroupId;
    if (groupId == null) return;
    try {
      await ref.read(libraryRepositoryProvider).deleteVariantGroup(groupId);
      if (!mounted) return;
      await ref.read(fileManagerProvider.notifier).refresh();
      if (!mounted) return;
      _snack(_l10n.fmVariantsUngrouped);
    } on AppApiException catch (e) {
      _failed(e, 'file_actions.ungroup_variants');
    }
  }

  Future<void> _addSelectedToQueue(FileManagerState s) async {
    final ids = s.selected.toList();
    try {
      await ref.read(libraryRepositoryProvider).addToQueue(ids);
      if (!mounted) return;
      ref.read(fileManagerProvider.notifier).clearSelection();
      _snack(_l10n.fmAddedToQueue);
    } on AppApiException catch (e) {
      _failed(e, 'files.add_to_queue');
    }
  }

  Future<void> _addToQueue(LibraryFile file) async {
    try {
      await ref.read(libraryRepositoryProvider).addToQueue([file.id]);
      if (!mounted) return;
      _snack(_l10n.fmAddedToQueue);
    } on AppApiException catch (e) {
      _failed(e, 'file_actions.add_to_queue');
    }
  }

  /// Print: the full print form, opened on ASAP. The job is configured before
  /// the queue item exists, so nothing can dispatch it mid-setup.
  Future<void> _printFile(LibraryFile file) async {
    await openQueueCreate(
      context,
      draft: QueueItem.draft(
        libraryFileId: file.id,
        name: file.displayName,
        thumbnail: file.thumbnailPath,
        slicedForModel: file.slicedForModel,
      ),
      schedule: QueueScheduleType.asap,
    );
  }

  /// G-code preview: opens the full-screen 3D viewer for a sliced library file.
  void _previewGcode(LibraryFile file) {
    context.push(
      gcodeViewerRoute(libraryFileId: file.id, title: file.displayName),
    );
  }

  /// Run a saved pipeline against this file — slices it and dispatches the
  /// copies without going through the four pickers.
  Future<void> _runPipeline(LibraryFile file) async {
    await showPipelineRunScreen(
      context,
      source: PipelineSource.libraryFile(file.id),
      sourceName: file.displayName,
    );
  }

  Future<void> _sliceFile(LibraryFile file) async {
    final sliced = await showSliceScreen(
      context,
      SliceTarget.libraryFile(file.id, file.displayName),
    );
    // A completed slice adds a new gcode file to the library — refresh.
    if (sliced && mounted) {
      await ref.read(fileManagerProvider.notifier).refresh();
      ref.invalidate(libraryStatsProvider);
    }
  }

  Future<void> _uploadFile(FileManagerState s) async {
    final l10n = _l10n;
    final picked = await pickFileFromDevice();
    if (!mounted) return;
    final file = picked.file;
    if (file == null) {
      if (picked.outcome == DeviceFileOutcome.failed) {
        _snack(l10n.fmUploadFailed);
      }
      return;
    }

    _snack(l10n.fmUploading);
    try {
      await ref
          .read(libraryRepositoryProvider)
          .uploadFile(
            filePath: file.path,
            filename: file.name,
            folderId: s.currentFolderId,
          );
      if (!mounted) return;
      await ref.read(fileManagerProvider.notifier).refresh();
      if (!mounted) return;
      ref.invalidate(libraryStatsProvider);
      _snack(l10n.fmUploaded(file.name));
    } on AppApiException catch (e) {
      _failed(e, 'files.upload');
    }
  }

  Future<String?> _promptName({
    required String title,
    required String label,
    String? initial,
  }) => promptName(context, title: title, label: label, initial: initial);

  /// Target folder picker (move). Includes "All Files" (root).
  /// [excludeFolderId] skips folder and its subtree (folder move).
  Future<LibraryFolder?> _pickFolder(
    FileManagerState s, {
    int? excludeFolderId,
  }) {
    final l10n = _l10n;
    final folders = [...s.allFolders]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return dashSheet<LibraryFolder>(
      context,
      scrollControlled: false,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.fmMoveTo,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: Text(l10n.fmRoot),
              onTap: () => Navigator.pop(
                ctx,
                const LibraryFolder(id: -1, name: ''),
              ), // Sentinel for root.
            ).tagged('files.move_target_root'),
            for (final f in folders)
              if (f.id != excludeFolderId && !f.isExternal)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(f.name),
                  onTap: () => Navigator.pop(ctx, f),
                ).tagged('files.move_target'),
          ],
        ),
      ),
    );
  }
}

/// Helper: for root selection from [_pickFolder] we return sentinel id=-1;
/// translate to `folderId=null` in move call.
extension on LibraryFolder {
  int? get moveTargetId => id == -1 ? null : id;
}

class _StatsBar extends ConsumerWidget {
  const _StatsBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final stats = ref.watch(libraryStatsProvider).valueOrNull;
    if (stats == null) return const SizedBox.shrink();
    final parts = <String>[
      if (stats.totalFiles != null) l10n.fmStatsFiles(stats.totalFiles!),
      if (stats.totalFolders != null) l10n.fmStatsFolders(stats.totalFolders!),
      if (stats.totalSizeBytes != null) formatBytes(stats.totalSizeBytes!),
      if (stats.freeBytes != null)
        l10n.fmStatsFree(formatBytes(stats.freeBytes!)),
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: t.subCard,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(
        parts.join('  ·  '),
        textAlign: TextAlign.center,
        style: t.monoLabel,
      ),
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.state, required this.onOpen});

  final FileManagerState state;
  final void Function(int? folderId) onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final crumbs = state.breadcrumb;
    TextStyle crumbStyle(bool current) =>
        t.bodyBold.copyWith(color: current ? t.textPrimary : t.accentGreenInk);
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          TextButton.icon(
            icon: Icon(
              Icons.home_outlined,
              size: 18,
              color: crumbs.isEmpty ? t.textTertiary : t.accentGreenInk,
            ),
            label: Text(l10n.fmRoot, style: crumbStyle(crumbs.isEmpty)),
            onPressed: crumbs.isEmpty ? null : () => onOpen(null),
          ).tagged('files.crumb_root'),
          for (var i = 0; i < crumbs.length; i++) ...[
            Icon(Icons.chevron_right, size: 18, color: t.textTertiary),
            TextButton(
              onPressed: i == crumbs.length - 1
                  ? null
                  : () => onOpen(crumbs[i].id),
              child: Text(
                crumbs[i].name,
                style: crumbStyle(i == crumbs.length - 1),
              ),
            ).tagged('files.crumb'),
          ],
        ],
      ),
    );
  }
}

class _FilterRow extends ConsumerWidget {
  const _FilterRow({
    required this.state,
    required this.controller,
    required this.onSearch,
  });

  final FileManagerState state;
  final TextEditingController controller;
  final ValueChanged<String> onSearch;

  /// Menu value for "All types", which the filter itself stores as `null`.
  /// See the item's own comment for why it cannot be `null`.
  static const _allTypes = '*';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final types = state.availableTypes;
    // Outer padding is supplied by the enclosing [DashSliverSearchBar].
    return Row(
      children: [
        Expanded(
          child: DashSearchField(
            id: 'files.search',
            controller: controller,
            hintText: l10n.fmSearchHint,
            onChanged: onSearch,
          ),
        ),
        if (libraryTagsSupported(ref.watch(libraryTagsProvider))) ...[
          const SizedBox(width: 4),
          logTag(
            'files.tag_filter',
            IconButton(
              tooltip: l10n.fmTagsFilterTitle,
              // A filled icon plus the accent is the only affordance saying the
              // listing is no longer the folder in the breadcrumb above it.
              icon: Icon(
                state.tagFilter.isEmpty ? Icons.sell_outlined : Icons.sell,
                color: state.tagFilter.isEmpty
                    ? t.textSecondary
                    : t.accentGreenInk,
              ),
              onPressed: () => showTagFilterSheet(context),
            ),
          ),
        ],
        if (types.isNotEmpty) ...[
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            tooltip: l10n.fmFilterType,
            icon: Icon(
              state.typeFilter == null
                  ? Icons.filter_list
                  : Icons.filter_list_alt,
              color: t.textSecondary,
            ),
            onSelected: (v) => ref
                .read(fileManagerProvider.notifier)
                .setType(v == _allTypes ? null : v),
            itemBuilder: (ctx) => [
              CheckedPopupMenuItem<String>(
                // Not `null`, which the filter stores for "no type filter":
                // `PopupMenuButton` cannot tell a null-valued item apart from a
                // dismissed menu, so such a row calls `onCanceled` and can
                // never be picked. A file extension is never `*`.
                value: _allTypes,
                checked: state.typeFilter == null,
                child: logTag('files.type_all', Text(l10n.fmAllTypes)),
              ),
              for (final ft in types)
                CheckedPopupMenuItem<String>(
                  value: ft,
                  checked: state.typeFilter == ft,
                  child: logTag('files.type_option', Text(ft.toUpperCase())),
                ),
            ],
          ).tagged('files.filter_type'),
        ],
      ],
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.folder,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final LibraryFolder folder;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: Colors.transparent,
        child: logTag(
          'files.folder',
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onOpen,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: t.subCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: t.subCardBorder),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: t.accentGreen.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      folder.isExternal
                          ? Icons.folder_special_outlined
                          : Icons.folder,
                      color: t.accentGreenInk,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          folder.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleSm,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.fmFolderItems(folder.fileCount),
                          style: t.label,
                        ),
                      ],
                    ),
                  ),
                  if (!folder.isExternal)
                    logTag(
                      'files.folder_actions',
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert, color: t.textSecondary),
                        onSelected: (v) =>
                            v == 'rename' ? onRename() : onDelete(),
                        itemBuilder: (ctx) => [
                          PopupMenuItem(
                            value: 'rename',
                            child: logTag(
                              'files.folder.rename',
                              Text(l10n.fmRename),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: logTag(
                              'files.folder.delete',
                              Text(l10n.fmDelete),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.file,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
    this.folderLabel,
  });

  final LibraryFile file;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Etykieta folderu (pokazywana w wynikach wyszukiwania globalnego).
  final String? folderLabel;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final meta = <String>[
      ?folderLabel,
      file.fileType.toUpperCase(),
      formatBytes(file.fileSize),
      if (file.slicedForModel != null) file.slicedForModel!,
      if (file.createdByUsername != null) file.createdByUsername!,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: Colors.transparent,
        child: logTag(
          'files.file',
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            onLongPress: onLongPress,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? t.accentGreen.withValues(alpha: 0.10)
                    : t.subCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected
                      ? t.accentGreen.withValues(alpha: 0.4)
                      : t.subCardBorder,
                ),
              ),
              child: Row(
                children: [
                  selectionMode
                      ? SizedBox(
                          width: 52,
                          height: 52,
                          child: Icon(
                            selected
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: selected ? t.accentGreenInk : t.textTertiary,
                          ),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: LibraryThumbnail(
                            fileId: file.id,
                            hasThumbnail: file.thumbnailPath != null,
                            size: 52,
                          ),
                        ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          file.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleSm,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          meta.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.monoLabel,
                        ),
                        // Marks a file that is one of several alternatives, so
                        // the grouping is visible without opening the sheet.
                        if (file.hasVariants) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.alt_route,
                                size: 12,
                                color: t.textTertiary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                AppLocalizations.of(
                                  context,
                                ).fmVariantsMemberCount(file.variantCount),
                                style: t.micro,
                              ),
                            ],
                          ),
                        ],
                        if (file.tags.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          // Capped so a file tagged a dozen times keeps the
                          // tile's height; the full set is in its action sheet.
                          Row(
                            children: [
                              for (final tag in file.tags.take(3)) ...[
                                Flexible(child: TagChip(tag.name)),
                                const SizedBox(width: 4),
                              ],
                              if (file.tags.length > 3)
                                TagChip('+${file.tags.length - 3}'),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!selectionMode)
                    Icon(Icons.more_vert, size: 20, color: t.textSecondary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
