import 'package:flutter/material.dart';

import '../../core/models/printer.dart';
import '../../core/models/pipeline_run.dart';
import '../../l10n/app_localizations.dart';

/// What a run's status is called, and the ink that carries the same meaning.
///
/// Split out because the run card and the dashboard's status filter name the
/// same eight states, and the two lists have to agree: a filter offering a
/// label the card never shows would look like a status the app invented.
String runStatusLabel(AppLocalizations l10n, PipelineRunStatus status) =>
    switch (status) {
      PipelineRunStatus.queued => l10n.pipelineStatusQueued,
      PipelineRunStatus.slicing => l10n.pipelineStatusSlicing,
      PipelineRunStatus.dispatching => l10n.pipelineStatusDispatching,
      PipelineRunStatus.inProgress => l10n.pipelineStatusInProgress,
      PipelineRunStatus.completed => l10n.pipelineStatusCompleted,
      PipelineRunStatus.failed => l10n.pipelineStatusFailed,
      PipelineRunStatus.partialFailure => l10n.pipelineStatusPartial,
      PipelineRunStatus.cancelled => l10n.pipelineStatusCancelled,
      PipelineRunStatus.unknown => l10n.pipelineStatusUnknown,
    };

/// Amber for the one state that leaves work undone without saying it failed;
/// error red for the failure; primary while something is happening; muted for
/// the states nothing is expected of.
Color runStatusColour(ColorScheme scheme, PipelineRunStatus status) =>
    switch (status) {
      PipelineRunStatus.slicing ||
      PipelineRunStatus.dispatching ||
      PipelineRunStatus.inProgress ||
      PipelineRunStatus.completed => scheme.primary,
      PipelineRunStatus.failed => scheme.error,
      PipelineRunStatus.partialFailure => scheme.tertiary,
      PipelineRunStatus.queued ||
      PipelineRunStatus.cancelled ||
      PipelineRunStatus.unknown => scheme.onSurfaceVariant,
    };

/// What a pipeline's target printer is called.
///
/// The picker used to spell this `#3` while the pipeline list beside it
/// resolved the name, so the same printer read as two different things
/// depending on which screen named it.
String targetPrinterName(
  AppLocalizations l10n,
  List<Printer>? printers,
  int? id,
) {
  if (id == null) return '';
  for (final p in printers ?? const <Printer>[]) {
    if (p.id == id) return p.name;
  }
  // Either the list has not landed yet or the printer really is gone. Naming
  // the id beats an empty line in both cases.
  return l10n.pipelineTargetPrinterGone(id);
}
