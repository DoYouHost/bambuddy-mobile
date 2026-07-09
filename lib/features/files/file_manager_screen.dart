import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/library_file.dart';
import '../../core/models/library_folder.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../common/confirm_dialog.dart';
import '../common/format_bytes.dart' show formatBytes;
import '../common/printer_picker.dart';
import '../common/state_views.dart';
import '../slicer/slice_providers.dart';
import '../slicer/slice_sheet.dart';
import 'file_manager_providers.dart';
import 'library_thumbnail.dart';

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

  String _errText(AppApiException e) =>
      e is AuthException && e.code == AppErrorCode.forbidden
          ? _l10n.ctrlForbidden
          : _l10n.ctrlFailed;

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n;
    final async = ref.watch(fileManagerProvider);
    // Warm the slice gate so the per-file sheet can read it synchronously.
    ref.watch(slicerEnabledProvider);
    final state = async.valueOrNull;
    final selectionMode = state?.selectionMode ?? false;

    return Scaffold(
      appBar: selectionMode
          ? _selectionAppBar(state!)
          : AppBar(
              title: Text(l10n.fileManagerTitle),
              actions: [
                IconButton(
                  tooltip: l10n.fmSortBy,
                  icon: const Icon(Icons.sort),
                  onPressed: state == null ? null : () => _openSortSheet(state),
                ),
                IconButton(
                  tooltip: l10n.fmTrash,
                  icon: const Icon(Icons.recycling),
                  onPressed: () => context.push('/files/trash'),
                ),
              ],
            ),
      floatingActionButton: selectionMode
          ? null
          : FloatingActionButton(
              onPressed: state == null ? null : () => _openCreateSheet(state),
              child: const Icon(Icons.add),
            ),
      body: async.when(
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => AsyncErrorView(
          message: err is AppApiException ? err.localized(l10n) : l10n.connectFailed,
          retryLabel: l10n.retry,
          onRetry: () => ref.invalidate(fileManagerProvider),
        ),
        data: (s) => Column(
          children: [
            const _StatsBar(),
            _Breadcrumb(
              state: s,
              onOpen: (id) => ref.read(fileManagerProvider.notifier).openFolder(id),
            ),
            _FilterRow(
              state: s,
              controller: _searchController,
              onSearch: _onSearchChanged,
            ),
            Expanded(child: _body(s)),
          ],
        ),
      ),
    );
  }

  Widget _body(FileManagerState s) {
    final l10n = _l10n;
    // Search is global (all library) — in search mode show matching files from all library,
    // not subfolders of current directory.
    final folders = s.isSearching ? const [] : s.subfolders;
    final files = s.visibleFiles;
    final notifier = ref.read(fileManagerProvider.notifier);

    // Fetching search index, no results yet.
    if (s.searching && files.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: notifier.refresh,
      child: (folders.isEmpty && files.isEmpty)
          ? EmptyStateView(
              message: s.searchFailed
                  ? l10n.connectFailed
                  : s.isSearching || s.typeFilter != null
                      ? l10n.fmNoMatches
                      : l10n.fmEmpty,
              icon: s.searchFailed
                  ? Icons.cloud_off
                  : Icons.folder_open_outlined,
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 88),
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
                    // Show folder location in search results (root when no folder).
                    folderLabel: s.isSearching
                        ? (s.folderName(f.folderId) ?? l10n.fmRoot)
                        : null,  // Show folder location in global search results.
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

  // --- AppBar trybu zaznaczania ---

  AppBar _selectionAppBar(FileManagerState s) {
    final l10n = _l10n;
    final notifier = ref.read(fileManagerProvider.notifier);
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: notifier.clearSelection,
      ),
      title: Text(l10n.fmSelectedCount(s.selected.length)),
      actions: [
        IconButton(
          tooltip: l10n.fmAddToQueue,
          icon: const Icon(Icons.playlist_add),
          onPressed: s.selected.isEmpty ? null : () => _addSelectedToQueue(s),
        ),
        IconButton(
          tooltip: l10n.fmDelete,
          icon: const Icon(Icons.delete_outline),
          onPressed: s.selected.isEmpty ? null : () => _deleteSelected(s),
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
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: Text(l10n.fmUpload),
              onTap: () {
                Navigator.pop(ctx);
                _uploadFile(s);
              },
            ),
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
              ),
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
              ),
              ListTile(
                leading: const Icon(Icons.view_in_ar_outlined),
                title: Text(l10n.gcodeViewerOpen),
                onTap: () {
                  Navigator.pop(ctx);
                  _previewGcode(file);
                },
              ),
            ],
            if (canSlice)
              ListTile(
                leading: const Icon(Icons.layers_outlined),
                title: Text(l10n.sliceAction),
                onTap: () {
                  Navigator.pop(ctx);
                  _sliceFile(file);
                },
              ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: Text(l10n.fmAddToQueue),
              onTap: () {
                Navigator.pop(ctx);
                _addToQueue(file);
              },
            ),
            if (!file.isExternal) ...[
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: Text(l10n.fmRename),
                onTap: () {
                  Navigator.pop(ctx);
                  _renameFile(file);
                },
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_move_outline),
                title: Text(l10n.fmMoveTo),
                onTap: () {
                  Navigator.pop(ctx);
                  _moveFile(file);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(l10n.fmDelete),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteFile(file);
                },
              ),
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

  Future<void> _printFile(LibraryFile file) async {
    final l10n = _l10n;
    final printer = await pickPrinterSheet(context, ref, l10n);
    if (printer == null || !mounted) return;
    final ok = await confirmDialog(
      context,
      title: l10n.fmPrint,
      message: l10n.fmPrintConfirmBody(file.displayName, printer.name),
      confirmLabel: l10n.fmPrint,
    );
    if (!ok || !mounted) return;
    try {
      await ref
          .read(queueRepositoryProvider)
          .addFromLibraryFile(file.id, printerId: printer.id);
      if (!mounted) return;
      _snack(l10n.fmPrintStarted);
    } on AppApiException catch (e) {
      if (!mounted) return;
      _snack(_errText(e));
    }
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
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) =>
          _PromptNameDialog(title: title, label: label, initial: initial),
    );
  }

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
            ),
            for (final f in folders)
              if (f.id != excludeFolderId && !f.isExternal)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(f.name),
                  onTap: () => Navigator.pop(ctx, f),
                ),
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

/// Name-prompt dialog (new folder / rename folder or file) — a StatefulWidget
/// so it owns and disposes its own controller in the State lifecycle, same as
/// `_NotesEditDialog` in project_detail_screen.dart (disposing a
/// function-local controller right after `await showDialog` races the
/// dialog's exit animation).
class _PromptNameDialog extends StatefulWidget {
  const _PromptNameDialog({
    required this.title,
    required this.label,
    this.initial,
  });

  final String title;
  final String label;
  final String? initial;

  @override
  State<_PromptNameDialog> createState() => _PromptNameDialogState();
}

class _PromptNameDialogState extends State<_PromptNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(l10n.fmSave),
        ),
      ],
    );
  }
}

class _StatsBar extends ConsumerWidget {
  const _StatsBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
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
      color: theme.colorScheme.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(parts.join('  ·  '),
          style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
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
    final theme = Theme.of(context);
    final crumbs = state.breadcrumb;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          TextButton.icon(
            icon: const Icon(Icons.home_outlined, size: 18),
            label: Text(l10n.fmRoot),
            onPressed: crumbs.isEmpty ? null : () => onOpen(null),
          ),
          for (var i = 0; i < crumbs.length; i++) ...[
            Icon(Icons.chevron_right,
                size: 18, color: theme.colorScheme.onSurfaceVariant),
            TextButton(
              onPressed: i == crumbs.length - 1
                  ? null
                  : () => onOpen(crumbs[i].id),
              child: Text(crumbs[i].name),
            ),
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
    final types = state.availableTypes;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: SearchBar(
              controller: controller,
              hintText: l10n.fmSearchHint,
              leading: const Icon(Icons.search),
              padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 12)),
              onChanged: onSearch,
            ),
          ),
          if (types.isNotEmpty) ...[
            const SizedBox(width: 8),
            PopupMenuButton<String?>(
              tooltip: l10n.fmFilterType,
              icon: Icon(state.typeFilter == null
                  ? Icons.filter_list
                  : Icons.filter_list_alt),
              onSelected: (v) =>
                  ref.read(fileManagerProvider.notifier).setType(v),
              itemBuilder: (ctx) => [
                CheckedPopupMenuItem<String?>(
                  value: null,
                  checked: state.typeFilter == null,
                  child: Text(l10n.fmAllTypes),
                ),
                for (final t in types)
                  CheckedPopupMenuItem<String?>(
                    value: t,
                    checked: state.typeFilter == t,
                    child: Text(t.toUpperCase()),
                  ),
              ],
            ),
          ],
        ],
      ),
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
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: ListTile(
        leading: Icon(
          folder.isExternal ? Icons.folder_special_outlined : Icons.folder,
          color: theme.colorScheme.primary,
        ),
        title: Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(l10n.fmFolderItems(folder.fileCount)),
        trailing: folder.isExternal
            ? null
            : PopupMenuButton<String>(
                onSelected: (v) => v == 'rename' ? onRename() : onDelete(),
                itemBuilder: (ctx) => [
                  PopupMenuItem(value: 'rename', child: Text(l10n.fmRename)),
                  PopupMenuItem(value: 'delete', child: Text(l10n.fmDelete)),
                ],
              ),
        onTap: onOpen,
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
    final theme = Theme.of(context);
    final meta = <String>[
      ?folderLabel,
      file.fileType.toUpperCase(),
      formatBytes(file.fileSize),
      if (file.slicedForModel != null) file.slicedForModel!,
      if (file.createdByUsername != null) file.createdByUsername!,
    ];
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      color: selected ? theme.colorScheme.secondaryContainer : null,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
        leading: selectionMode
            ? Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              )
            : LibraryThumbnail(
                fileId: file.id,
                hasThumbnail: file.thumbnailPath != null,
                size: 52,
              ),
        title: Text(file.displayName,
            maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(meta.join(' · '),
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
        trailing: selectionMode ? null : const Icon(Icons.more_vert, size: 20),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}
