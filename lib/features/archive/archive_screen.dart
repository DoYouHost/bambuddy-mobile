import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/archive.dart';
import '../../core/models/archive_purge.dart';
import '../../core/models/printer.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../common/print_thumbnail.dart';
import '../queue/queue_providers.dart';
import 'archive_providers.dart';

/// Archive screen for prints (M5): browsing with search and thumbnails,
/// reprint and add to queue (both require printer selection).
class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({super.key});

  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends ConsumerState<ArchiveScreen> {
  final _scrollController = ScrollController();
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

  void _selectAllVisible() {
    final items = ref.read(archiveProvider).valueOrNull?.items ?? const [];
    setState(() => _selected.addAll(items.map((a) => a.id)));
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Load next page as we approach the end of the list.
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      ref.read(archiveProvider.notifier).loadMore();
    }
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(archiveProvider.notifier).search(q.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(archiveProvider);

    return Scaffold(
      appBar: _selectionMode
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                tooltip: l10n.cancel,
                onPressed: _clearSelection,
              ),
              title: Text(l10n.archiveSelectedCount(_selected.length)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  tooltip: l10n.archiveSelectAll,
                  onPressed: _selectAllVisible,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: l10n.archiveDelete,
                  onPressed: _deleteSelected,
                ),
              ],
            )
          : AppBar(
              title: Text(l10n.navArchive),
              actions: [
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'purge') _purgeOlder();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'purge',
                      child: Text(l10n.archivePurgeOlder),
                    ),
                  ],
                ),
              ],
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SearchBar(
              hintText: l10n.archiveSearchHint,
              leading: const Icon(Icons.search),
              onChanged: _onSearchChanged,
            ),
          ),
          Expanded(
            child: async.when(
              skipLoadingOnReload: true,
              skipLoadingOnRefresh: true,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => _ErrorView(
                message: err is AppApiException
                    ? err.localized(l10n)
                    : l10n.connectFailed,
                retryLabel: l10n.retry,
                onRetry: () => ref.read(archiveProvider.notifier).refresh(),
              ),
              data: (s) => RefreshIndicator(
                onRefresh: () => ref.read(archiveProvider.notifier).refresh(),
                child: s.searchFailed
                    ? _EmptyView(
                        message: l10n.archiveSearchFailed(s.query),
                        icon: Icons.search_off,
                      )
                    : s.items.isEmpty
                        ? _EmptyView(message: l10n.archiveEmpty)
                        : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: s.items.length + (s.hasMore ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i >= s.items.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          final archive = s.items[i];
                          final card = _ArchiveCard(
                            archive: archive,
                            selected: _selected.contains(archive.id),
                            onTap: () => _selectionMode
                                ? _toggleSelect(archive.id)
                                : _openSheet(archive),
                            onLongPress: () => _toggleSelect(archive.id),
                          );
                          // No swipe-to-delete while multi-selecting.
                          return _selectionMode
                              ? card
                              : _deletable(archive, card);
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openSheet(Archive archive) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _ArchiveSheet(
        archive: archive,
        onReprint: () => _reprint(archive),
        onAddToQueue: () => _addToQueue(archive),
        onPreviewGcode: () => _previewGcode(archive),
        onDelete: () => _deleteFromSheet(archive),
      ),
    );
  }

  /// Swipe-to-delete wrapper. Confirmation (with the purge-stats choice) runs
  /// in `confirmDismiss`; the actual delete runs in `onDismissed` so the
  /// notifier's optimistic removal stays in sync with the dismiss animation.
  Widget _deletable(Archive archive, Widget child) {
    final theme = Theme.of(context);
    return Dismissible(
      key: ValueKey('archive_dismiss_${archive.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.delete_outline,
            color: theme.colorScheme.onErrorContainer),
      ),
      confirmDismiss: (_) async {
        final purge = await _askDelete(archive);
        if (purge == null) return false;
        _pendingPurge = purge;
        return true;
      },
      onDismissed: (_) => _deleteArchive(archive, _pendingPurge),
      child: child,
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
    messenger.showSnackBar(SnackBar(
      content: Text(ok ? l10n.archiveDeleted : l10n.archiveDeleteFailed),
    ));
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
    messenger.showSnackBar(SnackBar(
      content: Text(res.failed == 0
          ? l10n.archiveDeletedCount(res.ok)
          : l10n.archiveDeleteSomeFailed(res.ok, res.failed)),
    ));
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
      final deleted = await ref.read(archiveRepositoryProvider).purge(
            olderThanDays: result.days,
            purgeStats: result.purgeStats,
          );
      await ref.read(archiveProvider.notifier).refresh();
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.archivePurgeResult(deleted))),
      );
    } on AppApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_errText(e, l10n))));
    }
  }

  /// G-code preview: closes sheet and opens full-screen 3D viewer.
  void _previewGcode(Archive archive) {
    Navigator.pop(context);
    final name = Uri.encodeQueryComponent(archive.displayName);
    context.push('/gcode-viewer?archive=${archive.id}&name=$name');
  }

  /// Reprint: printer selection → confirmation → POST reprint. Initiates
  /// physical print, so always behind confirmation dialog.
  Future<void> _reprint(Archive archive) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);

    final printer = await _pickPrinter(l10n);
    if (printer == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.archiveReprintConfirmTitle),
        content: Text(l10n.archiveReprintConfirmBody(printer.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.archiveReprint),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(archiveRepositoryProvider)
          .reprint(archive.id, printerId: printer.id);
      messenger
          .showSnackBar(SnackBar(content: Text(l10n.archiveReprintStarted)));
    } on AppApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_errText(e, l10n))));
    }
  }

  /// Add to queue: printer selection → POST /queue/. On success, refreshes
  /// the queue tab.
  Future<void> _addToQueue(Archive archive) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);

    final printer = await _pickPrinter(l10n);
    if (printer == null || !mounted) return;

    try {
      await ref
          .read(queueRepositoryProvider)
          .addFromArchive(archive.id, printerId: printer.id);
      // Refresh queue list so new item is visible after tab switch.
      await ref.read(queueProvider.notifier).refresh();
      messenger.showSnackBar(SnackBar(content: Text(l10n.archiveAddedToQueue)));
    } on AppApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_errText(e, l10n))));
    }
  }

  /// Bottom sheet with printer list. If exactly one — returns it without asking.
  /// If zero — message and null.
  Future<Printer?> _pickPrinter(AppLocalizations l10n) async {
    final messenger = ScaffoldMessenger.of(context);
    final List<Printer> printers;
    try {
      printers = await ref.read(printersForPickerProvider.future);
    } on AppApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_errText(e, l10n))));
      return null;
    }
    if (!mounted) return null;
    if (printers.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.noPrintersAvailable)));
      return null;
    }
    if (printers.length == 1) return printers.first;

    return showModalBottomSheet<Printer>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.pickPrinterTitle,
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final p in printers)
              ListTile(
                leading: const Icon(Icons.print_outlined),
                title: Text(p.name),
                subtitle: p.model == null ? null : Text(p.model!),
                onTap: () => Navigator.pop(ctx, p),
              ),
          ],
        ),
      ),
    );
  }

  String _errText(AppApiException e, AppLocalizations l10n) =>
      e is AuthException && e.code == AppErrorCode.forbidden
          ? l10n.ctrlForbidden
          : l10n.ctrlFailed;
}

class _ArchiveCard extends StatelessWidget {
  const _ArchiveCard({
    required this.archive,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
  });

  final Archive archive;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = <String>[
      if (archive.filamentType != null) archive.filamentType!,
      if (archive.filamentUsedGrams != null)
        '${archive.filamentUsedGrams!.toStringAsFixed(0)} g',
      if (archive.createdAt != null) _date(archive.createdAt!),
    ];
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: selected ? theme.colorScheme.primaryContainer : null,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        leading: selected
            ? CircleAvatar(
                backgroundColor: theme.colorScheme.primary,
                child: Icon(Icons.check, color: theme.colorScheme.onPrimary),
              )
            : PrintThumbnail(archiveId: archive.id, size: 56),
        title: Text(
          archive.displayName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: meta.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(meta.join(' · '),
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
        trailing: archive.isFavorite
            ? Icon(Icons.star, size: 18, color: theme.colorScheme.tertiary)
            : null,
        onTap: onTap,
        onLongPress: onLongPress,
        selected: selected,
      ),
    );
  }

  String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _ArchiveSheet extends StatelessWidget {
  const _ArchiveSheet({
    required this.archive,
    required this.onReprint,
    required this.onAddToQueue,
    required this.onPreviewGcode,
    required this.onDelete,
  });

  final Archive archive;
  final VoidCallback onReprint;
  final VoidCallback onAddToQueue;
  final VoidCallback onPreviewGcode;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SafeArea(
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
                      Text(archive.displayName,
                          style: theme.textTheme.titleMedium,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis),
                      if (archive.designer != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(archive.designer!,
                              style: theme.textTheme.bodySmall),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.playlist_add),
                    label: Text(l10n.archiveAddToQueue),
                    onPressed: onAddToQueue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.print),
                    label: Text(l10n.archiveReprint),
                    onPressed: onReprint,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.view_in_ar_outlined),
                label: Text(l10n.gcodeViewerOpen),
                onPressed: onPreviewGcode,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.archiveDelete),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                onPressed: onDelete,
              ),
            ),
          ],
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
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _purgeStats,
            onChanged: (v) => setState(() => _purgeStats = v ?? false),
            title: Text(l10n.archiveDeletePurgeStats),
            subtitle: Text(l10n.archiveDeletePurgeStatsHint),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
          ),
          onPressed: () => Navigator.pop(context, _purgeStats),
          child: Text(l10n.archiveDelete),
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
      final preview = await ref.read(archiveRepositoryProvider).purgePreview(
            olderThanDays: _days,
            purgeStats: _purgeStats,
          );
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
                      child: Text(l10n.archivePurgeDaysOption(d)),
                    ),
                ],
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
                  : l10n.archivePurgePreview(p.count, _formatBytes(p.totalBytes)),
              style: theme.textTheme.bodyMedium,
            ),
          ),
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
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
          ),
          onPressed: canDelete
              ? () => Navigator.pop(
                    context,
                    (days: _days, purgeStats: _purgeStats),
                  )
              : null,
          child: Text(l10n.archiveDelete),
        ),
      ],
    );
  }
}

/// Human-readable byte size (binary units), e.g. `12.3 MB`.
String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var size = bytes / 1024;
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(1)} ${units[unit]}';
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.message, this.icon = Icons.inventory_2_outlined});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            children: [
              Icon(icon, size: 48, color: Theme.of(context).disabledColor),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.retryLabel,
  });

  final String message;
  final VoidCallback onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}
