import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/models/project.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../common/state_views.dart';
import 'project_common.dart';
import 'project_cover_image.dart';
import 'project_files.dart';
import 'project_form_screen.dart';
import 'projects_providers.dart';

/// Projects list (full-screen, pushed from the dashboard drawer). Status filter,
/// pull-to-refresh, cards with cover/progress/counts. FAB → create form.
class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final async = ref.watch(projectsListProvider);
    final filter = ref.watch(projectStatusFilterProvider);

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(
          context,
          title: l10n.projectsTitle,
          actions: [
            PopupMenuButton<String?>(
              icon: Icon(Icons.filter_list, color: t.textSecondary),
              tooltip: l10n.projectStatus,
              initialValue: filter,
              onSelected: (v) =>
                  ref.read(projectStatusFilterProvider.notifier).state =
                      v == '' ? null : v,
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: '',
                  child:
                      logTag('projects.filter_all', Text(l10n.projectsFilterAll)),
                ),
                // Named per value: the statuses are a fixed server-side list,
                // and which one was filtered on is the point of the record.
                for (final s in projectStatusValues)
                  PopupMenuItem(
                    value: s,
                    child: logTag('projects.filter_status.$s',
                        Text(projectStatusLabel(l10n, s))),
                  ),
              ],
            ).tagged('projects.filter_menu'),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: t.textSecondary),
              onSelected: (v) {
                if (v == 'import') _importProject(context, ref);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'import',
                  child:
                      logTag('projects.import', Text(l10n.projectMenuImport)),
                ),
              ],
            ).tagged('projects.overflow_menu'),
          ],
        ),
        floatingActionButton: logTag(
          'projects.create',
          FloatingActionButton.extended(
            backgroundColor: t.accentGreen,
            foregroundColor: const Color(0xFF0A0C08),
            onPressed: () => _openCreate(context),
            icon: const Icon(Icons.add),
            label: Text(l10n.projectCreate),
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
            onRetry: () => ref.read(projectsListProvider.notifier).refresh(),
          ),
          data: (projects) => RefreshIndicator(
            onRefresh: () => ref.read(projectsListProvider.notifier).refresh(),
            child: projects.isEmpty
                ? EmptyStateView(
                    message: l10n.projectsEmpty,
                    icon: Icons.folder_special_outlined,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                    itemCount: projects.length,
                    itemBuilder: (_, i) => _ProjectCard(
                      project: projects[i],
                      onTap: () => context.push('/projects/${projects[i].id}'),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _openCreate(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ProjectFormScreen()),
      );

  Future<void> _importProject(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final picked = await pickSingleFile();
    if (picked == null) return;
    messenger.showSnackBar(SnackBar(content: Text(l10n.projectUploading)));
    try {
      await ref.read(projectsRepositoryProvider).importFile(
            filePath: picked.path,
            filename: picked.name,
          );
      await ref.read(projectsListProvider.notifier).refresh();
      messenger.showSnackBar(SnackBar(content: Text(l10n.projectImported)));
    } on AppApiException {
      messenger.showSnackBar(SnackBar(content: Text(l10n.projectImportFailed)));
    }
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.onTap});

  final ProjectListResponse project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final fraction = progressFraction(project.progressPercent);
    final counts = <String>[
      '${l10n.projectStatCompleted} ${project.completedCount}',
      if (project.failedCount > 0) '${l10n.projectStatFailed} ${project.failedCount}',
      if (project.queueCount > 0) '${l10n.projectStatQueued} ${project.queueCount}',
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: logTag(
          'projects.card',
          InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: t.cardGradient,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: t.cardBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProjectCoverImage(
                    projectId: project.id,
                    hasCover: project.hasCover,
                    width: 64,
                    height: 64,
                    borderRadius: BorderRadius.circular(16),
                    cacheBust: project.createdAt,
                  ),
                  const SizedBox(width: 12),
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
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.titleMd,
                              ),
                            ),
                            ProjectStatusChip(status: project.status),
                          ],
                        ),
                        if (project.description != null &&
                            project.description!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              project.description!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: t.label.copyWith(color: t.textSecondary),
                            ),
                          ),
                        const SizedBox(height: 8),
                        if (project.progressPercent != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: fraction,
                              minHeight: 6,
                              backgroundColor: t.gaugeTrack,
                              valueColor: AlwaysStoppedAnimation(t.accentGreen),
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                        Text(
                          counts.join(' · '),
                          style: t.monoLabel,
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
