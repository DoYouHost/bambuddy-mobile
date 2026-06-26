import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/trash_file.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import 'file_manager_providers.dart';
import 'file_manager_screen.dart' show formatBytes;

/// Library trash: list of deleted files with restore, permanent delete, and empty trash.
class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(libraryTrashProvider);
    final items = async.valueOrNull ?? const <TrashFile>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.fmTrashTitle),
        actions: [
          IconButton(
            tooltip: l10n.fmEmptyTrash,
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: items.isEmpty
                ? null
                : () => _emptyTrash(context, ref, l10n),
          ),
        ],
      ),
      body: async.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48),
                const SizedBox(height: 12),
                Text(
                  err is AppApiException ? err.localized(l10n) : l10n.connectFailed,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref.invalidate(libraryTrashProvider),
                  child: Text(l10n.retry),
                ),
              ],
            ),
          ),
        ),
        data: (items) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(libraryTrashProvider),
          child: items.isEmpty
              ? ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(48),
                      child: Column(
                        children: [
                          Icon(Icons.delete_outline,
                              size: 48,
                              color: Theme.of(context).disabledColor),
                          const SizedBox(height: 12),
                          Text(l10n.fmTrashEmpty, textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _TrashTile(
                    file: items[i],
                    onRestore: () => _restore(context, ref, l10n, items[i]),
                    onDelete: () => _hardDelete(context, ref, l10n, items[i]),
                  ),
                ),
        ),
      ),
    );
  }

  void _snack(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    TrashFile file,
  ) async {
    try {
      await ref.read(libraryRepositoryProvider).restoreFromTrash(file.id);
      ref.invalidate(libraryTrashProvider);
      ref.invalidate(fileManagerProvider);
      if (context.mounted) _snack(context, l10n.fmRestored);
    } on AppApiException {
      if (context.mounted) _snack(context, l10n.ctrlFailed);
    }
  }

  Future<void> _hardDelete(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    TrashFile file,
  ) async {
    final ok = await _confirm(
      context,
      l10n,
      title: l10n.fmHardDelete,
      body: l10n.fmHardDeleteConfirm(file.filename),
    );
    if (ok != true) return;
    try {
      await ref.read(libraryRepositoryProvider).hardDelete(file.id);
      ref.invalidate(libraryTrashProvider);
      if (context.mounted) _snack(context, l10n.fmDeletedForever);
    } on AppApiException {
      if (context.mounted) _snack(context, l10n.ctrlFailed);
    }
  }

  Future<void> _emptyTrash(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ok = await _confirm(
      context,
      l10n,
      title: l10n.fmEmptyTrash,
      body: l10n.fmEmptyTrashConfirm,
    );
    if (ok != true) return;
    try {
      await ref.read(libraryRepositoryProvider).emptyTrash();
      ref.invalidate(libraryTrashProvider);
      if (context.mounted) _snack(context, l10n.fmDeletedForever);
    } on AppApiException {
      if (context.mounted) _snack(context, l10n.ctrlFailed);
    }
  }

  Future<bool?> _confirm(
    BuildContext context,
    AppLocalizations l10n, {
    required String title,
    required String body,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.fmHardDelete),
          ),
        ],
      ),
    );
  }
}

class _TrashTile extends StatelessWidget {
  const _TrashTile({
    required this.file,
    required this.onRestore,
    required this.onDelete,
  });

  final TrashFile file;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final meta = <String>[
      formatBytes(file.fileSize),
      if (file.folderName != null) file.folderName!,
    ];
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: ListTile(
        leading: Icon(Icons.insert_drive_file_outlined,
            color: theme.colorScheme.onSurfaceVariant),
        title: Text(file.filename,
            maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(meta.join(' · '), style: theme.textTheme.bodySmall),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: l10n.fmRestore,
              icon: const Icon(Icons.restore_from_trash_outlined),
              onPressed: onRestore,
            ),
            IconButton(
              tooltip: l10n.fmHardDelete,
              icon: Icon(Icons.delete_forever_outlined,
                  color: theme.colorScheme.error),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
