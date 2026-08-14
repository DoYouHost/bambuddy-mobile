import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/diagnostics/log_tag.dart';
import '../../core/models/printer.dart';
import '../../core/models/slicer_pipeline.dart';
import '../../core/models/slicer_preset.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import '../common/confirm_dialog.dart';
import '../common/state_views.dart';
import '../slicer/slice_providers.dart';
import 'pipeline_edit_screen.dart';
import 'pipeline_presets.dart';
import 'pipeline_runs_screen.dart';
import 'pipelines_providers.dart';

/// The saved pipelines: what each bundles, whether it can run, and the edit
/// that gives it a target.
///
/// A pipeline is authored in two places by design — the bundle is saved from
/// the slice form (the only screen that has a four-slot selection to save), and
/// the *target* is set here, because the create endpoint cannot carry one. So
/// this screen never creates; it targets, renames and deletes.
class PipelinesScreen extends ConsumerWidget {
  const PipelinesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final pipelines = ref.watch(pipelinesProvider);

    return Scaffold(
      appBar: dashAppBar(
        context,
        title: l10n.pipelinesTitle,
        actions: [
          logTag(
            'pipelines.open_runs',
            IconButton(
              icon: const Icon(Icons.history_rounded),
              tooltip: l10n.pipelineRunsTitle,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PipelineRunsScreen()),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(pipelinesProvider),
        child: pipelines.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => AsyncErrorView(
            message: err is AppApiException
                ? err.localized(l10n)
                : l10n.pipelinesEmpty,
            onRetry: () => ref.invalidate(pipelinesProvider),
            retryLabel: l10n.retry,
            scrollable: true,
          ),
          data: (list) => list.isEmpty
              ? EmptyStateView(
                  message: '${l10n.pipelinesEmpty}\n\n${l10n.pipelinesEmptyHint}',
                  icon: Icons.account_tree_outlined,
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: list.length,
                  itemBuilder: (ctx, i) => _PipelineCard(pipeline: list[i]),
                ),
        ),
      ),
    );
  }
}

class _PipelineCard extends ConsumerWidget {
  const _PipelineCard({required this.pipeline});

  final SlicerPipeline pipeline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final catalog = ref.watch(slicerPresetsProvider).valueOrNull;
    final canWrite = ref.watch(canWritePipelinesProvider);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pipeline.name,
                          style: theme.textTheme.titleSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      if ((pipeline.description ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(pipeline.description!,
                              style: theme.textTheme.bodySmall,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                  ),
                ),
                if (canWrite)
                  logTag(
                    'pipelines.edit',
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: l10n.pipelineEditTitle,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PipelineEditScreen(pipeline: pipeline),
                        ),
                      ),
                    ),
                  ),
                if (canWrite)
                  logTag(
                    'pipelines.delete',
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: l10n.pipelineDelete,
                      onPressed: () => _delete(context, ref, l10n),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _row(theme, l10n.slicePrinter,
                _name(catalog, pipeline.printerPreset, PresetSlot.printer, l10n)),
            _row(theme, l10n.sliceProcess,
                _name(catalog, pipeline.processPreset, PresetSlot.process, l10n)),
            if (pipeline.bedType != null)
              _row(theme, l10n.pipelineBed, pipeline.bedType!),
            const SizedBox(height: 6),
            Text(l10n.pipelineFilamentsCount(pipeline.filamentPresets.length),
                style: theme.textTheme.labelSmall),
            for (var i = 0; i < pipeline.filamentPresets.length; i++)
              _row(
                theme,
                l10n.pipelineSlotNumbered(i + 1),
                _name(catalog, pipeline.filamentPresets[i], PresetSlot.filament,
                    l10n),
              ),
            const SizedBox(height: 8),
            _targetLine(
              theme,
              l10n,
              ref.watch(pipelineTargetPrintersProvider).valueOrNull,
            ),
          ],
        ),
      ),
    );
  }

  /// What the pipeline will run on — or the warning that it cannot, which is
  /// the normal state right after saving one from the slice form.
  Widget _targetLine(
    ThemeData theme,
    AppLocalizations l10n,
    List<Printer>? printers,
  ) {
    if (!pipeline.isRunnable) {
      return Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 18, color: theme.colorScheme.tertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(l10n.pipelineNeedsTarget,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.tertiary)),
          ),
        ],
      );
    }
    final label = switch (pipeline.targetKind) {
      PipelineTargetKind.specificPrinter =>
        l10n.pipelineRunOnPrinter(_printerName(printers, l10n)),
      PipelineTargetKind.printerClass =>
        l10n.pipelineRunOnClass(pipeline.targetModelClass ?? ''),
    };
    return Row(
      children: [
        Icon(Icons.print_outlined,
            size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
      ],
    );
  }

  String _printerName(List<Printer>? printers, AppLocalizations l10n) {
    final id = pipeline.targetPrinterId;
    if (id == null) return '';
    for (final p in printers ?? const <Printer>[]) {
      if (p.id == id) return p.name;
    }
    // Either the list has not landed yet or the printer really is gone. Naming
    // the id beats an empty line in both cases.
    return l10n.pipelineTargetPrinterGone(id);
  }

  Widget _row(ThemeData theme, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: RichText(
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          text: TextSpan(
            style: theme.textTheme.bodySmall,
            children: [
              TextSpan(
                text: '$label: ',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              TextSpan(text: value),
            ],
          ),
        ),
      );

  String _name(
    UnifiedPresets? catalog,
    PresetRef ref,
    PresetSlot slot,
    AppLocalizations l10n,
  ) {
    if (catalog == null) return ref.id;
    final preset = resolvePresetRef(catalog, ref, slot);
    return isUnresolved(preset) ? l10n.pipelinePresetGone : preset.name;
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ok = await confirmDialog(
      context,
      title: l10n.pipelineDelete,
      message: l10n.pipelineDeleteConfirm(pipeline.name),
      confirmLabel: l10n.pipelineDelete,
      destructive: true,
      icon: Icons.delete_outline,
      id: 'pipelines.delete',
    );
    if (!ok || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(pipelinesRepositoryProvider).delete(pipeline.id);
      ref.invalidate(pipelinesProvider);
      messenger.showSnackBar(SnackBar(content: Text(l10n.pipelineDeleted)));
    } on AppApiException catch (e) {
      showApiFailure(messenger, e, l10n, action: 'pipelines.delete');
    }
  }
}
