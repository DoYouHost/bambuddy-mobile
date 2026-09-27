import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import 'package:app_diagnostics/app_diagnostics.dart';
import '../../core/models/slicer_pipeline.dart';
import '../../core/models/slicer_preset.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import '../common/dash_async.dart';
import '../slicer/slice_providers.dart';
import 'pipeline_picker_sheet.dart';
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
    if (!ref.watch(pipelinesSupportedProvider).orFalse) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final pipelines = ref.watch(pipelinesProvider).valueOrNull ?? const [];
    final canSave =
        ref.watch(canWritePipelinesProvider).orFalse && _selectionComplete;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.account_tree_outlined),
            enabled: pipelines.isNotEmpty && !widget.busy,
            title: Text(
              l10n.pipelineSection,
              style: theme.textTheme.labelMedium,
            ),
            subtitle: Text(
              pipelines.isEmpty ? l10n.pipelineApplyEmpty : l10n.pipelineApply,
              style: theme.textTheme.bodyMedium,
            ),
            trailing: pipelines.isEmpty
                ? null
                : const Icon(Icons.chevron_right),
            onTap: pipelines.isEmpty || widget.busy ? null : _pick,
          ).tagged('slice.pipeline_apply'),
          if (ref.watch(canWritePipelinesProvider).orFalse)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: _saving
                      ? const DashSpinner(size: 16)
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
    // Both read before the sheet, like every other action in this file: the
    // sheet is an await, and `onApply` below rebuilds the form that owns this
    // bar, so neither is safe to look up off `context` afterwards.
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final picked = await pickPipeline(
      context,
      pipelines: pipelines,
      tag: 'slice.pipeline_option',
      subtitle: (l10n, p) => _summary(l10n, catalog, p),
    );
    if (picked == null || !mounted) return;
    widget.onApply(picked);
    messenger.snack(l10n.pipelineApplied(picked.name));
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final name = await _askName(l10n);
    if (name == null || !mounted) return;

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(pipelinesRepositoryProvider)
          .create(
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
      messenger.snack(l10n.pipelineSaved);
    } on AppApiException catch (e) {
      showApiFailure(
        mounted ? messenger : null,
        e,
        l10n,
        action: 'slice.pipeline_save',
      );
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
                  decoration: InputDecoration(labelText: l10n.pipelineNameHint),
                  onChanged: (_) => setLocal(() {}),
                  onSubmitted: (v) =>
                      v.trim().isEmpty ? null : Navigator.pop(ctx, v.trim()),
                ).tagged('pipeline.name_field'),
                Text(
                  l10n.pipelineSaveHint,
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
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

/// Each pipeline summarised by the profiles it carries, so two similarly named
/// ones can be told apart without opening them.
String _summary(
  AppLocalizations l10n,
  UnifiedPresets? catalog,
  SlicerPipeline p,
) {
  if (catalog == null) {
    return l10n.pipelineFilamentsCount(p.filamentPresets.length);
  }
  final process = resolvePresetRef(
    catalog,
    p.processPreset,
    PresetSlot.process,
  );
  final printer = resolvePresetRef(
    catalog,
    p.printerPreset,
    PresetSlot.printer,
  );
  final parts = [
    if (!isUnresolved(printer)) printer.name,
    if (!isUnresolved(process)) process.name,
    l10n.pipelineFilamentsCount(p.filamentPresets.length),
  ];
  return parts.join(' · ');
}
