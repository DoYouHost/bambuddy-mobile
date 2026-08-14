import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/server_profile.dart';
import '../../core/models/current_user.dart';
import '../../core/models/pipeline_run.dart';
import '../../core/models/printer.dart';
import '../../core/models/slicer_pipeline.dart';
import '../../providers.dart';

/// Whether the pipeline screens may be offered to this session at all.
///
/// The auth-mode half is not a nicety: `core/auth.py` denies an **API-key
/// session every pipeline permission**, so a key meets nothing but 403s, and
/// `/auth/me` cannot be asked — up to 1.2.5.x it claimed a key was an admin
/// holding everything.
///
/// The permission half stays permissive on an unknown identity, unlike
/// administration: with authentication off the server answers these routes to
/// anybody (`RequirePermissionIfAuthEnabled`).
final canUsePipelinesProvider = Provider<bool>((ref) {
  if (ref.watch(serverProfileProvider)?.authMode == AuthMode.apiKey) {
    return false;
  }
  return ref.watch(permissionProvider(Permissions.pipelinesRead));
});

/// Whether this session may create / edit / delete a pipeline.
final canWritePipelinesProvider = Provider<bool>((ref) =>
    ref.watch(canUsePipelinesProvider) &&
    ref.watch(permissionProvider(Permissions.pipelinesWrite)));

/// Whether this session may dispatch a run — a separate permission server-side
/// because spending filament is not the same trust as authoring the recipe.
final canRunPipelinesProvider = Provider<bool>((ref) =>
    ref.watch(canUsePipelinesProvider) &&
    ref.watch(permissionProvider(Permissions.pipelinesRun)));

/// Whether the connected server has the pipeline routes at all. Probed, not
/// versioned; `false` while loading, so nothing flashes into the drawer and out
/// again.
final pipelinesSupportedProvider = FutureProvider<bool>((ref) async {
  if (!ref.watch(canUsePipelinesProvider)) return false;
  return ref.watch(pipelinesRepositoryProvider).probe();
});

/// Every saved pipeline, newest first.
final pipelinesProvider = FutureProvider.autoDispose<List<SlicerPipeline>>(
  (ref) => ref.watch(pipelinesRepositoryProvider).list(),
);

/// A page of runs, keyed by offset.
final pipelineRunsProvider =
    FutureProvider.autoDispose.family<PipelineRunPage, int>(
  (ref, offset) =>
      ref.watch(pipelinesRepositoryProvider).runs(offset: offset),
);

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
