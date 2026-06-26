import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/library_file.dart';
import '../../core/models/library_folder.dart';
import '../../core/models/project.dart';
import '../../core/models/queue_item.dart';
import '../../providers.dart';

/// Result of a project mutation returned to the widget (notifier has no
/// [BuildContext]; the screen shows the SnackBar). 403 → forbidden.
enum ProjectActionResult { ok, forbidden, error }

ProjectActionResult _mapError(Object e) {
  if (e is AuthException && e.code == AppErrorCode.forbidden) {
    return ProjectActionResult.forbidden;
  }
  return ProjectActionResult.error;
}

/// Active status filter for the projects list (`null` = all).
final projectStatusFilterProvider = StateProvider<String?>((_) => null);

final projectsListProvider = AutoDisposeAsyncNotifierProvider<
    ProjectsListNotifier, List<ProjectListResponse>>(ProjectsListNotifier.new);

/// Projects list with optional status filter. Rebuilds on profile or filter
/// change. Delete is optimistic; create just refreshes (server computes stats).
class ProjectsListNotifier
    extends AutoDisposeAsyncNotifier<List<ProjectListResponse>> {
  @override
  Future<List<ProjectListResponse>> build() async {
    ref.watch(serverProfileProvider);
    final status = ref.watch(projectStatusFilterProvider);
    return ref.read(projectsRepositoryProvider).list(status: status);
  }

  Future<void> refresh() async {
    state = const AsyncValue<List<ProjectListResponse>>.loading()
        .copyWithPrevious(state);
    state = await AsyncValue.guard(
      () => ref.read(projectsRepositoryProvider).list(
            status: ref.read(projectStatusFilterProvider),
          ),
    );
  }

  /// Optimistic delete: remove locally, call server, restore on failure.
  Future<ProjectActionResult> delete(int id) async {
    final previous = state.valueOrNull;
    if (previous != null) {
      state = AsyncValue.data([
        for (final p in previous)
          if (p.id != id) p,
      ]);
    }
    try {
      await ref.read(projectsRepositoryProvider).delete(id);
      return ProjectActionResult.ok;
    } on AppApiException catch (e) {
      if (previous != null) state = AsyncValue.data(previous);
      return _mapError(e);
    }
  }
}

/// Project templates (for "create from template"). Invalidated on changes.
final projectTemplatesProvider =
    FutureProvider.autoDispose<List<ProjectListResponse>>(
  (ref) => ref.watch(projectsRepositoryProvider).listTemplates(),
);

final projectDetailProvider = AutoDisposeAsyncNotifierProviderFamily<
    ProjectDetailNotifier, ProjectResponse, int>(ProjectDetailNotifier.new);

/// Full project detail keyed by id. Refresh after edits (stats recompute server-side).
class ProjectDetailNotifier
    extends AutoDisposeFamilyAsyncNotifier<ProjectResponse, int> {
  @override
  Future<ProjectResponse> build(int arg) async {
    ref.watch(serverProfileProvider);
    return ref.read(projectsRepositoryProvider).get(arg);
  }

  Future<void> refresh() async {
    state = const AsyncValue<ProjectResponse>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard(
      () => ref.read(projectsRepositoryProvider).get(arg),
    );
  }

  /// PATCH the project and replace state with the server response.
  Future<ProjectActionResult> save(ProjectUpdate body) async {
    try {
      final updated =
          await ref.read(projectsRepositoryProvider).update(arg, body);
      state = AsyncValue.data(updated);
      return ProjectActionResult.ok;
    } on AppApiException catch (e) {
      return _mapError(e);
    }
  }
}

final projectArchivesProvider = AutoDisposeAsyncNotifierProviderFamily<
    ProjectArchivesNotifier, List<ArchivePreview>, int>(
  ProjectArchivesNotifier.new,
);

/// Archives linked to a project, with add/remove that also refresh the detail
/// (counts/stats change). Keyed by project id.
class ProjectArchivesNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<ArchivePreview>, int> {
  @override
  Future<List<ArchivePreview>> build(int arg) async {
    ref.watch(serverProfileProvider);
    return ref.read(projectsRepositoryProvider).archives(arg);
  }

  Future<void> refresh() async {
    state = const AsyncValue<List<ArchivePreview>>.loading()
        .copyWithPrevious(state);
    state = await AsyncValue.guard(
      () => ref.read(projectsRepositoryProvider).archives(arg),
    );
  }

  Future<ProjectActionResult> add(List<int> archiveIds) =>
      _mutate(() => ref.read(projectsRepositoryProvider).addArchives(arg, archiveIds));

  Future<ProjectActionResult> remove(int archiveId) =>
      _mutate(() => ref.read(projectsRepositoryProvider).removeArchives(arg, [archiveId]));

  Future<ProjectActionResult> _mutate(Future<void> Function() action) async {
    try {
      await action();
      await refresh();
      ref.invalidate(projectDetailProvider(arg));
      return ProjectActionResult.ok;
    } on AppApiException catch (e) {
      return _mapError(e);
    }
  }
}

final projectBomProvider = AutoDisposeAsyncNotifierProviderFamily<
    ProjectBomNotifier, List<BomItem>, int>(ProjectBomNotifier.new);

/// BOM items for a project with full CRUD. Mutations refresh the list and the
/// detail (BOM totals feed project stats). Keyed by project id.
class ProjectBomNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<BomItem>, int> {
  @override
  Future<List<BomItem>> build(int arg) async {
    ref.watch(serverProfileProvider);
    return ref.read(projectsRepositoryProvider).bom(arg);
  }

  Future<void> refresh() async {
    state =
        const AsyncValue<List<BomItem>>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard(
      () => ref.read(projectsRepositoryProvider).bom(arg),
    );
  }

  Future<ProjectActionResult> add(BomItemInput body) =>
      _mutate(() => ref.read(projectsRepositoryProvider).addBomItem(arg, body));

  Future<ProjectActionResult> edit(int itemId, BomItemInput body) => _mutate(
      () => ref.read(projectsRepositoryProvider).updateBomItem(arg, itemId, body));

  Future<ProjectActionResult> delete(int itemId) =>
      _mutate(() => ref.read(projectsRepositoryProvider).deleteBomItem(arg, itemId));

  Future<ProjectActionResult> _mutate(Future<void> Function() action) async {
    try {
      await action();
      await refresh();
      ref.invalidate(projectDetailProvider(arg));
      return ProjectActionResult.ok;
    } on AppApiException catch (e) {
      return _mapError(e);
    }
  }
}

/// Queue items linked to a project (read-only list).
final projectQueueProvider =
    FutureProvider.autoDispose.family<List<QueueItem>, int>(
  (ref, projectId) =>
      ref.watch(projectsRepositoryProvider).queue(projectId),
);

/// Project timeline events (read-only list).
final projectTimelineProvider =
    FutureProvider.autoDispose.family<List<TimelineEvent>, int>(
  (ref, projectId) =>
      ref.watch(projectsRepositoryProvider).timeline(projectId),
);

/// Printable library files linked to the project (via linked folders).
final projectFilesProvider =
    FutureProvider.autoDispose.family<List<LibraryFile>, int>(
  (ref, projectId) => ref.watch(projectsRepositoryProvider).files(projectId),
);

/// Folders linked to the project (File Manager folders with `project_id`).
final projectFoldersProvider =
    FutureProvider.autoDispose.family<List<LibraryFolder>, int>(
  (ref, projectId) =>
      ref.watch(projectsRepositoryProvider).linkedFolders(projectId),
);
