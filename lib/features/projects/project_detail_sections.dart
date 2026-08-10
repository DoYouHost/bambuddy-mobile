import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/diagnostics/log_tag.dart';
import '../../core/models/library_file.dart';
import '../../core/models/library_folder.dart';
import '../../core/models/project.dart';
import '../../core/models/queue_item.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../files/library_thumbnail.dart';
import '../queue/queue_edit_screen.dart';
import 'project_files.dart';
import 'projects_providers.dart';

String sectionErr(AppApiException e, AppLocalizations l10n) =>
    e.localized(l10n);

/// Card wrapper for a detail section: header (icon + title + optional action)
/// over its body. Matches the web's stacked-card layout.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.action,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        gradient: t.cardGradient,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 19, color: t.accentGreenInk),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: DashTokens.fontUi,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// Green "ghost" action button used in a [SectionCard] header (link folder,
/// upload attachment, add BOM item).
Widget _dashAction({
  required BuildContext context,
  required IconData icon,
  required String label,
  required VoidCallback onPressed,
}) {
  final t = DashTokens.of(context);
  return TextButton.icon(
    style: TextButton.styleFrom(foregroundColor: t.accentGreenInk),
    icon: Icon(icon, size: 18),
    label: Text(label),
    onPressed: onPressed,
  ).tagged('project.section_action');
}

Widget _emptyHint(BuildContext context, String text) {
  final t = DashTokens.of(context);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      text,
      style: TextStyle(
        fontFamily: DashTokens.fontUi,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: t.textTertiary,
      ),
    ),
  );
}

// --- Files section: linked File Manager folders + their printable files ---

class ProjectFilesSection extends ConsumerWidget {
  const ProjectFilesSection({super.key, required this.projectId});

  final int projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final foldersAsync = ref.watch(projectFoldersProvider(projectId));
    final filesAsync = ref.watch(projectFilesProvider(projectId));

    return SectionCard(
      icon: Icons.folder_open_outlined,
      title: l10n.projectTabFiles,
      action: _dashAction(
        context: context,
        icon: Icons.create_new_folder_outlined,
        label: l10n.projectLinkFolder,
        onPressed: () => _linkFolder(context, ref),
      ),
      child: foldersAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(12),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => _emptyHint(
            context, e is AppApiException ? e.localized(l10n) : l10n.connectFailed),
        data: (folders) {
          if (folders.isEmpty) {
            return _emptyHint(context, l10n.projectFilesEmpty);
          }
          final files = filesAsync.valueOrNull ?? const <LibraryFile>[];
          return Column(
            children: [
              for (final folder in folders)
                _FolderTile(
                  folder: folder,
                  files: [for (final f in files) if (f.folderId == folder.id) f],
                  onPrint: (f) => _print(context, ref, f),
                  onUnlink: () => _unlink(context, ref, folder),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(projectFoldersProvider(projectId));
    ref.invalidate(projectFilesProvider(projectId));
  }

  Future<void> _linkFolder(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final linked = (ref.read(projectFoldersProvider(projectId)).valueOrNull ??
            const <LibraryFolder>[])
        .map((f) => f.id)
        .toSet();
    final List<LibraryFolder> candidates;
    try {
      final tree = await ref.read(libraryRepositoryProvider).listFolders();
      candidates = [
        for (final f in _flatten(tree))
          if (!linked.contains(f.id) && f.projectName == null) f,
      ];
    } on AppApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(sectionErr(e, l10n))));
      return;
    }
    if (!context.mounted) return;

    final folderId = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.projectLinkFolder,
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            if (candidates.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.projectNoFoldersToLink),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final f in candidates)
                      ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(f.name),
                        subtitle: Text(l10n.projectFolderFileCount(f.fileCount)),
                        onTap: () => Navigator.pop(ctx, f.id),
                      ).tagged('project.link_folder_option'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    if (folderId == null) return;

    try {
      await ref.read(projectsRepositoryProvider).setFolderProject(folderId, projectId);
      await _refresh(ref);
      ref.invalidate(projectDetailProvider(projectId));
      messenger.showSnackBar(SnackBar(content: Text(l10n.projectFolderLinked)));
    } on AppApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(sectionErr(e, l10n))));
    }
  }

  Future<void> _unlink(
      BuildContext context, WidgetRef ref, LibraryFolder folder) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(projectsRepositoryProvider).setFolderProject(folder.id, null);
      await _refresh(ref);
      ref.invalidate(projectDetailProvider(projectId));
      messenger.showSnackBar(SnackBar(content: Text(l10n.projectFolderUnlinked)));
    } on AppApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(sectionErr(e, l10n))));
    }
  }

  /// Print a project file: the full print form, opened on ASAP. Printer choice
  /// lives in the form, so there is no separate picker or confirm step here.
  Future<void> _print(BuildContext context, WidgetRef ref, LibraryFile file) =>
      openQueueCreate(
        context,
        draft: QueueItem.draft(
          libraryFileId: file.id,
          name: file.displayName,
          thumbnail: file.thumbnailPath,
          slicedForModel: file.slicedForModel,
        ),
        schedule: QueueScheduleType.asap,
      );

  List<LibraryFolder> _flatten(List<LibraryFolder> tree) => [
        for (final f in tree) ...[f, ..._flatten(f.children)],
      ];
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.folder,
    required this.files,
    required this.onPrint,
    required this.onUnlink,
  });

  final LibraryFolder folder;
  final List<LibraryFile> files;
  final ValueChanged<LibraryFile> onPrint;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    return Theme(
      // Remove the default ExpansionTile divider lines for a cleaner card.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: 8, bottom: 8),
        iconColor: t.textSecondary,
        collapsedIconColor: t.textSecondary,
        leading: Icon(Icons.folder_outlined, color: t.accentGreenInk),
        title: Text(
          folder.name,
          style: TextStyle(
            fontFamily: DashTokens.fontUi,
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: t.textPrimary,
          ),
        ),
        subtitle: Text(
          l10n.projectFolderFileCount(folder.fileCount),
          style: TextStyle(
            fontFamily: DashTokens.fontUi,
            fontSize: 12,
            color: t.textTertiary,
          ),
        ),
        trailing: IconButton(
          icon: Icon(Icons.link_off, color: t.textSecondary),
          tooltip: l10n.projectUnlinkFolder,
          onPressed: onUnlink,
        ).tagged('project.unlink_folder'),
        children: [
          if (files.isEmpty)
            _emptyHint(context, l10n.projectFilesEmpty)
          else
            for (final f in files)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: LibraryThumbnail(
                  fileId: f.id,
                  hasThumbnail: f.thumbnailPath != null,
                  size: 44,
                ),
                title: Text(
                  f.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: DashTokens.fontUi,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: t.textPrimary,
                  ),
                ),
                trailing: f.isPrintable
                    ? IconButton(
                        icon: Icon(Icons.print_outlined, color: t.accentGreenInk),
                        tooltip: l10n.fmPrint,
                        onPressed: () => onPrint(f),
                      ).tagged('project.print_file')
                    : null,
              ).tagged('project.file'),
        ],
      ).tagged('project.folder'),
    );
  }
}

// --- Attachments section ---

class ProjectAttachmentsSection extends ConsumerWidget {
  const ProjectAttachmentsSection({super.key, required this.project});

  final ProjectResponse project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final files = project.attachments;
    return SectionCard(
      icon: Icons.attach_file,
      title: l10n.projectTabAttachments,
      action: _dashAction(
        context: context,
        icon: Icons.upload_file,
        label: l10n.projectAttachmentUpload,
        onPressed: () => _upload(context, ref),
      ),
      child: files.isEmpty
          ? _emptyHint(context, l10n.projectAttachmentsEmpty)
          : Column(
              children: [
                for (final name in files)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.insert_drive_file_outlined,
                        color: t.textSecondary),
                    title: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: DashTokens.fontUi,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: t.textPrimary,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.download_outlined,
                              color: t.accentGreenInk),
                          tooltip: l10n.projectAttachmentDownload,
                          onPressed: () => _download(context, ref, name),
                        ).tagged('project.attachment_download'),
                        IconButton(
                          icon: Icon(Icons.delete_outline, color: t.danger),
                          tooltip: l10n.projectAttachmentDelete,
                          onPressed: () => _delete(context, ref, name),
                        ).tagged('project.attachment_delete'),
                      ],
                    ),
                  ).tagged('project.attachment'),
              ],
            ),
    );
  }

  Future<void> _upload(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final picked = await pickSingleFile();
    if (picked == null) return;
    messenger.showSnackBar(SnackBar(content: Text(l10n.projectUploading)));
    try {
      await ref.read(projectsRepositoryProvider).uploadAttachment(
            project.id,
            filePath: picked.path,
            filename: picked.name,
          );
      await ref.read(projectDetailProvider(project.id).notifier).refresh();
      messenger.showSnackBar(SnackBar(content: Text(l10n.projectAttachmentUploaded)));
    } on AppApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(sectionErr(e, l10n))));
    }
  }

  Future<void> _download(BuildContext context, WidgetRef ref, String name) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes =
          await ref.read(projectsRepositoryProvider).downloadAttachment(project.id, name);
      final path = await saveBytesToFile(fileName: name, bytes: bytes);
      if (path == null) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.projectSaveCancelled)));
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(l10n.projectFileSaved(path))));
    } on AppApiException {
      messenger.showSnackBar(SnackBar(content: Text(l10n.projectDownloadFailed)));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, String name) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(projectsRepositoryProvider).deleteAttachment(project.id, name);
      await ref.read(projectDetailProvider(project.id).notifier).refresh();
      messenger.showSnackBar(SnackBar(content: Text(l10n.projectAttachmentDeleted)));
    } on AppApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(sectionErr(e, l10n))));
    }
  }
}

// --- BOM section ---

class ProjectBomSection extends ConsumerWidget {
  const ProjectBomSection({super.key, required this.projectId});

  final int projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(projectBomProvider(projectId));
    return SectionCard(
      icon: Icons.shopping_cart_outlined,
      title: l10n.projectTabBom,
      action: _dashAction(
        context: context,
        icon: Icons.add,
        label: l10n.bomAdd,
        onPressed: () => _editItem(context, ref, null),
      ),
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(12),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => _emptyHint(
            context, e is AppApiException ? e.localized(l10n) : l10n.connectFailed),
        data: (items) => items.isEmpty
            ? _emptyHint(context, l10n.projectBomEmpty)
            : Column(
                children: [for (final i in items) _bomTile(context, ref, i)],
              ),
      ),
    );
  }

  Widget _bomTile(BuildContext context, WidgetRef ref, BomItem item) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final subtitle = <String>[
      '×${item.quantityNeeded}',
      if (item.unitPrice != null) item.unitPrice!.toStringAsFixed(2),
    ].join(' · ');
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      // Completion is derived from quantity_acquired >= quantity_needed, so the
      // checkbox sets acquired to needed (done) or 0 (not done).
      leading: Checkbox(
        value: item.isComplete,
        activeColor: t.accentGreen,
        checkColor: const Color(0xFF0A0C08),
        onChanged: (v) => ref.read(projectBomProvider(projectId).notifier).edit(
              item.id,
              BomItemInput(
                name: item.name,
                quantityAcquired: (v ?? false) ? item.quantityNeeded : 0,
              ),
            ),
      ).tagged('project.bom_done'),
      title: Text(
        item.name,
        style: TextStyle(
          fontFamily: DashTokens.fontUi,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          decoration: item.isComplete ? TextDecoration.lineThrough : null,
          color: item.isComplete ? t.textTertiary : t.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontFamily: DashTokens.fontMono,
          fontSize: 11.5,
          color: t.textTertiary,
        ),
      ),
      trailing: PopupMenuButton<String>(
        icon: Icon(Icons.more_vert, color: t.textSecondary),
        onSelected: (v) {
          if (v == 'edit') _editItem(context, ref, item);
          if (v == 'open' && item.sourcingUrl != null) {
            launchUrl(Uri.parse(item.sourcingUrl!), mode: LaunchMode.externalApplication);
          }
          if (v == 'delete') {
            ref.read(projectBomProvider(projectId).notifier).delete(item.id);
          }
        },
        itemBuilder: (_) => [
          // Tag on the child: a wrapped `PopupMenuItem` is no longer a
          // `PopupMenuEntry`.
          PopupMenuItem(
            value: 'edit',
            child: logTag('bom_menu.edit', Text(l10n.bomEditTitle)),
          ),
          if (item.sourcingUrl != null && item.sourcingUrl!.isNotEmpty)
            PopupMenuItem(
              value: 'open',
              child: logTag('bom_menu.open_url', Text(l10n.bomSourcingUrl)),
            ),
          PopupMenuItem(
            value: 'delete',
            child: logTag('bom_menu.delete', Text(l10n.bomDelete)),
          ),
        ],
      ),
    ).tagged('project.bom_item');
  }

  Future<void> _editItem(BuildContext context, WidgetRef ref, BomItem? item) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final input = await showDialog<BomItemInput>(
      context: context,
      builder: (_) => BomItemDialog(item: item),
    );
    if (input == null) return;
    final notifier = ref.read(projectBomProvider(projectId).notifier);
    final result =
        item == null ? await notifier.add(input) : await notifier.edit(item.id, input);
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(result.messageFor(l10n) ?? l10n.projectSaved),
    ));
  }
}

// --- Timeline section ---

class ProjectTimelineSection extends ConsumerWidget {
  const ProjectTimelineSection({super.key, required this.projectId});

  final int projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final async = ref.watch(projectTimelineProvider(projectId));
    return SectionCard(
      icon: Icons.history,
      title: l10n.projectTabTimeline,
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(12),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => _emptyHint(context, l10n.projectTimelineEmpty),
        data: (events) => events.isEmpty
            ? _emptyHint(context, l10n.projectTimelineEmpty)
            : Column(
                children: [
                  for (final e in events)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_eventIcon(e.eventType), color: t.accentGreenInk),
                      title: Text(
                        e.title,
                        style: TextStyle(
                          fontFamily: DashTokens.fontUi,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: t.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        [
                          if (e.description != null) e.description!,
                          if (e.timestampParsed != null)
                            _fmtDateTime(e.timestampParsed!),
                        ].join('\n'),
                        style: TextStyle(
                          fontFamily: DashTokens.fontMono,
                          fontSize: 11.5,
                          color: t.textTertiary,
                        ),
                      ),
                      isThreeLine: e.description != null,
                    ),
                ],
              ),
      ),
    );
  }

  IconData _eventIcon(String type) {
    final t = type.toLowerCase();
    if (t.contains('complet')) return Icons.check_circle_outline;
    if (t.contains('fail') || t.contains('error')) return Icons.error_outline;
    if (t.contains('print')) return Icons.print_outlined;
    if (t.contains('queue')) return Icons.queue_outlined;
    if (t.contains('creat')) return Icons.add_circle_outline;
    if (t.contains('bom')) return Icons.shopping_cart_outlined;
    return Icons.fiber_manual_record_outlined;
  }

  String _fmtDateTime(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Add / edit dialog for a BOM line item.
class BomItemDialog extends StatefulWidget {
  const BomItemDialog({super.key, this.item});

  final BomItem? item;

  @override
  State<BomItemDialog> createState() => _BomItemDialogState();
}

class _BomItemDialogState extends State<BomItemDialog> {
  late final TextEditingController _name;
  late final TextEditingController _needed;
  late final TextEditingController _price;
  late final TextEditingController _url;
  late final TextEditingController _remarks;

  @override
  void initState() {
    super.initState();
    final i = widget.item;
    _name = TextEditingController(text: i?.name ?? '');
    _needed = TextEditingController(text: (i?.quantityNeeded ?? 1).toString());
    _price = TextEditingController(text: i?.unitPrice?.toString() ?? '');
    _url = TextEditingController(text: i?.sourcingUrl ?? '');
    _remarks = TextEditingController(text: i?.remarks ?? '');
  }

  @override
  void dispose() {
    for (final c in [_name, _needed, _price, _url, _remarks]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.item == null ? l10n.bomAddTitle : l10n.bomEditTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: InputDecoration(labelText: l10n.bomName),
            ).tagged('bom_item.name'),
            TextField(
              controller: _needed,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l10n.bomQtyNeeded),
            ).tagged('bom_item.needed'),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: l10n.bomUnitPrice),
            ).tagged('bom_item.price'),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(labelText: l10n.bomSourcingUrl),
            ).tagged('bom_item.url'),
            TextField(
              controller: _remarks,
              decoration: InputDecoration(labelText: l10n.bomRemarks),
            ).tagged('bom_item.remarks'),
          ],
        ),
      ),
      actions: [
        logTag(
          'bom_item.cancel',
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        ),
        logTag(
          'bom_item.save',
          FilledButton(
            onPressed: () {
              if (_name.text.trim().isEmpty) return;
              final item = widget.item;
              final price = double.tryParse(_price.text.trim().replaceAll(',', '.'));
              final url = _url.text.trim();
              final remarks = _remarks.text.trim();
              Navigator.pop(
                context,
                BomItemInput(
                  name: _name.text.trim(),
                  quantityNeeded: int.tryParse(_needed.text.trim()),
                  unitPrice: price,
                  // Editing an existing value down to empty must actively clear
                  // it server-side (see [BomItemInput]) — a fresh item has
                  // nothing to clear, so these never trigger on create.
                  clearUnitPrice: item?.unitPrice != null && price == null,
                  sourcingUrl: url.isEmpty ? null : url,
                  clearSourcingUrl: (item?.sourcingUrl?.isNotEmpty ?? false) && url.isEmpty,
                  remarks: remarks.isEmpty ? null : remarks,
                  clearRemarks: (item?.remarks?.isNotEmpty ?? false) && remarks.isEmpty,
                ),
              );
            },
            child: Text(l10n.projectSave),
          ),
        ),
      ],
    );
  }
}
