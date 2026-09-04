import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/log_tag.dart';

import '../../core/models/pipeline_run.dart';
import '../../l10n/app_localizations.dart';
import '../common/dash_input.dart';
import '../common/dash_sheet.dart';
import 'pipeline_run_status_labels.dart';
import 'pipelines_providers.dart';

/// Narrow the runs dashboard: which pipeline, which status, which target.
///
/// A sheet rather than a row of chips on the screen: three selects is a form,
/// and on a phone they cost more width than the list can spare.
Future<void> showPipelineRunFilterSheet(BuildContext context) => dashSheet<void>(
      context,
      builder: (_) => const _PipelineRunFilterSheet(),
    );

/// One target choice. The server has two fields for this and ANDs them, but a
/// run is dispatched to a printer *or* to a class, so the picker offers one
/// list and only ever sets one of the pair. A null [_Target] is "any target",
/// which is what keeps the two fields from needing a third state between them.
typedef _Target = ({int? printerId, String? modelClass});

class _PipelineRunFilterSheet extends ConsumerWidget {
  const _PipelineRunFilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final filter = ref.watch(pipelineRunFilterProvider);
    final pipelines = ref.watch(pipelinesProvider).valueOrNull ?? const [];
    final printers =
        ref.watch(pipelineTargetPrintersProvider).valueOrNull ?? const [];
    final classes =
        ref.watch(pipelinePrinterClassesProvider).valueOrNull ?? const [];
    final notifier = ref.read(pipelineRunFilterProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.pipelineRunsFilter, style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),

          dashAnyOrOne<int>(
            context,
            id: 'pipeline_runs.filter_pipeline',
            anyLabel: l10n.pipelineRunsFilterAny,
            label: Text(l10n.pipelineSection),
            // A run whose pipeline was deleted carries a null `pipeline_id`,
            // and no value of this filter reaches it.
            helperText: l10n.pipelineRunsFilterPipelineHint,
            selected: filter.pipelineId,
            options: [for (final p in pipelines) (p.id, p.name)],
            onPick: (v) =>
                notifier.replace(filter.copyWith(pipelineId: (value: v))),
          ),
          const SizedBox(height: 12),

          dashAnyOrOne<String>(
            context,
            id: 'pipeline_runs.filter_status',
            anyLabel: l10n.pipelineRunsFilterAny,
            label: Text(l10n.pipelineRunsFilterStatus),
            // The server matches the *persisted* status, which lags the live
            // roll-up until a transition writes through.
            helperText: l10n.pipelineRunsFilterStatusHint,
            selected: filter.status,
            options: [
              for (final s in PipelineRunStatus.filterable)
                (s.wire!, runStatusLabel(l10n, s)),
            ],
            onPick: (v) =>
                notifier.replace(filter.copyWith(status: (value: v))),
          ),
          const SizedBox(height: 12),

          dashAnyOrOne<_Target>(
            context,
            id: 'pipeline_runs.filter_target',
            anyLabel: l10n.pipelineRunsFilterAny,
            label: Text(l10n.pipelineRunsFilterTarget),
            // Filters on where the pipeline points *now*: re-targeting one
            // moves its whole history from one answer to the other.
            helperText: l10n.pipelineRunsFilterTargetHint,
            selected: filter.targetPrinterId == null &&
                    filter.targetModelClass == null
                ? null
                : (
                    printerId: filter.targetPrinterId,
                    modelClass: filter.targetModelClass,
                  ),
            options: [
              for (final p in printers)
                (
                  (printerId: p.id, modelClass: null),
                  l10n.pipelineRunOnPrinter(p.name),
                ),
              for (final c in classes)
                (
                  (printerId: null, modelClass: c),
                  l10n.pipelineRunOnClass(c),
                ),
            ],
            onPick: (v) => notifier.replace(filter.copyWith(
              targetPrinterId: (value: v?.printerId),
              targetModelClass: (value: v?.modelClass),
            )),
          ),
          const SizedBox(height: 20),

          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              logTag(
                'pipeline_runs.filter_clear',
                TextButton(
                  onPressed: filter.isEmpty
                      ? null
                      : () {
                          notifier.clear();
                          Navigator.of(context).pop();
                        },
                  child: Text(l10n.pipelineRunsFilterClear),
                ),
              ),
              const SizedBox(width: 8),
              logTag(
                'pipeline_runs.filter_done',
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.pipelineRunsDone),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
