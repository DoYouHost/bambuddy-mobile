import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/models/library_file.dart';
import '../../core/models/library_folder.dart';
import '../../core/models/queue_item.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../common/confirm_dialog.dart';
import '../common/prompt_name_dialog.dart';
import '../common/dash_search_field.dart';
import '../common/sliver_search_bar.dart';
import '../common/format_bytes.dart' show formatBytes;
import '../common/state_views.dart';
import '../queue/queue_edit_screen.dart';
import '../slicer/slice_providers.dart';
import '../slicer/slice_sheet.dart';
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

  void _snack(String msg) =>
      _messenger.showSnackBar(SnackBar(content: Text(msg)));

  String _errText(AppApiException e) => e.localized(_l10n);

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
                      onPressed:
                          state == null ? null : () => _openSortSheet(state),
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
                  onPressed:
                      state == null ? null : () => _openCreateSheet(state),
                  child: const Icon(Icons.add),
                ),
              ),
        body: async.when(
          skipLoadingOnReload: true,
          skipLoadingOnRefresh: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => AsyncErrorView(
            message:
                err is AppApiException ? err.localized(l10n) : l10n.connectFailed,
            retryLabel: l10n.retry,
            onRetry: () => ref.invalidate(fileManagerProvider),
          ),
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
        child: Center(child: CircularProgressIndicator()),
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
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
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
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                leading: Icon(s.sort == entry.$1
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked),
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
        (ref.read(slicerEnabledProvider).valueOrNull ?? false) && !file.isPrintable;
    final tagsSupported = libraryTagsSupported(ref.read(libraryTagsProvider));
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
                    child: Text(file.displayName,
                        style: Theme.of(ctx).textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
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
            if (canSlice)
              ListTile(
                leading: const Icon(Icons.layers_outlined),
                title: Text(l10n.sliceAction),
                onTap: () {
                  Navigator.pop(ctx);
                  _sliceFile(file);
                },
              ).tagged('file_actions.slice'),
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
                subtitle: Text(file.tags.isEmpty
                    ? l10n.fmTagsNone
                    : file.tagNames.join(', ')),
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
      if (!mounted) return;
      _snack(_errText(e));
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
      if (!mounted) return;
      _snack(_errText(e));
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
      if (!mounted) return;
      _snack(_errText(e));
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
      if (!mounted) return;
      _snack(_errText(e));
    }
  }

  Future<void> _moveFile(LibraryFile file) async {
    final state = ref.read(fileManagerProvider).valueOrNull;
    if (state == null) return;
    final target = await _pickFolder(state, excludeFolderId: null);
    if (target == null || !mounted) return; // anulowano
    try {
      await ref
          .read(libraryRepositoryProvider)
          .moveFiles([file.id], folderId: target.moveTargetId);
      if (!mounted) return;
      await ref.read(fileManagerProvider.notifier).refresh();
      if (!mounted) return;
      _snack(_l10n.fmMoved);
    } on AppApiException catch (e) {
      if (!mounted) return;
      _snack(_errText(e));
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
      if (!mounted) return;
      _snack(_errText(e));
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
      if (!mounted) return;
      _snack(_errText(e));
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

  Future<void> _addSelectedToQueue(FileManagerState s) async {
    final ids = s.selected.toList();
    try {
      await ref.read(libraryRepositoryProvider).addToQueue(ids);
      if (!mounted) return;
      ref.read(fileManagerProvider.notifier).clearSelection();
      _snack(_l10n.fmAddedToQueue);
    } on AppApiException catch (e) {
      if (!mounted) return;
      _snack(_errText(e));
    }
  }

  Future<void> _addToQueue(LibraryFile file) async {
    try {
      await ref.read(libraryRepositoryProvider).addToQueue([file.id]);
      if (!mounted) return;
      _snack(_l10n.fmAddedToQueue);
    } on AppApiException catch (e) {
      if (!mounted) return;
      _snack(_errText(e));
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
    final name = Uri.encodeQueryComponent(file.displayName);
    context.push('/gcode-viewer?library_file=${file.id}&name=$name');
  }

  Future<void> _sliceFile(LibraryFile file) async {
    final sliced = await showSliceSheet(
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
    final FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(withReadStream: false);
    } on Exception {
      if (!mounted) return;
      _snack(l10n.fmUploadFailed);
      return;
    }
    if (!mounted) return;
    final path = picked?.files.single.path;
    final name = picked?.files.single.name;
    if (path == null || name == null) return; // anulowano

    _snack(l10n.fmUploading);
    try {
      await ref.read(libraryRepositoryProvider).uploadFile(
            filePath: path,
            filename: name,
            folderId: s.currentFolderId,
          );
      if (!mounted) return;
      await ref.read(fileManagerProvider.notifier).refresh();
      if (!mounted) return;
      ref.invalidate(libraryStatsProvider);
      _snack(l10n.fmUploaded(name));
    } on AppApiException catch (e) {
      if (!mounted) return;
      _snack(_errText(e));
    }
  }

  Future<String?> _promptName({
    required String title,
    required String label,
    String? initial,
  }) =>
      promptName(context, title: title, label: label, initial: initial);

  /// Target folder picker (move). Includes "All Files" (root).
  /// [excludeFolderId] skips folder and its subtree (folder move).
  Future<LibraryFolder?> _pickFolder(
    FileManagerState s, {
    int? excludeFolderId,
  }) {
    final l10n = _l10n;
    final folders = [...s.allFolders]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return showModalBottomSheet<LibraryFolder>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.fmMoveTo,
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: Text(l10n.fmRoot),
              onTap: () =>
                  Navigator.pop(ctx, const LibraryFolder(id: -1, name: '')),  // Sentinel for root.
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
      if (stats.freeBytes != null) l10n.fmStatsFree(formatBytes(stats.freeBytes!)),
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: t.subCard,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(
        parts.join('  ·  '),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: DashTokens.fontMono,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: t.textTertiary,
        ),
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
    TextStyle crumbStyle(bool current) => TextStyle(
          fontFamily: DashTokens.fontUi,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: current ? t.textPrimary : t.accentGreenInk,
        );
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          TextButton.icon(
            icon: Icon(Icons.home_outlined,
                size: 18, color: crumbs.isEmpty ? t.textTertiary : t.accentGreenInk),
            label: Text(l10n.fmRoot, style: crumbStyle(crumbs.isEmpty)),
            onPressed: crumbs.isEmpty ? null : () => onOpen(null),
          ).tagged('files.crumb_root'),
          for (var i = 0; i < crumbs.length; i++) ...[
            Icon(Icons.chevron_right, size: 18, color: t.textTertiary),
            TextButton(
              onPressed: i == crumbs.length - 1
                  ? null
                  : () => onOpen(crumbs[i].id),
              child: Text(crumbs[i].name,
                  style: crumbStyle(i == crumbs.length - 1)),
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
                color: state.tagFilter.isEmpty ? t.textSecondary : t.accentGreenInk,
              ),
              onPressed: () => showTagFilterSheet(context),
            ),
          ),
        ],
        if (types.isNotEmpty) ...[
          const SizedBox(width: 4),
          PopupMenuButton<String?>(
            tooltip: l10n.fmFilterType,
            icon: Icon(
              state.typeFilter == null
                  ? Icons.filter_list
                  : Icons.filter_list_alt,
              color: t.textSecondary,
            ),
            onSelected: (v) => ref.read(fileManagerProvider.notifier).setType(v),
            itemBuilder: (ctx) => [
              CheckedPopupMenuItem<String?>(
                value: null,
                checked: state.typeFilter == null,
                child: logTag('files.type_all', Text(l10n.fmAllTypes)),
              ),
              for (final ft in types)
                CheckedPopupMenuItem<String?>(
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
                          style: TextStyle(
                            fontFamily: DashTokens.fontUi,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: t.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.fmFolderItems(folder.fileCount),
                          style: TextStyle(
                            fontFamily: DashTokens.fontUi,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: t.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!folder.isExternal)
                    logTag(
                      'files.folder_actions',
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert, color: t.textSecondary),
                        onSelected: (v) => v == 'rename' ? onRename() : onDelete(),
                        itemBuilder: (ctx) => [
                          PopupMenuItem(
                            value: 'rename',
                            child: logTag('files.folder.rename',
                                Text(l10n.fmRename)),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: logTag('files.folder.delete',
                                Text(l10n.fmDelete)),
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
                          style: TextStyle(
                            fontFamily: DashTokens.fontUi,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: t.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          meta.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: DashTokens.fontMono,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: t.textTertiary,
                          ),
                        ),
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
