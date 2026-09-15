import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';

import '../../core/models/slicer_pipeline.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';

/// "Which pipeline?" — the sheet the run screen and the slice bar both open.
///
/// The two were written out separately and drifted: only one carried the
/// `Semantics` header, so on the other a screen reader opened straight into an
/// unnamed list. The subtitle is the only thing they actually disagree on, so
/// it is the parameter and everything else is shared.
///
/// Opened with [dashSheet], not `showModalBottomSheet`: both call sites were
/// missing its `useSafeArea` and bottom inset, which on Android 15 puts the
/// last pipeline in the list under the navigation bar.
Future<SlicerPipeline?> pickPipeline(
  BuildContext context, {
  required List<SlicerPipeline> pipelines,
  required String Function(AppLocalizations l10n, SlicerPipeline p) subtitle,
  required String tag,
  Color? Function(ThemeData theme, SlicerPipeline p)? subtitleColor,
}) => dashSheet<SlicerPipeline>(
  context,
  builder: (_) => _PipelinePickerSheet(
    pipelines: pipelines,
    subtitle: subtitle,
    tag: tag,
    subtitleColor: subtitleColor,
  ),
);

class _PipelinePickerSheet extends StatelessWidget {
  const _PipelinePickerSheet({
    required this.pipelines,
    required this.subtitle,
    required this.tag,
    this.subtitleColor,
  });

  final List<SlicerPipeline> pipelines;
  final String Function(AppLocalizations l10n, SlicerPipeline p) subtitle;

  /// Diagnostic id of one row. Wire value — the two callers keep the ids their
  /// logs already carry rather than sharing one.
  final String tag;

  /// Paints the subtitle of a row that needs to stand out — the run screen
  /// tints a pipeline with no target. Null keeps the default.
  final Color? Function(ThemeData theme, SlicerPipeline p)? subtitleColor;

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
          // A sheet that opens straight into a list gives a screen reader
          // nothing to say about what the list is for.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                header: true,
                child: Text(
                  l10n.pipelineSection,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: controller,
              itemCount: pipelines.length,
              itemBuilder: (ctx, i) {
                final p = pipelines[i];
                return ListTile(
                  title: Text(
                    p.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    subtitle(l10n, p),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: subtitleColor?.call(theme, p),
                    ),
                  ),
                  onTap: () => Navigator.pop(ctx, p),
                ).tagged(tag);
              },
            ),
          ),
        ],
      ),
    );
  }
}
