import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/models/project.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../common/api_failure_snack.dart';
import '../common/confirm_dialog.dart';
import '../../providers.dart';
import '../common/format_datetime.dart';
import 'project_common.dart';
import 'project_cover_image.dart';
import 'project_detail_sections.dart';
import 'project_files.dart';
import 'project_form_screen.dart';
import 'projects_providers.dart';

/// Project detail — a single scrolling page (matching the web): header,
/// plates/parts progress, stat cards, notes, linked files, attachments, BOM
/// and the activity timeline.
class ProjectDetailScreen extends ConsumerWidget {
  const ProjectDetailScreen({super.key, required this.projectId});

  final int projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final async = ref.watch(projectDetailProvider(projectId));

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(
          context,
          title: async.valueOrNull?.name ?? l10n.projectsTitle,
          actions: [
            if (async.hasValue) ...[
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: l10n.projectEdit,
                onPressed: () => openProjectEdit(context, async.value!),
              ).tagged('project.edit'),
              _OverflowMenu(project: async.value!),
            ],
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
                  Icon(Icons.cloud_off, size: 48, color: t.textTertiary),
                  const SizedBox(height: 12),
                  Text(
                    err is AppApiException
                        ? err.localized(l10n)
                        : l10n.connectFailed,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: DashTokens.fontUi,
                      color: t.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    style: dashPrimaryButtonStyle(t),
                    onPressed: () => ref
                        .read(projectDetailProvider(projectId).notifier)
                        .refresh(),
                    child: Text(l10n.retry),
                  ).tagged('project.retry'),
                ],
              ),
            ),
          ),
          data: (project) => RefreshIndicator(
            onRefresh: () async {
              // The per-file counts move whenever a print finishes, and they
              // live in their own provider — without this the sets bar would
              // keep its number while everything above it updated.
              ref.invalidate(projectFileProgressProvider(projectId));
              await ref.read(projectDetailProvider(projectId).notifier).refresh();
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _Header(project: project),
                if (project.stats != null)
                  _ProgressCard(stats: project.stats!, project: project),
                if (project.stats != null) _StatCards(stats: project.stats!),
                _NotesSection(project: project),
                ProjectFilesSection(projectId: projectId),
                ProjectAttachmentsSection(project: project),
                ProjectBomSection(projectId: projectId),
                ProjectTimelineSection(projectId: projectId),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Header: cover, name, status, priority, due date, tags, link, parent/children,
/// description.
class _Header extends ConsumerWidget {
  const _Header({required this.project});

  final ProjectResponse project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProjectCoverImage(
                projectId: project.id,
                hasCover: project.hasCover,
                width: 88,
                height: 88,
                borderRadius: BorderRadius.circular(18),
                cacheBust: project.updatedAt,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ProjectColorDot(color: project.color),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            project.name,
                            style: t.display,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ProjectStatusChip(status: project.status),
                        _DashTag(label: projectPriorityLabel(l10n, project.priority)),
                        if (project.dueDateParsed != null)
                          Text(
                            l10n.projectDueOn(formatDate(project.dueDateParsed!)),
                            style: t.monoMicro,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (project.description != null && project.description!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              project.description!,
              style: t.bodySoft,
            ),
          ],
          if (project.url != null && project.url!.isNotEmpty) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () => launchUrl(Uri.parse(project.url!),
                  mode: LaunchMode.externalApplication),
              child: Row(
                children: [
                  Icon(Icons.link, size: 18, color: t.accentGreenInk),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      project.url!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.body.copyWith(color: t.accentGreenInk),
                    ),
                  ),
                ],
              ),
            ).tagged('project.open_url'),
          ],
          if (project.tagList.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final tag in project.tagList) _DashTag(label: tag),
              ],
            ),
          ],
          if (project.parentId != null)
            Material(
              color: Colors.transparent,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.subdirectory_arrow_right, color: t.textSecondary),
                title: Text(
                  project.parentName ?? '#${project.parentId}',
                  style: t.body,
                ),
                onTap: () => context.push('/projects/${project.parentId}'),
              ).tagged('project.parent'),
            ),
          if (project.children.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l10n.projectChildren,
              style: t.bodyBold.copyWith(color: t.textPrimary),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final child in project.children)
                  ActionChip(
                    backgroundColor: t.subCard,
                    side: BorderSide(color: t.subCardBorder),
                    avatar: ProjectColorDot(color: child.color),
                    label: Text(
                      child.name,
                      style: t.label.copyWith(color: t.textPrimary),
                    ),
                    onPressed: () => context.push('/projects/${child.id}'),
                  ).tagged('project.child'),
              ],
            ),
          ],
        ],
      ),
    );
  }

}

/// Neutral pill tag (priority, free-form tags) — same shape family as
/// [ProjectStatusChip] but without a status accent color.
class _DashTag extends StatelessWidget {
  const _DashTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: t.subCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.subCardBorder),
      ),
      child: Text(
        label,
        style: t.micro.copyWith(color: t.textSecondary),
      ),
    );
  }
}

/// Plates + parts progress bars (the project's two target metrics), plus
/// complete sets where the project tracks them.
class _ProgressCard extends ConsumerWidget {
  const _ProgressCard({required this.stats, required this.project});

  final ProjectStats stats;
  final ProjectResponse project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return SectionCard(
      icon: Icons.track_changes_outlined,
      title: l10n.projectStatProgress,
      child: Column(
        children: [
          _ProgressRow(
            label: l10n.projectStatPrints,
            percent: stats.progressPercent ?? 0,
            trailing: stats.remainingPrints == null
                ? null
                : l10n.projectRemainingShort(stats.remainingPrints!),
          ),
          const SizedBox(height: 12),
          _ProgressRow(
            label: l10n.projectStatPartsProgress,
            percent: stats.partsProgressPercent ?? 0,
            trailing: stats.remainingParts == null
                ? null
                : l10n.projectRemainingShort(stats.remainingParts!),
          ),
          ..._setsRow(context, ref, l10n),
        ],
      ),
    );
  }

  /// Complete-sets bar. Needs both halves of a feature that only exists from
  /// 1.2.5.2: a target on the project, and the per-file counts to measure it
  /// against. Either one missing (older server, or the user tracking plates and
  /// parts only) and the row is absent rather than showing an empty bar.
  List<Widget> _setsRow(
      BuildContext context, WidgetRef ref, AppLocalizations l10n) {
    final target = project.targetSets;
    if (target == null || target <= 0) return const [];

    final progress = ref.watch(projectFileProgressProvider(project.id)).valueOrNull;
    final files = ref.watch(projectFilesProvider(project.id)).valueOrNull;
    if (progress == null || files == null || files.isEmpty) return const [];

    final complete = completeSetsFor([for (final f in files) f.id], progress);

    return [
      const SizedBox(height: 12),
      _ProgressRow(
        label: l10n.projectStatSets,
        percent: (complete / target * 100).clamp(0, 100).toDouble(),
        trailing: l10n.projectSetsOfTarget(complete, target),
      ),
    ];
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.label, required this.percent, this.trailing});

  final String label;
  final double percent;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: t.body,
            ),
            Text(
              trailing == null
                  ? '${percent.toStringAsFixed(0)}%'
                  : '${percent.toStringAsFixed(0)}% · $trailing',
              style: t.monoLabel,
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progressFraction(percent),
            minHeight: 8,
            backgroundColor: t.gaugeTrack,
            valueColor: AlwaysStoppedAnimation(t.accentGreen),
          ),
        ),
      ],
    );
  }
}

/// Three headline stat cards: print jobs, print time, filament used (+ extras).
class _StatCards extends StatelessWidget {
  const _StatCards({required this.stats});

  final ProjectStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tiles = <(IconData, String, String)>[
      (
        Icons.view_in_ar_outlined,
        l10n.projectStatPrints,
        '${stats.totalArchives}',
      ),
      (
        Icons.schedule_outlined,
        l10n.projectStatPrintTime,
        '${stats.totalPrintTimeHours.toStringAsFixed(1)} h',
      ),
      (
        Icons.line_weight_outlined,
        l10n.projectStatFilament,
        '${stats.totalFilamentGrams.toStringAsFixed(0)} g',
      ),
      (
        Icons.attach_money_outlined,
        l10n.projectStatCost,
        stats.estimatedCost.toStringAsFixed(2),
      ),
      (
        Icons.bolt_outlined,
        l10n.projectStatEnergy,
        '${stats.totalEnergyKwh.toStringAsFixed(2)} kWh',
      ),
      (
        Icons.checklist_outlined,
        l10n.projectStatBom,
        '${stats.bomCompletedItems}/${stats.bomTotalItems}',
      ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 2.6,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        children: [
          for (final (icon, label, value) in tiles)
            _StatTile(icon: icon, label: label, value: value),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: t.subCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.subCardBorder),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: t.accentGreenInk),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: t.titleMd,
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.micro,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Notes card with inline edit (PATCH notes).
class _NotesSection extends ConsumerWidget {
  const _NotesSection({required this.project});

  final ProjectResponse project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final notes = project.notes;
    final hasNotes = notes != null && notes.isNotEmpty;
    return SectionCard(
      icon: Icons.notes_outlined,
      title: l10n.projectNotes,
      action: TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: t.accentGreenInk),
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: Text(l10n.projectEdit),
        onPressed: () => _editNotes(context, ref),
      ).tagged('project.edit_notes'),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          hasNotes ? notes : l10n.projectNotesEmpty,
          style: t.bodySoft.copyWith(color: hasNotes ? t.textPrimary : t.textTertiary),
        ),
      ),
    );
  }

  Future<void> _editNotes(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final saved = await showDialog<String>(
      context: context,
      builder: (_) => _NotesEditDialog(initial: project.notes ?? ''),
    );
    if (saved == null) return;
    final result = await ref
        .read(projectDetailProvider(project.id).notifier)
        .save(ProjectUpdate(notes: saved));
    messenger.showSnackBar(SnackBar(
      content: Text(result.messageFor(l10n) ?? l10n.projectSaved),
    ));
  }
}

/// Notes edit dialog. A StatefulWidget so it owns/disposes its controller in
/// the State lifecycle — disposing a controller right after `await showDialog`
/// races the dialog's exit animation and corrupts element deactivation.
class _NotesEditDialog extends StatefulWidget {
  const _NotesEditDialog({required this.initial});

  final String initial;

  @override
  State<_NotesEditDialog> createState() => _NotesEditDialogState();
}

class _NotesEditDialogState extends State<_NotesEditDialog> {
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
      title: Text(l10n.projectNotes),
      content: TextField(
        controller: _controller,
        maxLines: 6,
        autofocus: true,
        decoration: InputDecoration(hintText: l10n.projectNotes),
      ).tagged('project_notes.field'),
      actions: [
        logTag(
          'project_notes.cancel',
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        ),
        logTag(
          'project_notes.save',
          FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: Text(l10n.projectSave),
          ),
        ),
      ],
    );
  }
}

/// Overflow menu: export, cover image, save-as-template, delete.
class _OverflowMenu extends ConsumerWidget {
  const _OverflowMenu({required this.project});

  final ProjectResponse project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<String>(
      onSelected: (v) async {
        switch (v) {
          case 'export':
            await _export(context, ref);
          case 'cover':
            await _uploadCover(context, ref);
          case 'cover_delete':
            await _deleteCover(context, ref);
          case 'template':
            await _createTemplate(context, ref);
          case 'delete':
            await _delete(context, ref);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'export',
          child: logTag('project.export', Text(l10n.projectMenuExport)),
        ),
        PopupMenuItem(
          value: 'cover',
          child: logTag('project.cover_upload', Text(l10n.projectCoverUpload)),
        ),
        if (project.hasCover)
          PopupMenuItem(
            value: 'cover_delete',
            child:
                logTag('project.cover_delete', Text(l10n.projectCoverDelete)),
          ),
        PopupMenuItem(
          value: 'template',
          child: logTag(
              'project.create_template', Text(l10n.projectMenuCreateTemplate)),
        ),
        PopupMenuItem(
          value: 'delete',
          child: logTag('project.delete', Text(l10n.projectDelete)),
        ),
      ],
    ).tagged('project.overflow_menu');
  }

  Future<void> _uploadCover(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final picked = await pickSingleFile(
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif'],
    );
    if (picked == null) return;
    try {
      await ref
          .read(projectsRepositoryProvider)
          .uploadCoverImage(project.id, filePath: picked.path, filename: picked.name);
      // `ProjectListResponse` has no `updated_at` to cache-bust the list
      // card's cover URL with, so a same-session reprint of a project whose
      // cover URL is otherwise stable could show the old bitmap from cache —
      // drop the whole image cache instead (cheap; cover changes are rare).
      PaintingBinding.instance.imageCache.clear();
      await ref.read(projectDetailProvider(project.id).notifier).refresh();
      ref.read(projectsListProvider.notifier).refresh();
      messenger.showSnackBar(SnackBar(content: Text(l10n.projectCoverUpdated)));
    } on AppApiException catch (e) {
      showApiFailure(messenger, e, l10n, action: 'project.cover_upload');
    }
  }

  Future<void> _deleteCover(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(projectsRepositoryProvider).deleteCoverImage(project.id);
      PaintingBinding.instance.imageCache.clear();
      await ref.read(projectDetailProvider(project.id).notifier).refresh();
      ref.read(projectsListProvider.notifier).refresh();
      messenger.showSnackBar(SnackBar(content: Text(l10n.projectCoverRemoved)));
    } on AppApiException catch (e) {
      showApiFailure(messenger, e, l10n, action: 'project.cover_delete');
    }
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await ref.read(projectsRepositoryProvider).export(project.id);
      final safeName = project.name.replaceAll(RegExp(r'[^\w\-]+'), '_');
      final path = await saveBytesToFile(
        fileName: '$safeName.zip',
        bytes: bytes,
        dialogTitle: l10n.projectMenuExport,
      );
      if (path == null) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.projectSaveCancelled)));
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(l10n.projectExported(path))));
    } on AppApiException catch (e) {
      showApiFailure(messenger, e, l10n, action: 'project.export');
    }
  }

  Future<void> _createTemplate(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(projectsRepositoryProvider).createTemplate(project.id);
      ref.invalidate(projectTemplatesProvider);
      messenger.showSnackBar(SnackBar(content: Text(l10n.projectTemplateCreated)));
    } on AppApiException catch (e) {
      showApiFailure(messenger, e, l10n, action: 'project.create_template');
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await confirmDialog(
      context,
      title: l10n.projectDeleteTitle,
      message: l10n.projectDeleteBody(project.name),
      confirmLabel: l10n.projectDelete,
      destructive: true,
      id: 'project_delete',
    );
    if (!confirmed) return;
    final result = await ref.read(projectsListProvider.notifier).delete(project.id);
    messenger.showSnackBar(SnackBar(
      content: Text(result.messageFor(l10n) ?? l10n.projectDeleted),
    ));
    if (result.isOk) navigator.pop();
  }
}
