import 'package:app_util/app_util.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app_diagnostics/app_diagnostics.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/models/trash_file.dart';
import '../../core/theme/dash_theme.dart';
import '../../data/library_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import '../common/dash_async.dart';
import 'file_manager_providers.dart';

/// Library trash: list of deleted files with restore, permanent delete, and empty trash.
class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(libraryTrashProvider);
    final items = async.value ?? const <TrashFile>[];

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(
          context,
          title: l10n.fmTrashTitle,
          actions: [
            logTag(
              'trash.purge',
              IconButton(
                tooltip: l10n.fmEmptyTrash,
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: items.isEmpty
                    ? null
                    : () => _emptyTrash(context, ref, l10n),
              ),
            ),
          ],
        ),
        body: dashAsync(
          context,
          async,
          onRetry: () => ref.invalidate(libraryTrashProvider),
          skipLoadingOnRefresh: false,
          data: (items) => RefreshIndicator(
            onRefresh: () => ref.refresh(libraryTrashProvider.future),
            child: items.isEmpty
                ? EmptyStateView(
                    message: l10n.fmTrashEmpty,
                    icon: Icons.delete_outline,
                  )
                : ListView.builder(
                    padding: withSystemNavInset(
                      context,
                      const EdgeInsets.symmetric(vertical: DashSpace.sm),
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) => _TrashTile(
                      file: items[i],
                      onRestore: () => _restore(context, ref, l10n, items[i]),
                      onDelete: () => _hardDelete(context, ref, l10n, items[i]),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

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
      if (context.mounted) ScaffoldMessenger.of(context).snack(l10n.fmRestored);
    } on AppApiException catch (e) {
      showApiFailure(
        context.mounted ? ScaffoldMessenger.of(context) : null,
        e,
        l10n,
        action: 'trash.restore',
      );
    }
  }

  Future<void> _hardDelete(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    TrashFile file,
  ) => _purge(
    context,
    ref,
    l10n,
    id: 'trash.hard_delete_confirm',
    title: l10n.fmHardDelete,
    message: l10n.fmHardDeleteConfirm(file.filename),
    action: 'trash.delete',
    write: (repo) => repo.hardDelete(file.id),
  );

  Future<void> _emptyTrash(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) => _purge(
    context,
    ref,
    l10n,
    id: 'trash.purge_confirm',
    title: l10n.fmEmptyTrash,
    message: l10n.fmEmptyTrashConfirm,
    action: 'trash.purge',
    write: (repo) => repo.emptyTrash(),
  );

  /// Asks, deletes for good through [write], and says so; the trash reloads.
  Future<void> _purge(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n, {
    required String id,
    required String title,
    required String message,
    required String action,
    required Future<void> Function(LibraryRepository repo) write,
  }) async {
    final ok = await confirmDialog(
      context,
      id: id,
      title: title,
      message: message,
      confirmLabel: l10n.fmHardDelete,
      destructive: true,
    );
    if (!ok) return;
    try {
      await write(ref.read(libraryRepositoryProvider));
      ref.invalidate(libraryTrashProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).snack(l10n.fmDeletedForever);
      }
    } on AppApiException catch (e) {
      showApiFailure(
        context.mounted ? ScaffoldMessenger.of(context) : null,
        e,
        l10n,
        action: action,
      );
    }
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
    final t = DashTokens.of(context);
    final meta = <String>[
      formatBytes(file.fileSize),
      if (file.folderName != null) file.folderName!,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DashSpace.gutter,
        0,
        DashSpace.gutter,
        DashSpace.sm,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DashSpace.md,
          vertical: DashSpace.sm,
        ),
        decoration: t.subCardBox(DashRadius.xl),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.insert_drive_file_outlined,
            color: t.textSecondary,
          ),
          title: Text(
            file.filename,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.titleSm,
          ),
          subtitle: Text(meta.join(' · '), style: t.monoLabel),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: l10n.fmRestore,
                icon: Icon(
                  Icons.restore_from_trash_outlined,
                  color: t.accentGreenInk,
                ),
                onPressed: onRestore,
              ).tagged('trash.restore'),
              IconButton(
                tooltip: l10n.fmHardDelete,
                icon: Icon(Icons.delete_forever_outlined, color: t.dangerInk),
                onPressed: onDelete,
              ).tagged('trash.delete'),
            ],
          ),
        ).tagged('trash.file'),
      ),
    );
  }
}
