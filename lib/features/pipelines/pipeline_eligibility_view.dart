import 'package:flutter/material.dart';

import '../../core/models/pipeline_run.dart';
import '../../core/models/slicer_pipeline.dart';
import '../../l10n/app_localizations.dart';

/// The pre-flight verdict, rendered the same whether it came from
/// `check-eligibility` or from the 409 a `run` was refused with — one widget,
/// because the server deliberately returns one shape for both.
class EligibilityView extends StatelessWidget {
  const EligibilityView({super.key, required this.report});

  final EligibilityReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final blocking = report.allIssues.where((i) => !i.isAdvisory).toList();
    final advisory = report.allIssues.where((i) => i.isAdvisory).toList();

    // `ok` is not "no issues": a class run is ok as soon as one printer passes,
    // so the headline reports the verdict and the list reports the detail.
    final (icon, colour, headline) = report.ok
        ? (
            blocking.isEmpty ? Icons.check_circle_outline : Icons.info_outline,
            blocking.isEmpty
                ? theme.colorScheme.primary
                : theme.colorScheme.tertiary,
            _okHeadline(l10n),
          )
        : (
            Icons.error_outline,
            theme.colorScheme.error,
            l10n.pipelineEligibilityBlocked,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: colour),
            const SizedBox(width: 8),
            Expanded(
              child: Text(headline,
                  style: theme.textTheme.bodyMedium?.copyWith(color: colour)),
            ),
          ],
        ),
        if (blocking.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final i in blocking) _issueLine(theme, l10n, i, false),
        ],
        if (advisory.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(l10n.pipelineEligibilityAdvisory,
              style: theme.textTheme.labelSmall),
          for (final i in advisory) _issueLine(theme, l10n, i, true),
        ],
        // Which candidate is which — a class report that is `ok` overall can
        // still have most of its printers unusable, and that decides whether
        // "run anyway" means one printer or five.
        if (report.targetKind == PipelineTargetKind.printerClass &&
            report.printerReports.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final p in report.printerReports)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  Icon(p.ok ? Icons.check : Icons.close,
                      size: 16,
                      color: p.ok
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(p.printerName,
                          style: theme.textTheme.bodySmall)),
                ],
              ),
            ),
        ],
      ],
    );
  }

  String _okHeadline(AppLocalizations l10n) =>
      report.targetKind == PipelineTargetKind.printerClass &&
              report.printerReports.isNotEmpty
          ? l10n.pipelineEligibilityClassCount(
              report.eligibleCount, report.printerReports.length)
          : l10n.pipelineEligibilityOk;

  Widget _issueLine(
    ThemeData theme,
    AppLocalizations l10n,
    EligibilityIssue issue,
    bool advisory,
  ) {
    final detail = _detail(l10n, issue);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(advisory ? Icons.info_outline : Icons.remove_circle_outline,
              size: 16,
              color: advisory
                  ? theme.colorScheme.tertiary
                  : theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              detail == null
                  ? _text(l10n, issue)
                  : '${_text(l10n, issue)} ($detail)',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  String _text(AppLocalizations l10n, EligibilityIssue issue) =>
      switch (issue.kind) {
        EligibilityIssueKind.printerNotSet => l10n.pipelineIssuePrinterNotSet,
        EligibilityIssueKind.printerNotFound =>
          l10n.pipelineIssuePrinterNotFound,
        EligibilityIssueKind.printerDisabled =>
          l10n.pipelineIssuePrinterDisabled,
        EligibilityIssueKind.printerOffline => l10n.pipelineIssuePrinterOffline,
        EligibilityIssueKind.filamentTypeMismatch =>
          l10n.pipelineIssueFilamentType,
        EligibilityIssueKind.filamentColorMismatch =>
          l10n.pipelineIssueFilamentColor,
        EligibilityIssueKind.amsSlotMissing => l10n.pipelineIssueAmsSlotMissing,
        EligibilityIssueKind.filamentUnverified =>
          l10n.pipelineIssueFilamentUnverified,
        EligibilityIssueKind.noClassMatches =>
          l10n.pipelineIssueNoClassMatches,
        EligibilityIssueKind.classNotSet => l10n.pipelineIssueClassNotSet,
        // A newer server's reason, shown raw rather than dropped — untranslated
        // beats invisible when it is the thing blocking the run.
        EligibilityIssueKind.unknown => issue.rawKind,
      };

  /// Slot and expected/actual, when the kind carries them.
  String? _detail(AppLocalizations l10n, EligibilityIssue issue) {
    final parts = <String>[
      if (issue.slotIndex != null) l10n.pipelineIssueSlot(issue.slotIndex! + 1),
      if (issue.expected != null && issue.actual != null)
        l10n.pipelineIssueWantedGot(issue.expected!, issue.actual!)
      else if (issue.expected != null)
        l10n.pipelineIssueWanted(issue.expected!),
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }
}
