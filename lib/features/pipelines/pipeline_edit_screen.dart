import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/diagnostics/log_tag.dart';
import '../../core/models/printer.dart';
import '../../core/models/slicer_pipeline.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import '../common/dash_input.dart';
import 'pipelines_providers.dart';

/// Name, description and — the reason this screen exists — the target a run
/// dispatches to.
///
/// The bundle itself (printer / process / filaments / plate) is not editable
/// here on purpose: it is a four-slot selection, and the slice form is the one
/// screen that can present those slots with their catalogs, compatibility
/// filtering and per-slot colour hints. Re-saving from the slice form is how a
/// bundle changes; this screen decides where it runs.
class PipelineEditScreen extends ConsumerStatefulWidget {
  const PipelineEditScreen({super.key, required this.pipeline});

  final SlicerPipeline pipeline;

  @override
  ConsumerState<PipelineEditScreen> createState() => _PipelineEditScreenState();
}

class _PipelineEditScreenState extends ConsumerState<PipelineEditScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.pipeline.name);
  late final TextEditingController _description =
      TextEditingController(text: widget.pipeline.description ?? '');

  late PipelineTargetKind _targetKind = widget.pipeline.targetKind;
  late int? _printerId = widget.pipeline.targetPrinterId;
  late String? _modelClass = widget.pipeline.targetModelClass;
  late FanoutStrategy _fanout = widget.pipeline.fanoutStrategy;

  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final printers =
        ref.watch(pipelineTargetPrintersProvider).valueOrNull ?? const [];
    final classes =
        ref.watch(pipelinePrinterClassesProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: dashAppBar(context, title: l10n.pipelineEditTitle),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          TextField(
            controller: _name,
            maxLength: 200,
            decoration: InputDecoration(labelText: l10n.pipelineNameHint),
            onChanged: (_) => setState(() {}),
          ).tagged('pipeline_edit.name'),
          TextField(
            controller: _description,
            maxLength: 1000,
            maxLines: 3,
            minLines: 1,
            decoration:
                InputDecoration(labelText: l10n.pipelineDescriptionHint),
          ).tagged('pipeline_edit.description'),
          const SizedBox(height: 16),
          Text(l10n.pipelineTargetType, style: theme.textTheme.labelLarge),
          RadioGroup<PipelineTargetKind>(
            groupValue: _targetKind,
            onChanged: (v) => setState(() => _targetKind = v!),
            child: Column(
              children: [
                RadioListTile<PipelineTargetKind>(
                  value: PipelineTargetKind.specificPrinter,
                  title: Text(l10n.pipelineTargetSpecific),
                  contentPadding: EdgeInsets.zero,
                ).tagged('pipeline_edit.target_specific'),
                RadioListTile<PipelineTargetKind>(
                  value: PipelineTargetKind.printerClass,
                  title: Text(l10n.pipelineTargetClass),
                  contentPadding: EdgeInsets.zero,
                ).tagged('pipeline_edit.target_class'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_targetKind == PipelineTargetKind.specificPrinter)
            _printerDropdown(l10n, printers)
          else ...[
            _classDropdown(l10n, classes),
            const SizedBox(height: 16),
            // Only a class spreads copies over several printers; with one
            // pinned printer there is nothing to spread.
            _fanoutDropdown(l10n),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _name.text.trim().isEmpty || _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l10n.pipelineSaveConfirm),
          ).tagged('pipeline_edit.save'),
        ],
      ),
    );
  }

  /// The pinned printer, or none yet — which is what every pipeline saved from
  /// the slice form starts as, since the create schema carries no target.
  Widget _printerDropdown(AppLocalizations l10n, List<Printer> printers) =>
      dashAnyOrOne<int>(
        context,
        id: 'pipeline_edit.printer',
        anyLabel: l10n.pipelineTargetNone,
        label: Text(l10n.pipelineTargetPickPrinter),
        enabled: !_saving,
        selected: _printerId,
        options: [for (final p in printers) (p.id, p.name)],
        onPick: (v) => setState(() => _printerId = v),
      );

  /// Verbatim model codes — see `pipelinePrinterClassesProvider` for why they
  /// must not be normalised on the way in.
  Widget _classDropdown(AppLocalizations l10n, List<String> classes) =>
      dashAnyOrOne<String>(
        context,
        id: 'pipeline_edit.class',
        anyLabel: l10n.pipelineTargetNone,
        label: Text(l10n.pipelineTargetPickClass),
        enabled: !_saving,
        selected: _modelClass,
        options: [for (final c in classes) (c, c)],
        onPick: (v) => setState(() => _modelClass = v),
      );

  Widget _fanoutDropdown(AppLocalizations l10n) {
    String label(FanoutStrategy s) => switch (s) {
          FanoutStrategy.maxParallel => l10n.pipelineFanoutMaxParallel,
          FanoutStrategy.roundRobin => l10n.pipelineFanoutRoundRobin,
          FanoutStrategy.fillOneFirst => l10n.pipelineFanoutFillOneFirst,
        };
    // Not a [dashAnyOrOne]: a strategy has no "none" — the server defaults an
    // unset one to `max_parallel`, so an empty row would be a lie about it.
    return dashCombo<FanoutStrategy>(
      context,
      id: 'pipeline_edit.fanout',
      label: Text(l10n.pipelineFanout),
      enabled: !_saving,
      initialSelection: _fanout,
      onSelected: (v) => setState(() => _fanout = v ?? _fanout),
      entries: [
        for (final s in FanoutStrategy.values)
          DropdownMenuEntry(
            value: s,
            label: label(s),
            labelWidget: logTag('pipeline_edit.fanout_option', Text(label(s))),
          ),
      ],
    );
  }

  /// Writes the whole target as one payload, including the *clearing* of the
  /// half that no longer applies.
  ///
  /// Clearing is the load-bearing part. The matcher takes the specific-printer
  /// branch whenever `target_printer_id is not None` — **before** it looks at
  /// `target_kind` (`pipeline_eligibility.py`) — so a pipeline switched from a
  /// pinned printer to a class would keep dispatching to that one printer if
  /// the id were merely left alone. And a `null` cannot clear it: every field
  /// is written under an `is not None` guard server-side, which makes omitting
  /// a key and sending null the same request. The sentinels the API defines for
  /// this are `target_printer_id: 0` and `target_model_class: ''`.
  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final byClass = _targetKind == PipelineTargetKind.printerClass;

    setState(() => _saving = true);
    try {
      await ref.read(pipelinesRepositoryProvider).update(
            widget.pipeline.id,
            name: _name.text.trim(),
            description: _description.text.trim(),
            targetKind: _targetKind,
            targetPrinterId: byClass ? 0 : (_printerId ?? 0),
            targetModelClass: byClass ? (_modelClass ?? '') : '',
            fanoutStrategy: _fanout,
          );
      ref.invalidate(pipelinesProvider);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.pipelineSaved)));
      navigator.pop();
    } on AppApiException catch (e) {
      if (mounted) setState(() => _saving = false);
      showApiFailure(mounted ? messenger : null, e, l10n,
          action: 'pipeline_edit.save');
    }
  }
}
