import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/archive.dart';
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
      appBar: AppBar(title: Text(l10n.navArchive)),
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
                          return _ArchiveCard(
                            archive: s.items[i],
                            onTap: () => _openSheet(s.items[i]),
                          );
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
      ),
    );
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
  const _ArchiveCard({required this.archive, required this.onTap});

  final Archive archive;
  final VoidCallback onTap;

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
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        leading: PrintThumbnail(archiveId: archive.id, size: 56),
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
  });

  final Archive archive;
  final VoidCallback onReprint;
  final VoidCallback onAddToQueue;
  final VoidCallback onPreviewGcode;

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
          ],
        ),
      ),
    );
  }
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
