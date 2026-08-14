import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/diagnostics/log_tag.dart';
import '../../core/models/pipeline_run.dart';
import '../../core/models/slicer_pipeline.dart';
import '../../core/theme/dash_theme.dart';
import '../../data/pipelines_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import 'pipeline_eligibility_view.dart';
import 'pipeline_runs_screen.dart';
import 'pipelines_providers.dart';

/// Run a saved pipeline against one file: pick the bundle, say how many copies,
/// read the pre-flight, start.
///
/// Returns true when a run was dispatched.
Future<bool> showPipelineRunScreen(
  BuildContext context, {
  required PipelineSource source,
  required String sourceName,
}) async {
  final started = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) =>
          _PipelineRunScreen(source: source, sourceName: sourceName),
    ),
  );
  return started ?? false;
}

class _PipelineRunScreen extends ConsumerStatefulWidget {
  const _PipelineRunScreen({required this.source, required this.sourceName});

  final PipelineSource source;
  final String sourceName;

  @override
  ConsumerState<_PipelineRunScreen> createState() => _PipelineRunScreenState();
}

class _PipelineRunScreenState extends ConsumerState<_PipelineRunScreen> {
  SlicerPipeline? _pipeline;
  int _copies = 1;
  bool _checking = false;
  bool _starting = false;
  EligibilityReport? _report;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final pipelines = ref.watch(pipelinesProvider).valueOrNull ?? const [];
    final maxCopies = ref.watch(pipelineMaxCopiesProvider).valueOrNull ?? 50;
    final report = _report;

    // Force is only offered once the server has actually refused: a blind
    // "run anyway" before the pre-flight would skip the one check that tells
    // the operator which printer is going to reject the job.
    final blocked = report != null && !report.ok;
    final canStart = _pipeline != null &&
        _pipeline!.isRunnable &&
        !_checking &&
        !_starting;

    return Scaffold(
      appBar: dashAppBar(context, title: l10n.pipelineRun),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  Text(widget.sourceName,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: const Icon(Icons.account_tree_outlined),
                      title: Text(l10n.pipelineSection,
                          style: theme.textTheme.labelMedium),
                      subtitle: Text(
                        _pipeline?.name ??
                            (pipelines.isEmpty
                                ? l10n.pipelineApplyEmpty
                                : l10n.pipelineApply),
                        style: theme.textTheme.bodyMedium,
                      ),
                      trailing: pipelines.isEmpty
                          ? null
                          : const Icon(Icons.chevron_right),
                      enabled: pipelines.isNotEmpty && !_starting,
                      onTap: pipelines.isEmpty || _starting
                          ? null
                          : () => _pick(pipelines),
                    ).tagged('pipeline_run.pick'),
                  ),
                  // A pipeline saved from the slice form has no target yet, and
                  // the server would answer `printer_not_set` / `class_not_set`.
                  // Saying so here points at the edit screen instead.
                  if (_pipeline != null && !_pipeline!.isRunnable)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 18, color: theme.colorScheme.tertiary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(l10n.pipelineNeedsTarget,
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.tertiary)),
                          ),
                        ],
                      ),
                    ),
                  if (_pipeline != null && _pipeline!.isRunnable)
                    _copiesCard(l10n, theme, maxCopies),
                  if (_checking)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (report != null && !_checking)
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: EligibilityView(report: report),
                      ),
                    ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: _starting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.play_arrow_rounded),
                    label: Text(blocked
                        ? l10n.pipelineRunAnyway
                        : l10n.pipelineRunStart),
                    style: blocked
                        ? FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.error,
                            foregroundColor: theme.colorScheme.onError,
                          )
                        : null,
                    onPressed: canStart ? () => _start(force: blocked) : null,
                  ).tagged('pipeline_run.start'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _copiesCard(AppLocalizations l10n, ThemeData theme, int maxCopies) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.filter_none_rounded),
        title: Text(l10n.pipelineRunCopies, style: theme.textTheme.labelMedium),
        subtitle: Text(
          _copies >= maxCopies
              ? l10n.pipelineRunMaxCopies(maxCopies)
              : '$_copies',
          style: theme.textTheme.bodyMedium,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            logTag(
              'pipeline_run.copies_less',
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: _copies > 1 && !_starting
                    ? () => setState(() => _copies--)
                    : null,
              ),
            ),
            Text('$_copies', style: theme.textTheme.titleMedium),
            logTag(
              'pipeline_run.copies_more',
              IconButton(
                icon: const Icon(Icons.add),
                // The ceiling is a 422 server-side rather than a clamp, so the
                // stepper stops at it instead of sending a doomed request.
                onPressed: _copies < maxCopies && !_starting
                    ? () => setState(() => _copies++)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(List<SlicerPipeline> pipelines) async {
    final picked = await showModalBottomSheet<SlicerPipeline>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _RunPipelinePicker(pipelines: pipelines),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _pipeline = picked;
      _report = null;
    });
    if (picked.isRunnable) await _check();
  }

  /// Pre-flight, run as soon as a pipeline is chosen so the operator reads the
  /// problems before reaching for the button rather than after being refused.
  Future<void> _check() async {
    final pipeline = _pipeline;
    if (pipeline == null) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _checking = true);
    try {
      final report = await ref
          .read(pipelinesRepositoryProvider)
          .checkEligibility(pipeline.id, source: widget.source);
      if (!mounted) return;
      setState(() => _report = report);
    } on AppApiException catch (e) {
      showApiFailure(mounted ? messenger : null, e, l10n,
          action: 'pipeline_run.check');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _start({required bool force}) async {
    final pipeline = _pipeline;
    if (pipeline == null) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _starting = true);
    try {
      await ref.read(pipelinesRepositoryProvider).run(
            pipeline.id,
            source: widget.source,
            copies: _copies,
            force: force,
          );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.pipelineRunStarted)));
      navigator.pop(true);
      navigator.push(
        MaterialPageRoute(builder: (_) => const PipelineRunsScreen()),
      );
    } on PipelineNotEligible catch (e) {
      // The pre-flight passed a moment ago and the dispatch disagreed — a
      // printer went offline in between, most likely. Show what changed and
      // leave the button on "run anyway".
      if (!mounted) return;
      setState(() {
        _report = e.report;
        _starting = false;
      });
    } on AppApiException catch (e) {
      if (mounted) setState(() => _starting = false);
      showApiFailure(mounted ? messenger : null, e, l10n,
          action: 'pipeline_run.start');
    }
  }
}

/// Pipelines to run with. An untargeted one stays selectable — picking it is
/// how the operator finds out it needs an edit, and the screen says so.
class _RunPipelinePicker extends StatelessWidget {
  const _RunPipelinePicker({required this.pipelines});

  final List<SlicerPipeline> pipelines;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (ctx, controller) => ListView.builder(
        controller: controller,
        itemCount: pipelines.length,
        itemBuilder: (ctx, i) {
          final p = pipelines[i];
          return ListTile(
            title: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: p.isRunnable
                ? Text(
                    p.targetKind == PipelineTargetKind.printerClass
                        ? l10n.pipelineRunOnClass(p.targetModelClass ?? '')
                        : l10n.pipelineRunOnPrinter('#${p.targetPrinterId}'),
                    style: theme.textTheme.bodySmall,
                  )
                : Text(l10n.pipelineNoTargetChip,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.tertiary)),
            onTap: () => Navigator.pop(ctx, p),
          ).tagged('pipeline_run.option');
        },
      ),
    );
  }
}
