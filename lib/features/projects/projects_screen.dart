import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/project.dart';
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
    final async = ref.watch(projectsListProvider);
    final filter = ref.watch(projectStatusFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.projectsTitle),
        actions: [
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            tooltip: l10n.projectStatus,
            initialValue: filter,
            onSelected: (v) =>
                ref.read(projectStatusFilterProvider.notifier).state =
                    v == '' ? null : v,
            itemBuilder: (_) => [
              PopupMenuItem(value: '', child: Text(l10n.projectsFilterAll)),
              for (final s in projectStatusValues)
                PopupMenuItem(value: s, child: Text(projectStatusLabel(l10n, s))),
            ],
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'import') _importProject(context, ref);
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'import', child: Text(l10n.projectMenuImport)),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreate(context),
        icon: const Icon(Icons.add),
        label: Text(l10n.projectCreate),
      ),
      body: async.when(
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => AsyncErrorView(
          message: err is AppApiException ? err.localized(l10n) : l10n.connectFailed,
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
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final fraction = progressFraction(project.progressPercent);
    final counts = <String>[
      '${l10n.projectStatCompleted} ${project.completedCount}',
      if (project.failedCount > 0) '${l10n.projectStatFailed} ${project.failedCount}',
      if (project.queueCount > 0) '${l10n.projectStatQueued} ${project.queueCount}',
    ];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProjectCoverImage(
                projectId: project.id,
                hasCover: project.hasCover,
                width: 64,
                height: 64,
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
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                          style: theme.textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (project.progressPercent != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: fraction,
                          minHeight: 6,
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      counts.join(' · '),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
