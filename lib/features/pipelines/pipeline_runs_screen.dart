
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/diagnostics/log_tag.dart';
import '../../core/models/pipeline_run.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import '../common/confirm_dialog.dart';
import '../common/dash_async.dart';
import '../common/state_views.dart';
import 'pipeline_run_filter_sheet.dart';
import 'pipeline_run_status_labels.dart';
import 'pipelines_providers.dart';

/// Opens the dashboard, optionally already narrowed — how the pipeline card
/// shows one pipeline's history.
///
/// The seed goes in through a [ProviderScope] so the first fetch is already
/// filtered. Writing it into the notifier from the screen's `initState` throws
/// ("tried to modify a provider while the widget tree was building"), which is
/// what the history button used to do.
Route<void> pipelineRunsRoute({PipelineRunFilter? filter}) => MaterialPageRoute(
      builder: (_) => ProviderScope(
        overrides: [
          if (filter != null)
            pipelineRunFilterSeedProvider.overrideWithValue(filter),
        ],
        child: const PipelineRunsScreen(),
      ),
    );

/// What every run is doing: how many copies are done, which printer took each,
/// and the two actions a run in trouble needs — cancel and retry-failed.
class PipelineRunsScreen extends ConsumerStatefulWidget {
  const PipelineRunsScreen({super.key});

  @override
  ConsumerState<PipelineRunsScreen> createState() => _PipelineRunsScreenState();
}

class _PipelineRunsScreenState extends ConsumerState<PipelineRunsScreen> {
  Timer? _poll;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    // Not an optimisation: this is the only thing that tracks a run through
    // printing. The `pipeline_run_updated` push stops at `dispatching` — the
    // scheduler never touches `PipelineRun`, so the status and the `copies_*`
    // roll-up are computed while answering a GET and pushed nowhere. It is
    // also routed per `created_by`, so a colleague's batch is invisible to it.
    // Remove this timer and a run sits on `dispatching` for ever.
    //
    // It refreshes the window already on screen rather than invalidating, which
    // would throw away every page past the first and jump the scroll position.
    //
    // Stops the moment nothing on screen is in flight, and that costs one
    // thing: a run someone *else* starts while this list holds only finished
    // ones does not appear on its own — the push is routed to its own
    // `created_by`, and there is nothing left here to poll for. Pull to
    // refresh is the way to see it, which is the trade for not waking a
    // request every four seconds on an idle screen.
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      final view = ref.read(pipelineRunsProvider).valueOrNull;
      final live = view?.runs.any((r) => !r.status.isTerminal) ?? false;
      if (live) {
        unawaited(ref.read(pipelineRunsProvider.notifier).refreshLoaded());
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// Ask for the next page a screen's height before the end, so the list grows
  /// under the thumb instead of stalling at the bottom. `loadMore` is itself a
  /// no-op while one is in flight, which is what makes a repeated scroll
  /// notification harmless.
  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels < position.maxScrollExtent - position.viewportDimension) {
      return;
    }
    unawaited(_loadMore());
  }

  Future<void> _loadMore() async {
    try {
      await ref.read(pipelineRunsProvider.notifier).loadMore();
    } on AppApiException catch (e) {
      if (!mounted) return;
      showApiFailure(ScaffoldMessenger.of(context), e,
          AppLocalizations.of(context), action: 'pipeline_runs.load_more');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final runs = ref.watch(pipelineRunsProvider);
    final filter = ref.watch(pipelineRunFilterProvider);

    return Scaffold(
      appBar: dashAppBar(
        context,
        title: l10n.pipelineRunsTitle,
        actions: [
          logTag(
            'pipeline_runs.filter',
            IconButton(
              icon: Badge(
                isLabelVisible: !filter.isEmpty,
                label: Text('${filter.activeCount}'),
                child: const Icon(Icons.filter_list_rounded),
              ),
              // The badge is the only sign that a filter is on, and a badge
              // is not read out — so the count goes in the name instead.
              tooltip: filter.isEmpty
                  ? l10n.pipelineRunsFilter
                  : l10n.pipelineRunsFilterActive(filter.activeCount),
              onPressed: () => showPipelineRunFilterSheet(context),
            ),
          ),
          if (ref.watch(canWritePipelinesProvider).orFalse)
            logTag(
              'pipeline_runs.clear',
              IconButton(
                icon: const Icon(Icons.cleaning_services_outlined),
                tooltip: l10n.pipelineRunsClear,
                onPressed: () => _clear(l10n),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(pipelineRunsProvider.future),
        child: runs.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => AsyncErrorView(
            message: err is AppApiException
                ? err.localized(l10n)
                : l10n.pipelineRunsEmpty,
            onRetry: () => ref.invalidate(pipelineRunsProvider),
            retryLabel: l10n.retry,
            scrollable: true,
          ),
          data: (view) => view.runs.isEmpty
              ? EmptyStateView(
                  // A filter that matches nothing is not an empty history, and
                  // saying so is what stops the user hunting for lost runs.
                  message: filter.isEmpty
                      ? l10n.pipelineRunsEmpty
                      : l10n.pipelineRunsNoneMatch,
                  icon: Icons.history_rounded,
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  // One past the runs for the footer: the spinner while a page
                  // loads, and the count once everything is in.
                  itemCount: view.runs.length + 1,
                  itemBuilder: (ctx, i) => i == view.runs.length
                      ? _footer(l10n, view)
                      : _RunCard(run: view.runs[i]),
                ),
        ),
      ),
    );
  }

  Widget _footer(AppLocalizations l10n, PipelineRunsView view) {
    if (view.loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (view.hasMore) {
      // Reachable when the list is shorter than the viewport, so no scroll can
      // fire, and as the affordance for a "load more" that failed.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: logTag(
            'pipeline_runs.load_more',
            TextButton(
              onPressed: _loadMore,
              child: Text(l10n.pipelineRunsLoadMore),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Center(
        child: Text(
          l10n.pipelineRunsShowingAll(view.runs.length),
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }

  Future<void> _clear(AppLocalizations l10n) async {
    final ok = await confirmDialog(
      context,
      title: l10n.pipelineRunsClear,
      message: l10n.pipelineRunsClearConfirm,
      confirmLabel: l10n.pipelineRunsClear,
      destructive: true,
      icon: Icons.cleaning_services_outlined,
      id: 'pipeline_runs.clear',
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final n = await ref.read(pipelinesRepositoryProvider).clearTerminalRuns();
      unawaited(ref.read(pipelineRunsProvider.notifier).refreshLoaded());
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.pipelineRunsCleared(n))));
    } on AppApiException catch (e) {
      showApiFailure(messenger, e, l10n, action: 'pipeline_runs.clear');
    }
  }
}

class _RunCard extends ConsumerWidget {
  const _RunCard({required this.run});

  final PipelineRun run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final canRun = ref.watch(canRunPipelinesProvider).orFalse;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    run.pipelineName ?? l10n.pipelineRunDeletedPipeline,
                    style: theme.textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _statusChip(theme, l10n),
              ],
            ),
            if ((run.sourceFilename ?? '').isNotEmpty)
              Text(l10n.pipelineRunSource(run.sourceFilename!),
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            if (run.parentRunId != null)
              Text(l10n.pipelineRunRetryOf(run.parentRunId!),
                  style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            // Excluded from semantics: with a value and no `semanticsLabel`
            // Flutter synthesises a bare percentage ("50"), which a reader
            // would announce right before the line below says the same thing
            // in words and with the counts.
            ExcludeSemantics(
              child: LinearProgressIndicator(
                value: run.copies == 0 ? null : run.copiesFinished / run.copies,
              ),
            ),
            const SizedBox(height: 4),
            Text(l10n.pipelineRunCopiesProgress(run.copiesFinished, run.copies),
                style: theme.textTheme.bodySmall),
            if (run.eligibilityOverridden)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(l10n.pipelineRunOverridden,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.tertiary)),
              ),
            if ((run.errorMessage ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(run.errorMessage!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error)),
              ),
            if (run.jobs.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final job in run.jobs) _jobLine(theme, l10n, job),
            ],
            if (canRun)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!run.status.isTerminal)
                    logTag(
                      'pipeline_runs.cancel',
                      TextButton(
                        onPressed: () => _cancel(context, ref, l10n),
                        child: Text(l10n.pipelineRunCancel),
                      ),
                    ),
                  if (run.canRetry)
                    logTag(
                      'pipeline_runs.retry',
                      TextButton(
                        onPressed: () => _retry(context, ref, l10n),
                        child: Text(l10n.pipelineRunRetry),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(ThemeData theme, AppLocalizations l10n) {
    final colour = runStatusColour(theme.colorScheme, run.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(runStatusLabel(l10n, run.status),
          style: theme.textTheme.labelSmall?.copyWith(color: colour)),
    );
  }

  Widget _jobLine(ThemeData theme, AppLocalizations l10n, PipelineJob job) {
    final label = switch (job.status) {
      PipelineJobStatus.pending => l10n.pipelineJobPending,
      PipelineJobStatus.awaitingPrinter => l10n.pipelineJobAwaitingPrinter,
      PipelineJobStatus.queued => l10n.pipelineJobQueued,
      PipelineJobStatus.printing => l10n.pipelineJobPrinting,
      PipelineJobStatus.completed => l10n.pipelineJobCompleted,
      PipelineJobStatus.failed => l10n.pipelineJobFailed,
      PipelineJobStatus.cancelled => l10n.pipelineJobCancelled,
      PipelineJobStatus.unknown => l10n.pipelineJobUnknown,
    };
    final icon = switch (job.status) {
      PipelineJobStatus.completed => Icons.check_circle_outline,
      PipelineJobStatus.failed => Icons.error_outline,
      PipelineJobStatus.cancelled => Icons.cancel_outlined,
      PipelineJobStatus.printing => Icons.print_outlined,
      _ => Icons.schedule_rounded,
    };
    final colour = switch (job.status) {
      PipelineJobStatus.completed => theme.colorScheme.primary,
      PipelineJobStatus.failed => theme.colorScheme.error,
      _ => theme.colorScheme.onSurfaceVariant,
    };
    final printer = job.assignedPrinterName;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colour),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              [
                l10n.pipelineJobCopy(job.copyIndex + 1),
                label,
                if (printer != null && printer.isNotEmpty) printer,
              ].join(' · '),
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ok = await confirmDialog(
      context,
      title: l10n.pipelineRunCancel,
      message: l10n.pipelineRunCancelConfirm,
      confirmLabel: l10n.pipelineRunCancel,
      destructive: true,
      icon: Icons.cancel_outlined,
      id: 'pipeline_runs.cancel',
    );
    if (!ok || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(pipelinesRepositoryProvider).cancel(run.id);
      unawaited(ref.read(pipelineRunsProvider.notifier).refreshLoaded());
      messenger.showSnackBar(SnackBar(content: Text(l10n.pipelineRunCancelled)));
    } on AppApiException catch (e) {
      showApiFailure(messenger, e, l10n, action: 'pipeline_runs.cancel');
    }
  }

  Future<void> _retry(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final count = run.copiesFailed + run.copiesCancelled;
    try {
      await ref.read(pipelinesRepositoryProvider).retryFailed(run.id);
      unawaited(ref.read(pipelineRunsProvider.notifier).refreshLoaded());
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.pipelineRunRetryStarted(count))));
    } on AppApiException catch (e) {
      showApiFailure(messenger, e, l10n, action: 'pipeline_runs.retry');
    }
  }
}
