import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/server_profile.dart';
import '../../core/models/current_user.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/models/pipeline_run.dart';
import '../../core/models/printer.dart';
import '../../core/models/slicer_pipeline.dart';
import '../../data/pipelines_repository.dart';
import '../../providers.dart';
import '../dashboard/ws_providers.dart';

/// What `/auth/me` *claims* about reading pipelines — permissive on an unknown
/// identity, like every [permissionProvider]. Not gated on the auth mode: since
/// server 1.2.5.3 an API key holds this one, and a key on an older server meets
/// a 403 that [pipelinesSupportedProvider] records instead of a version guess.
final canUsePipelinesProvider = Provider<bool>(
  (ref) => ref.watch(permissionProvider(Permissions.pipelinesRead)),
);

/// Whether the connected server has the pipeline routes and answers them to
/// this session. Probed, not versioned; `false` while loading, so nothing
/// flashes into the drawer and out again.
final pipelinesSupportedProvider = FutureProvider<bool>((ref) async {
  if (!ref.watch(canUsePipelinesProvider)) return false;
  return ref.watch(pipelinesRepositoryProvider).probe();
});

/// Whether this session may create / edit / delete a pipeline, or clear run
/// history. **An API-key session never may:** `PIPELINES_WRITE` is outside the
/// allowlist in `core/auth.py`, which is allowlist-only, so it is a 403 on every
/// version — and `/auth/me` claimed the opposite up to 1.2.5.x. Decided on the
/// auth mode for the same reason [identifiedPermissionProvider] is.
final canWritePipelinesProvider = FutureProvider<bool>((ref) async {
  if (ref.watch(serverProfileProvider)?.authMode == AuthMode.apiKey) {
    return false;
  }
  if (!ref.watch(permissionProvider(Permissions.pipelinesWrite))) return false;
  // Through the probe: the list route is what settles presence for all three.
  if (!await ref.watch(pipelinesSupportedProvider.future)) return false;
  return ref.watch(pipelinesRepositoryProvider).canWrite;
});

/// Whether this session may dispatch, cancel or retry a run. Offered to an API
/// key, unlike authoring — `PIPELINES_RUN` maps to `can_queue` **and**
/// `can_manage_library`, both, because a run slices into the library and then
/// queues prints. A key holding one of the two is refused.
final canRunPipelinesProvider = FutureProvider<bool>((ref) async {
  if (!ref.watch(permissionProvider(Permissions.pipelinesRun))) return false;
  // See [canWritePipelinesProvider]; the archive and file-manager entry points
  // reach this without ever having listed a pipeline.
  if (!await ref.watch(pipelinesSupportedProvider.future)) return false;
  return ref.watch(pipelinesRepositoryProvider).canRun;
});

/// Every saved pipeline, newest first.
final pipelinesProvider = FutureProvider.autoDispose<List<SlicerPipeline>>(
  (ref) => ref.watch(pipelinesRepositoryProvider).list(),
);

/// What the runs dashboard is narrowed to. `autoDispose`, so leaving the screen
/// clears it — a filter the user cannot see must not still be hiding runs.
final pipelineRunFilterProvider =
    NotifierProvider.autoDispose<PipelineRunFilterNotifier, PipelineRunFilter>(
  PipelineRunFilterNotifier.new,
);

class PipelineRunFilterNotifier extends AutoDisposeNotifier<PipelineRunFilter> {
  @override
  PipelineRunFilter build() => const PipelineRunFilter();

  void replace(PipelineRunFilter filter) => state = filter;

  void clear() => state = const PipelineRunFilter();
}

/// The pages loaded so far, plus how many the filter matches in total.
class PipelineRunsView {
  const PipelineRunsView({
    this.runs = const [],
    this.total = 0,
    this.loadingMore = false,
  });

  final List<PipelineRun> runs;

  /// Every run the filter matches server-side, not just the loaded ones.
  final int total;

  /// A `loadMore` in flight — the spinner goes at the end of the list, not over
  /// the rows already read.
  final bool loadingMore;

  bool get hasMore => runs.length < total;

  PipelineRunsView copyWith({
    List<PipelineRun>? runs,
    int? total,
    bool? loadingMore,
  }) =>
      PipelineRunsView(
        runs: runs ?? this.runs,
        total: total ?? this.total,
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

/// Page 0 on build, appended by [loadMore], rebuilt on a filter change.
final pipelineRunsProvider = AsyncNotifierProvider.autoDispose<
    PipelineRunsNotifier, PipelineRunsView>(PipelineRunsNotifier.new);

class PipelineRunsNotifier
    extends AutoDisposeAsyncNotifier<PipelineRunsView> {
  @override
  Future<PipelineRunsView> build() async {
    // Watched, not read: changing a filter has to start the list over, since
    // `total` and the offsets both describe one filtered set.
    final filter = ref.watch(pipelineRunFilterProvider);

    // The push half of the refresh; [WsPipelineRunUpdated] says why the
    // screen's timer is still the other half. Subscribed before the first fetch
    // so a frame arriving mid-request is not lost, and guarded because this
    // list is REST: `wsClientProvider` throws without a server profile, and a
    // socket that cannot be built must cost the pushes, not the runs.
    try {
      final sub = ref
          .watch(wsClientProvider)
          .pipelineRunUpdates
          .listen((frame) => patch(PipelineRun.fromJson(frame.run)));
      ref.onDispose(sub.cancel);
    } on StateError {
      // No profile: nothing to subscribe to, and nothing to report either.
    }

    final page = await ref
        .read(pipelinesRepositoryProvider)
        .runs(offset: 0, filter: filter);
    return PipelineRunsView(runs: page.runs, total: page.total);
  }

  /// Append the next page. A no-op while one is in flight or everything is
  /// loaded, so a scroll notification firing twice cannot ask twice.
  Future<void> loadMore() async {
    final view = state.valueOrNull;
    if (view == null || view.loadingMore || !view.hasMore) return;
    state = AsyncData(view.copyWith(loadingMore: true));
    try {
      final page = await ref.read(pipelinesRepositoryProvider).runs(
            offset: view.runs.length,
            filter: ref.read(pipelineRunFilterProvider),
          );
      // `total` from the same query, so runs cleared between the two requests
      // shrink the count instead of stranding the footer.
      state = AsyncData(PipelineRunsView(
        runs: [...view.runs, ...page.runs],
        total: page.total,
      ));
    } on AppApiException {
      // Only the spinner goes: a failed page must not empty the list the user
      // was reading. Thrown on, because a press deserves an answer.
      state = AsyncData(view.copyWith(loadingMore: false));
      rethrow;
    }
  }

  /// Re-read the window on screen in one request, keeping the scroll position.
  ///
  /// The route caps `limit` at 100 silently, so a longer window is refreshed
  /// only as far as the cap — acceptable because the runs that move are the
  /// newest, which are on the first page.
  ///
  /// Never throws: the caller is a timer, where an escaping exception is an
  /// unhandled async error with nothing waiting to show it. Answers `false`
  /// instead, leaves the rows alone, and the next tick tries again.
  Future<bool> refreshLoaded() async {
    final loaded = state.valueOrNull?.runs.length ?? 0;
    try {
      final page = await ref.read(pipelinesRepositoryProvider).runs(
            limit: loaded.clamp(
              PipelinesRepository.pageSize,
              PipelinesRepository.maxPageSize,
            ),
            offset: 0,
            filter: ref.read(pipelineRunFilterProvider),
          );
      state = AsyncData(PipelineRunsView(runs: page.runs, total: page.total));
      return true;
    } on AppApiException {
      return false;
    }
  }

  /// Replace one run in place — what a `pipeline_run_updated` push carries. A
  /// run the page does not hold is ignored rather than prepended: where it
  /// belongs depends on the filter, which one frame cannot answer.
  void patch(PipelineRun run) {
    final view = state.valueOrNull;
    if (view == null) return;
    final at = view.runs.indexWhere((r) => r.id == run.id);
    if (at < 0) return;
    final runs = [...view.runs];
    runs[at] = run;
    state = AsyncData(view.copyWith(runs: runs));
  }
}

/// One run, for the detail sheet's poll.
final pipelineRunProvider =
    FutureProvider.autoDispose.family<PipelineRun, int>(
  (ref, runId) => ref.watch(pipelinesRepositoryProvider).runById(runId),
);

/// Every printer, for the "specific printer" target picker.
final pipelineTargetPrintersProvider =
    FutureProvider.autoDispose<List<Printer>>((ref) async {
  final all = await ref.watch(printersRepositoryProvider).fetchAll();
  return [for (final p in all) p.printer];
});

/// The distinct printer models installed here, for the "printer class" picker.
///
/// **Verbatim, not normalised**, so this cannot reuse
/// `ownedPrinterCodesProvider`: the server matches a class with a plain
/// `Printer.model == target_model_class` (`pipeline_eligibility.py`), and an
/// upper-cased value simply matches nothing.
final pipelinePrinterClassesProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  final printers = await ref.watch(pipelineTargetPrintersProvider.future);
  final models = <String>{
    for (final p in printers)
      if (p.model != null && p.model!.isNotEmpty) p.model!,
  };
  return models.toList()..sort();
});
