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
/// list and only ever sets one of the pair.
typedef _Target = ({int? printerId, String? modelClass});

const _Target _anyTarget = (printerId: null, modelClass: null);

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

          dashCombo<int?>(
            context,
            id: 'pipeline_runs.filter_pipeline',
            label: Text(l10n.pipelineSection),
            initialSelection: filter.pipelineId,
            // A run whose pipeline was deleted carries a null `pipeline_id`,
            // and no value of this filter reaches it — so the helper says the
            // list is of saved pipelines, not of everything that ever ran.
            helperText: l10n.pipelineRunsFilterPipelineHint,
            onSelected: (v) =>
                notifier.replace(filter.copyWith(pipelineId: (value: v))),
            entries: [
              DropdownMenuEntry(
                value: null,
                label: l10n.pipelineRunsFilterAny,
                labelWidget: logTag('pipeline_runs.filter_pipeline_option',
                    Text(l10n.pipelineRunsFilterAny)),
              ),
              for (final p in pipelines)
                DropdownMenuEntry(
                  value: p.id,
                  label: p.name,
                  labelWidget: logTag(
                      'pipeline_runs.filter_pipeline_option', Text(p.name)),
                ),
            ],
          ),
          const SizedBox(height: 12),

          dashCombo<String?>(
            context,
            id: 'pipeline_runs.filter_status',
            label: Text(l10n.pipelineRunsFilterStatus),
            initialSelection: filter.status,
            // The server matches the *persisted* status, which lags the live
            // roll-up until a transition writes through — so a run that is
            // printing can still answer to `dispatching`.
            helperText: l10n.pipelineRunsFilterStatusHint,
            onSelected: (v) =>
                notifier.replace(filter.copyWith(status: (value: v))),
            entries: [
              DropdownMenuEntry(
                value: null,
                label: l10n.pipelineRunsFilterAny,
                labelWidget: logTag('pipeline_runs.filter_status_option',
                    Text(l10n.pipelineRunsFilterAny)),
              ),
              for (final s in PipelineRunStatus.filterable)
                DropdownMenuEntry(
                  value: s.wire,
                  label: runStatusLabel(l10n, s),
                  labelWidget: logTag('pipeline_runs.filter_status_option',
                      Text(runStatusLabel(l10n, s))),
                ),
            ],
          ),
          const SizedBox(height: 12),

          dashCombo<_Target>(
            context,
            id: 'pipeline_runs.filter_target',
            label: Text(l10n.pipelineRunsFilterTarget),
            initialSelection: (
              printerId: filter.targetPrinterId,
              modelClass: filter.targetModelClass,
            ),
            // Filters on where the pipeline points *now*: re-targeting one
            // moves its whole history from one answer to the other.
            helperText: l10n.pipelineRunsFilterTargetHint,
            onSelected: (v) => notifier.replace(filter.copyWith(
              targetPrinterId: (value: v?.printerId),
              targetModelClass: (value: v?.modelClass),
            )),
            entries: [
              DropdownMenuEntry(
                value: _anyTarget,
                label: l10n.pipelineRunsFilterAny,
                labelWidget: logTag('pipeline_runs.filter_target_option',
                    Text(l10n.pipelineRunsFilterAny)),
              ),
              for (final p in printers)
                DropdownMenuEntry(
                  value: (printerId: p.id, modelClass: null),
                  label: l10n.pipelineRunOnPrinter(p.name),
                  labelWidget: logTag('pipeline_runs.filter_target_option',
                      Text(l10n.pipelineRunOnPrinter(p.name))),
                ),
              for (final c in classes)
                DropdownMenuEntry(
                  value: (printerId: null, modelClass: c),
                  label: l10n.pipelineRunOnClass(c),
                  labelWidget: logTag('pipeline_runs.filter_target_option',
                      Text(l10n.pipelineRunOnClass(c))),
                ),
            ],
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
