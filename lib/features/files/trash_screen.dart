import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/models/trash_file.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import '../common/confirm_dialog.dart';
import '../common/dash_async.dart';
import '../common/dash_snack.dart';
import '../common/format_bytes.dart';
import '../common/state_views.dart';
import 'file_manager_providers.dart';

/// Library trash: list of deleted files with restore, permanent delete, and empty trash.
class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(libraryTrashProvider);
    final items = async.valueOrNull ?? const <TrashFile>[];

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
  ) async {
    final ok = await confirmDialog(
      context,
      id: 'trash.hard_delete_confirm',
      title: l10n.fmHardDelete,
      message: l10n.fmHardDeleteConfirm(file.filename),
      confirmLabel: l10n.fmHardDelete,
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(libraryRepositoryProvider).hardDelete(file.id);
      ref.invalidate(libraryTrashProvider);
      if (context.mounted) ScaffoldMessenger.of(context).snack(l10n.fmDeletedForever);
    } on AppApiException catch (e) {
      showApiFailure(
        context.mounted ? ScaffoldMessenger.of(context) : null,
        e,
        l10n,
        action: 'trash.delete',
      );
    }
  }

  Future<void> _emptyTrash(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ok = await confirmDialog(
      context,
      id: 'trash.purge_confirm',
      title: l10n.fmEmptyTrash,
      message: l10n.fmEmptyTrashConfirm,
      confirmLabel: l10n.fmHardDelete,
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(libraryRepositoryProvider).emptyTrash();
      ref.invalidate(libraryTrashProvider);
      if (context.mounted) ScaffoldMessenger.of(context).snack(l10n.fmDeletedForever);
    } on AppApiException catch (e) {
      showApiFailure(
        context.mounted ? ScaffoldMessenger.of(context) : null,
        e,
        l10n,
        action: 'trash.purge',
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
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: t.subCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: t.subCardBorder),
        ),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.insert_drive_file_outlined, color: t.textSecondary),
          title: Text(
            file.filename,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.titleSm,
          ),
          subtitle: Text(
            meta.join(' · '),
            style: t.monoLabel,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: l10n.fmRestore,
                icon: Icon(Icons.restore_from_trash_outlined, color: t.accentGreenInk),
                onPressed: onRestore,
              ).tagged('trash.restore'),
              IconButton(
                tooltip: l10n.fmHardDelete,
                icon: Icon(Icons.delete_forever_outlined, color: t.danger),
                onPressed: onDelete,
              ).tagged('trash.delete'),
            ],
          ),
        ).tagged('trash.file'),
      ),
    );
  }
}
