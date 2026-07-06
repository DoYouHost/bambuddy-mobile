import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/printer_file.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../projects/project_files.dart' show saveBytesToFile;

/// Client-side sort keys for the printer file list (the endpoint doesn't sort).
enum PrinterFileSort { nameAsc, nameDesc, sizeAsc, sizeDesc, dateAsc, dateDesc }

/// Browse a printer's on-device storage: navigate folders, filter/sort, then
/// download or delete files. Shown only for online printers (offline FTP fails).
///
/// State is local (not a Riverpod notifier): a listing is a live FTP snapshot
/// scoped to this screen, refreshed on navigation / pull / after a mutation.
class PrinterFileManagerScreen extends ConsumerStatefulWidget {
  const PrinterFileManagerScreen({
    super.key,
    required this.printerId,
    required this.printerName,
  });

  final int printerId;
  final String printerName;

  @override
  ConsumerState<PrinterFileManagerScreen> createState() =>
      _PrinterFileManagerScreenState();
}

class _PrinterFileManagerScreenState
    extends ConsumerState<PrinterFileManagerScreen> {
  String _path = '/';
  List<PrinterFile>? _files; // null = not loaded yet
  bool _loading = false;
  String? _error; // localized load error
  PrinterStorage _storage = const PrinterStorage();

  PrinterFileSort _sort = PrinterFileSort.nameAsc;
  String _query = '';
  final Set<String> _selected = {}; // full paths of selected files
  bool _busy = false; // download/delete in progress

  // Quick-navigation shortcuts, mirroring the server web UI.
  static const _quickDirs = [
    ('/', _QuickTab.root),
    ('/cache', _QuickTab.cache),
    ('/model', _QuickTab.models),
    ('/timelapse', _QuickTab.timelapse),
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _loadStorage();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _selected.clear();
    });
    try {
      final repo = ref.read(printerFilesRepositoryProvider);
      final files = await repo.listFiles(widget.printerId, _path);
      if (!mounted) return;
      setState(() {
        _files = files;
        _loading = false;
      });
    } on AppApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.localized(AppLocalizations.of(context));
      });
    }
  }

  Future<void> _loadStorage() async {
    final storage =
        await ref.read(printerFilesRepositoryProvider).fetchStorage(widget.printerId);
    if (!mounted) return;
    setState(() => _storage = storage);
  }

  void _navigateTo(String path) {
    if (path == _path) {
      _load();
      return;
    }
    setState(() {
      _path = path;
      _query = '';
      _files = null;
    });
    _load();
  }

  void _navigateUp() {
    if (_path == '/') return;
    final parts = _path.split('/').where((p) => p.isNotEmpty).toList()..removeLast();
    _navigateTo(parts.isEmpty ? '/' : '/${parts.join('/')}');
  }

  /// Files after search filter, folders first, then the selected sort applied
  /// within each group (matches the server web UI ordering).
  List<PrinterFile> get _visible {
    final files = _files ?? const <PrinterFile>[];
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? [...files]
        : files.where((f) => f.name.toLowerCase().contains(q)).toList();
    filtered.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return switch (_sort) {
        PrinterFileSort.nameAsc =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        PrinterFileSort.nameDesc =>
          b.name.toLowerCase().compareTo(a.name.toLowerCase()),
        PrinterFileSort.sizeAsc => a.size.compareTo(b.size),
        PrinterFileSort.sizeDesc => b.size.compareTo(a.size),
        PrinterFileSort.dateAsc => _compareDate(a, b),
        PrinterFileSort.dateDesc => _compareDate(b, a),
      };
    });
    return filtered;
  }

  int _compareDate(PrinterFile a, PrinterFile b) {
    final da = a.modifiedAt, db = b.modifiedAt;
    if (da == null && db == null) return 0;
    if (da == null) return 1; // unknown dates sort last
    if (db == null) return -1;
    return da.compareTo(db);
  }

  List<PrinterFile> get _selectableFiles =>
      _visible.where((f) => !f.isDirectory).toList();

  void _toggleSelection(String path) => setState(() {
        _selected.contains(path) ? _selected.remove(path) : _selected.add(path);
      });

  void _toggleSelectAll() {
    final all = _selectableFiles.map((f) => f.path).toSet();
    setState(() {
      if (_selected.containsAll(all) && all.isNotEmpty) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(all);
      }
    });
  }

  Future<void> _download() async {
    if (_selected.isEmpty || _busy) return;
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(printerFilesRepositoryProvider);
    final paths = _selected.toList();
    setState(() => _busy = true);
    try {
      if (paths.length == 1) {
        final bytes = await repo.downloadFile(widget.printerId, paths.first);
        final name = paths.first.split('/').last;
        final saved = await saveBytesToFile(fileName: name, bytes: bytes);
        if (!mounted) return;
        if (saved != null) {
          _snack(l10n.pfmDownloadSaved);
          setState(_selected.clear);
        }
      } else {
        final bytes = await repo.downloadZip(widget.printerId, paths);
        final safeName =
            widget.printerName.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
        final saved =
            await saveBytesToFile(fileName: '$safeName-files.zip', bytes: bytes);
        if (!mounted) return;
        if (saved != null) {
          _snack(l10n.pfmDownloadSaved);
          setState(_selected.clear);
        }
      }
    } on AppApiException catch (e) {
      if (mounted) _snack(e.localized(l10n));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_selected.isEmpty || _busy) return;
    final l10n = AppLocalizations.of(context);
    final paths = _selected.toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.pfmDeleteConfirmTitle),
        content: Text(l10n.pfmDeleteConfirmBody(paths.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.pfmDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final repo = ref.read(printerFilesRepositoryProvider);
    var deleted = 0;
    String? failure;
    for (final path in paths) {
      try {
        await repo.deleteFile(widget.printerId, path);
        deleted++;
      } on AppApiException catch (e) {
        failure = e.localized(l10n);
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(failure ?? l10n.pfmDeleted(deleted));
    await _load();
    await _loadStorage();
  }

  void _snack(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final selectable = _selectableFiles;
    final allSelected =
        selectable.isNotEmpty && _selected.containsAll(selectable.map((f) => f.path));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.pfmTitle),
            Text(
              widget.printerName,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          if (_storage.usedBytes != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  l10n.pfmStorageUsed(_formatBytes(_storage.usedBytes!)),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          PopupMenuButton<PrinterFileSort>(
            icon: const Icon(Icons.sort),
            tooltip: l10n.pfmSortTooltip,
            initialValue: _sort,
            onSelected: (s) => setState(() => _sort = s),
            itemBuilder: (_) => [
              _sortItem(PrinterFileSort.nameAsc, l10n.pfmSortNameAsc),
              _sortItem(PrinterFileSort.nameDesc, l10n.pfmSortNameDesc),
              _sortItem(PrinterFileSort.sizeDesc, l10n.pfmSortSizeLargest),
              _sortItem(PrinterFileSort.sizeAsc, l10n.pfmSortSizeSmallest),
              _sortItem(PrinterFileSort.dateDesc, l10n.pfmSortDateNewest),
              _sortItem(PrinterFileSort.dateAsc, l10n.pfmSortDateOldest),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.pfmRefreshTooltip,
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          _quickNav(theme, l10n),
          _breadcrumb(theme),
          _searchAndSelectAll(l10n, selectable.isNotEmpty, allSelected),
          Expanded(child: _list(l10n, theme)),
        ],
      ),
      bottomNavigationBar:
          _selected.isEmpty ? null : _actionBar(l10n, theme),
    );
  }

  PopupMenuItem<PrinterFileSort> _sortItem(PrinterFileSort s, String label) =>
      PopupMenuItem(value: s, child: Text(label));

  Widget _quickNav(ThemeData theme, AppLocalizations l10n) => SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          children: [
            for (final (path, tab) in _quickDirs)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(_quickLabel(tab, l10n)),
                  selected: _path == path,
                  onSelected: (_) => _navigateTo(path),
                ),
              ),
          ],
        ),
      );

  String _quickLabel(_QuickTab tab, AppLocalizations l10n) => switch (tab) {
        _QuickTab.root => l10n.pfmTabRoot,
        _QuickTab.cache => l10n.pfmTabCache,
        _QuickTab.models => l10n.pfmTabModels,
        _QuickTab.timelapse => l10n.pfmTabTimelapse,
      };

  Widget _breadcrumb(ThemeData theme) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              visualDensity: VisualDensity.compact,
              onPressed: _path == '/' ? null : _navigateUp,
            ),
            Expanded(
              child: Text(
                _path,
                style: theme.textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );

  Widget _searchAndSelectAll(
    AppLocalizations l10n,
    bool hasSelectable,
    bool allSelected,
  ) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search),
                  hintText: l10n.pfmSearchHint,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            if (hasSelectable)
              TextButton(
                onPressed: _toggleSelectAll,
                child: Text(
                  allSelected ? l10n.pfmDeselectAll : l10n.pfmSelectAll,
                ),
              ),
          ],
        ),
      );

  Widget _list(AppLocalizations l10n, ThemeData theme) {
    if (_loading && _files == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _centered(
        icon: Icons.error_outline,
        message: _error!,
        theme: theme,
        action: FilledButton.tonal(onPressed: _load, child: Text(l10n.retry)),
      );
    }
    final items = _visible;
    if (items.isEmpty) {
      return _centered(
        icon: Icons.folder_open,
        message: (_files?.isEmpty ?? true) ? l10n.pfmEmpty : l10n.pfmNoMatches,
        theme: theme,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) => _row(items[i], theme),
      ),
    );
  }

  Widget _row(PrinterFile file, ThemeData theme) {
    if (file.isDirectory) {
      return ListTile(
        leading: Icon(Icons.folder, color: theme.colorScheme.primary),
        title: Text(file.name, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _navigateTo(file.path),
      );
    }
    final selected = _selected.contains(file.path);
    return ListTile(
      leading: Checkbox(
        value: selected,
        onChanged: (_) => _toggleSelection(file.path),
      ),
      title: Text(file.name, overflow: TextOverflow.ellipsis),
      subtitle: Text(_subtitle(file)),
      trailing: Icon(_iconFor(file.name),
          color: theme.colorScheme.onSurfaceVariant),
      onTap: () => _toggleSelection(file.path),
    );
  }

  String _subtitle(PrinterFile file) {
    final size = _formatBytes(file.size);
    final date = file.modifiedAt;
    if (date == null) return size;
    final local = date.toLocal();
    final d =
        '${local.year}-${_two(local.month)}-${_two(local.day)} ${_two(local.hour)}:${_two(local.minute)}';
    return '$size · $d';
  }

  Widget _actionBar(AppLocalizations l10n, ThemeData theme) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(child: Text(l10n.pfmSelected(_selected.length))),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else ...[
                TextButton.icon(
                  onPressed: _download,
                  icon: const Icon(Icons.download),
                  label: Text(l10n.pfmDownload),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: _delete,
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(l10n.pfmDelete),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _centered({
    required IconData icon,
    required String message,
    required ThemeData theme,
    Widget? action,
  }) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 16), action],
            ],
          ),
        ),
      );
}

enum _QuickTab { root, cache, models, timelapse }

String _two(int v) => v.toString().padLeft(2, '0');

/// Human-readable byte size (binary units), e.g. `833.8 KB`, `1.2 GB`.
String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
}

/// Rough icon by extension — matches the file types printers store.
IconData _iconFor(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    '3mf' || 'gcode' || 'stl' => Icons.view_in_ar,
    'mp4' || 'avi' || 'mov' => Icons.movie_outlined,
    'png' || 'jpg' || 'jpeg' || 'gif' => Icons.image_outlined,
    'zip' || 'gz' || 'tar' => Icons.folder_zip_outlined,
    'json' || 'txt' || 'log' || 'cfg' => Icons.description_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}
