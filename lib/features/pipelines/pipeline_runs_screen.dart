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
import '../common/state_views.dart';
import 'pipelines_providers.dart';

/// What every run is doing: how many copies are done, which printer took each,
/// and the two actions a run in trouble needs — cancel and retry-failed.
class PipelineRunsScreen extends ConsumerStatefulWidget {
  const PipelineRunsScreen({super.key});

  @override
  ConsumerState<PipelineRunsScreen> createState() => _PipelineRunsScreenState();
}

class _PipelineRunsScreenState extends ConsumerState<PipelineRunsScreen> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // Polled rather than pushed. The server does broadcast
    // `pipeline_run_updated`, but only to the run's own `created_by` — an
    // auth-disabled install broadcasts globally, a JWT session gets its own —
    // and this app's WS client is a printer-status pipeline that would have to
    // grow a new frame type to carry it. A 4 s poll while something is in
    // flight is the smaller change and works on every install; it stops the
    // moment nothing is running.
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      final page = ref.read(pipelineRunsProvider(0)).valueOrNull;
      final live = page?.runs.any((r) => !r.status.isTerminal) ?? false;
      if (live) ref.invalidate(pipelineRunsProvider(0));
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final runs = ref.watch(pipelineRunsProvider(0));

    return Scaffold(
      appBar: dashAppBar(
        context,
        title: l10n.pipelineRunsTitle,
        actions: [
          if (ref.watch(canWritePipelinesProvider))
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
        onRefresh: () async => ref.invalidate(pipelineRunsProvider(0)),
        child: runs.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => AsyncErrorView(
            message: err is AppApiException
                ? err.localized(l10n)
                : l10n.pipelineRunsEmpty,
            onRetry: () => ref.invalidate(pipelineRunsProvider(0)),
            retryLabel: l10n.retry,
            scrollable: true,
          ),
          data: (page) => page.runs.isEmpty
              ? EmptyStateView(
                  message: l10n.pipelineRunsEmpty,
                  icon: Icons.history_rounded,
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: page.runs.length,
                  itemBuilder: (ctx, i) => _RunCard(run: page.runs[i]),
                ),
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
      ref.invalidate(pipelineRunsProvider(0));
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
    final canRun = ref.watch(canRunPipelinesProvider);

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
            LinearProgressIndicator(
              value: run.copies == 0 ? null : run.copiesFinished / run.copies,
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
    final (label, colour) = switch (run.status) {
      PipelineRunStatus.queued => (l10n.pipelineStatusQueued, theme.colorScheme.onSurfaceVariant),
      PipelineRunStatus.slicing => (l10n.pipelineStatusSlicing, theme.colorScheme.primary),
      PipelineRunStatus.dispatching => (l10n.pipelineStatusDispatching, theme.colorScheme.primary),
      PipelineRunStatus.inProgress => (l10n.pipelineStatusInProgress, theme.colorScheme.primary),
      PipelineRunStatus.completed => (l10n.pipelineStatusCompleted, theme.colorScheme.primary),
      PipelineRunStatus.failed => (l10n.pipelineStatusFailed, theme.colorScheme.error),
      PipelineRunStatus.partialFailure => (l10n.pipelineStatusPartial, theme.colorScheme.tertiary),
      PipelineRunStatus.cancelled => (l10n.pipelineStatusCancelled, theme.colorScheme.onSurfaceVariant),
      PipelineRunStatus.unknown => (l10n.pipelineStatusUnknown, theme.colorScheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
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
      ref.invalidate(pipelineRunsProvider(0));
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
      ref.invalidate(pipelineRunsProvider(0));
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.pipelineRunRetryStarted(count))));
    } on AppApiException catch (e) {
      showApiFailure(messenger, e, l10n, action: 'pipeline_runs.retry');
    }
  }
}
