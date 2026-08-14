import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/diagnostics/log_tag.dart';
import '../../core/models/slicer_pipeline.dart';
import '../../core/models/slicer_preset.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import '../slicer/slice_providers.dart';
import 'pipeline_presets.dart';
import 'pipelines_providers.dart';

/// The "apply a saved bundle / save this one" row at the top of the slice form.
///
/// Renders nothing at all unless the server has the routes and this session may
/// read them — an entry point that can only produce a 403 is worse than none,
/// and an API-key session is refused every pipeline permission server-side.
class PipelineSliceBar extends ConsumerStatefulWidget {
  const PipelineSliceBar({
    super.key,
    required this.printer,
    required this.process,
    required this.filaments,
    required this.bedType,
    required this.onApply,
    required this.busy,
  });

  final SlicerPreset? printer;
  final SlicerPreset? process;
  final List<SlicerPreset?> filaments;
  final String? bedType;

  /// Handed the picked pipeline; the form decides how to fold it into its slots.
  final void Function(SlicerPipeline) onApply;

  /// The slice itself is running — no point starting a save on top of it.
  final bool busy;

  @override
  ConsumerState<PipelineSliceBar> createState() => _PipelineSliceBarState();
}

class _PipelineSliceBarState extends ConsumerState<PipelineSliceBar> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    if (ref.watch(pipelinesSupportedProvider).valueOrNull != true) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final pipelines = ref.watch(pipelinesProvider).valueOrNull ?? const [];
    final canSave = ref.watch(canWritePipelinesProvider) && _selectionComplete;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.account_tree_outlined),
            enabled: pipelines.isNotEmpty && !widget.busy,
            title: Text(l10n.pipelineSection,
                style: theme.textTheme.labelMedium),
            subtitle: Text(
              pipelines.isEmpty ? l10n.pipelineApplyEmpty : l10n.pipelineApply,
              style: theme.textTheme.bodyMedium,
            ),
            trailing:
                pipelines.isEmpty ? null : const Icon(Icons.chevron_right),
            onTap: pipelines.isEmpty || widget.busy ? null : _pick,
          ).tagged('slice.pipeline_apply'),
          if (ref.watch(canWritePipelinesProvider))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: Text(l10n.pipelineSaveAs),
                  onPressed: canSave && !_saving && !widget.busy ? _save : null,
                ).tagged('slice.pipeline_save'),
              ),
            ),
        ],
      ),
    );
  }

  /// A pipeline needs a ref per slot — `filament_presets` has `min_length=1`
  /// and the whole bundle is required — so a half-filled form has nothing
  /// savable yet.
  bool get _selectionComplete =>
      widget.printer != null &&
      widget.process != null &&
      widget.filaments.isNotEmpty &&
      widget.filaments.every((f) => f != null);

  Future<void> _pick() async {
    final pipelines = ref.read(pipelinesProvider).valueOrNull ?? const [];
    final catalog = ref.read(slicerPresetsProvider).valueOrNull;
    final picked = await showModalBottomSheet<SlicerPipeline>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _PipelinePicker(pipelines: pipelines, catalog: catalog),
    );
    if (picked == null || !mounted) return;
    widget.onApply(picked);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text(AppLocalizations.of(context).pipelineApplied(picked.name))),
    );
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final name = await _askName(l10n);
    if (name == null || !mounted) return;

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(pipelinesRepositoryProvider).create(
            SlicerPipeline(
              id: 0, // server assigns
              name: name,
              printerPreset: refOf(widget.printer!),
              processPreset: refOf(widget.process!),
              filamentPresets: [for (final f in widget.filaments) refOf(f!)],
              bedType: widget.bedType,
            ),
          );
      ref.invalidate(pipelinesProvider);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.pipelineSaved)));
    } on AppApiException catch (e) {
      showApiFailure(mounted ? messenger : null, e, l10n,
          action: 'slice.pipeline_save');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _askName(AppLocalizations l10n) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        // Rebuilt on every keystroke so the confirm button tracks the field —
        // the name is the one required part of the create body (min_length=1).
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(l10n.pipelineSaveAs),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 200,
                  decoration:
                      InputDecoration(labelText: l10n.pipelineNameHint),
                  onChanged: (_) => setLocal(() {}),
                  onSubmitted: (v) => v.trim().isEmpty
                      ? null
                      : Navigator.pop(ctx, v.trim()),
                ).tagged('pipeline.name_field'),
                Text(l10n.pipelineSaveHint,
                    style: Theme.of(ctx).textTheme.bodySmall),
              ],
            ),
            actions: [
              logTag(
                'pipeline.save_cancel',
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.cancel),
                ),
              ),
              logTag(
                'pipeline.save_confirm',
                FilledButton(
                  onPressed: controller.text.trim().isEmpty
                      ? null
                      : () => Navigator.pop(ctx, controller.text.trim()),
                  child: Text(l10n.pipelineSaveConfirm),
                ),
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();
    return name;
  }
}

/// The saved bundles, each summarised by the profiles it carries so two
/// similarly named pipelines can be told apart without opening them.
class _PipelinePicker extends StatelessWidget {
  const _PipelinePicker({required this.pipelines, required this.catalog});

  final List<SlicerPipeline> pipelines;
  final UnifiedPresets? catalog;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (ctx, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child:
                  Text(l10n.pipelineSection, style: theme.textTheme.titleMedium),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: controller,
              itemCount: pipelines.length,
              itemBuilder: (ctx, i) {
                final p = pipelines[i];
                return ListTile(
                  title: Text(p.name,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    _summary(l10n, p),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  onTap: () => Navigator.pop(ctx, p),
                ).tagged('slice.pipeline_option');
              },
            ),
          ),
        ],
      ),
    );
  }

  String _summary(AppLocalizations l10n, SlicerPipeline p) {
    final cat = catalog;
    if (cat == null) {
      return l10n.pipelineFilamentsCount(p.filamentPresets.length);
    }
    final process = resolvePresetRef(cat, p.processPreset, PresetSlot.process);
    final printer = resolvePresetRef(cat, p.printerPreset, PresetSlot.printer);
    final parts = [
      if (!isUnresolved(printer)) printer.name,
      if (!isUnresolved(process)) process.name,
      l10n.pipelineFilamentsCount(p.filamentPresets.length),
    ];
    return parts.join(' · ');
  }
}
