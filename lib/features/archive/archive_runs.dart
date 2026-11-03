import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/format/datetime_format.dart';
import '../../core/format/duration_format.dart';
import '../../core/format/filament_colour.dart';
import '../../core/format/money_format.dart';
import '../../core/models/archive.dart';
import '../../core/models/print_log_entry.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/print_run_labels.dart';
import '../slicer/slice_providers.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/app_context.dart';
import '../common/api_failure_snack.dart';
import '../common/dash_async.dart';
import 'archive_details.dart';
import 'outcome_sheet.dart';
import 'archive_providers.dart';
import 'print_outcome.dart';

/// What one print can open: its finish photos and whether it has a video —
/// its own, or the archive's for a print logged before prints kept their own.
typedef RunMedia = ({List<String> photos, bool ownVideo, bool archiveVideo});

/// `ArchiveDetailModal.tsx::mediaOf`, branch by branch.
///
/// A print with its own photo list (even an empty one) shows those. A null list
/// is a print logged before the redesign: it shares the archive's photos that
/// no other print holds, and the archive's video when no print holds that one.
RunMedia runMedia(
  Archive archive,
  List<PrintLogEntry> runs,
  PrintLogEntry run,
) {
  final fileVideo =
      archive.hasTimelapse &&
      !runs.any((r) => r.timelapsePath == archive.timelapsePath);
  final owned = {for (final r in runs) ...?r.photos};
  final shared = archive.photos.where((p) => !owned.contains(p)).toList();
  return (
    photos: run.photos ?? shared,
    ownVideo: run.timelapsePath != null,
    archiveVideo: run.timelapsePath == null && run.photos == null && fileVideo,
  );
}

/// Whether this session may give [run] a verdict of its own: a server that
/// keeps one per print and records verdicts, a completed print, and update
/// rights on the archive (the route checks the archive's owner).
bool runJudgeable(WidgetRef ref, Archive archive, PrintLogEntry run) =>
    run.status == 'completed' &&
    ref.watch(archiveRunsSupportedProvider).orFalse &&
    ref.watch(printOutcomeSupportedProvider).orFalse &&
    ref.watch(archiveUpdateAllowedProvider(archive.createdById));

/// How far a measured time ran from its estimate, as "+4%" / "-6%".
String estimateDelta(int seconds, int estimate) {
  final delta = ((seconds - estimate) / estimate * 100).round();
  return '${delta > 0 ? '+' : ''}$delta%';
}

/// A print's time next to its plate's estimate (#3375): a finished print by
/// how far it ran from it, one that stopped by how far it got, and an
/// unmeasured time (`~`) with the estimate but no percentage.
String? runTimeText(AppLocalizations l10n, PrintLogEntry run) {
  final seconds = run.durationSeconds;
  if (seconds == null || seconds <= 0) return null;
  final value =
      '${run.durationUnmeasured ? '~' : ''}${formatSeconds(l10n, seconds)}';
  final estimate = run.estimateSeconds;
  if (estimate == null || estimate <= 0) return value;
  final est = formatSeconds(l10n, estimate);
  if (run.status != 'completed') return l10n.archiveRunTimeOf(value, est);
  if (run.durationUnmeasured) return l10n.archiveRunWithEstimate(value, est);
  return l10n.archiveRunTimeVsEstimate(
    value,
    est,
    estimateDelta(seconds, estimate),
  );
}

String? runGramsText(AppLocalizations l10n, PrintLogEntry run) {
  final grams = run.filamentUsedGrams;
  if (grams == null) return null;
  final value = '${grams.toStringAsFixed(1)} g';
  final estimate = run.estimateGrams;
  if (estimate == null || estimate <= 0) return value;
  return l10n.archiveRunWithEstimate(value, '${estimate.toStringAsFixed(1)} g');
}

/// Statuses of an archive printed before each print was logged: its one print
/// is the archive's own outcome (`LEGACY_PRINTED` in the web).
const _legacyPrinted = {
  'completed',
  'failed',
  'aborted',
  'cancelled',
  'stopped',
};

/// The archive's prints, newest first, each opening onto its own figures,
/// note and media — the "Print history" of the web's archive page.
class ArchiveRunsSection extends ConsumerStatefulWidget {
  const ArchiveRunsSection({
    super.key,
    required this.archive,
    required this.onPhotos,
    required this.onVideo,
    required this.onReprint,
  });

  final Archive archive;

  /// Opens these photos of the archive.
  final ValueChanged<List<String>> onPhotos;

  /// Opens a print's own video, or with null the archive's.
  final ValueChanged<int?> onVideo;

  /// Opens the print form on this plate (null: the archive's).
  final ValueChanged<int?> onReprint;

  @override
  ConsumerState<ArchiveRunsSection> createState() => _ArchiveRunsSectionState();
}

class _ArchiveRunsSectionState extends ConsumerState<ArchiveRunsSection> {
  int? _open;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final archive = widget.archive;
    final runs = ref.watch(archiveRunsProvider(archive.id));
    final plates =
        ref.watch(plateListProvider((true, archive.id))).value?.plates ??
        const [];
    final multiPlate = plates.length > 1;
    final plate = ref.watch(archiveRunsPlateProvider(archive.id));

    Widget note(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: DashSpace.sm),
      child: Text(text, style: t.labelSoft),
    );

    final Widget body = switch (runs) {
      AsyncValue(:final value?) when value.isEmpty => note(
        _legacyPrinted.contains(archive.status)
            ? l10n.archiveRunsBeforeLog(
                printRunStatusLabel(l10n, archive.status),
              )
            : l10n.archiveRunsEmpty,
      ),
      AsyncValue(:final value?) => _list(context, value, multiPlate, plate),
      // As the sheet's other reads (`_SliceArchiveButton`): a failed read is
      // explained in place, never a broken sheet.
      AsyncValue(hasError: true) => note(l10n.connectFailed),
      _ => const Padding(
        padding: EdgeInsets.all(DashSpace.lg),
        child: DashLoading(),
      ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: DashSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.archiveRunsTitle,
            style: t.bodyBold.copyWith(color: t.textPrimary),
          ),
          if (multiPlate)
            Padding(
              padding: const EdgeInsets.only(top: DashSpace.sm),
              child: Wrap(
                spacing: DashSpace.xs,
                runSpacing: DashSpace.xs,
                children: [
                  for (final index in [null, ...plates.map((p) => p.index)])
                    ChoiceChip(
                      label: Text(
                        index == null
                            ? l10n.archiveRunsAllPlates
                            : l10n.archiveRunPlate(index),
                      ),
                      selected: plate == index,
                      onSelected: (_) =>
                          ref
                                  .read(
                                    archiveRunsPlateProvider(
                                      archive.id,
                                    ).notifier,
                                  )
                                  .state =
                              index,
                    ).tagged('archive.runs.plate_filter'),
                ],
              ),
            ),
          const SizedBox(height: DashSpace.sm),
          body,
        ],
      ),
    );
  }

  Widget _list(
    BuildContext context,
    List<PrintLogEntry> runs,
    bool multiPlate,
    int? plate,
  ) {
    final l10n = AppLocalizations.of(context);
    final shown = plate == null
        ? runs
        : runs.where((r) => r.plateId == plate).toList();
    if (shown.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: DashSpace.sm),
        child: Text(
          l10n.archiveRunsPlateEmpty,
          style: DashTokens.of(context).labelSoft,
        ),
      );
    }
    // A plate column only where there is more than one plate to tell apart.
    final showPlate = multiPlate || runs.any((r) => (r.plateId ?? 1) > 1);
    return Column(
      spacing: DashSpace.sm,
      children: [
        for (final run in shown)
          _RunTile(
            archive: widget.archive,
            run: run,
            showPlate: showPlate,
            media: runMedia(widget.archive, runs, run),
            open: _open == run.id,
            onToggle: () =>
                setState(() => _open = _open == run.id ? null : run.id),
            onPhotos: widget.onPhotos,
            onVideo: widget.onVideo,
            onReprint: widget.onReprint,
          ),
      ],
    );
  }
}

class _RunTile extends ConsumerWidget {
  const _RunTile({
    required this.archive,
    required this.run,
    required this.showPlate,
    required this.media,
    required this.open,
    required this.onToggle,
    required this.onPhotos,
    required this.onVideo,
    required this.onReprint,
  });

  final Archive archive;
  final PrintLogEntry run;
  final bool showPlate;
  final RunMedia media;
  final bool open;
  final VoidCallback onToggle;
  final ValueChanged<List<String>> onPhotos;
  final ValueChanged<int?> onVideo;
  final ValueChanged<int?> onReprint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final dates = DateTimeFormats.of(context);
    final currency = ref.watch(currencySymbolProvider);
    final (tone, toneInk) = printRunTone(t, run.status);
    final where = [
      run.printerName ?? l10n.archiveRunNoPrinter,
      if (showPlate && run.plateId != null) l10n.archiveRunPlate(run.plateId!),
    ];
    final numbers = [
      ?runTimeText(l10n, run),
      ?runGramsText(l10n, run),
      if (run.cost != null) formatMoneyValue(currency, run.cost!),
    ];
    final colours = filamentColourTokens(run.filamentColor);
    final types = filamentTypeTokens(run.filamentType).toSet();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(DashRadius.xl),
        onTap: onToggle,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(DashSpace.md),
          decoration: BoxDecoration(
            color: t.subCard,
            borderRadius: BorderRadius.circular(DashRadius.xl),
            border: Border.all(color: t.subCardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    open ? Icons.expand_less : Icons.expand_more,
                    size: DashIcon.md,
                    color: t.textTertiary,
                  ),
                  const SizedBox(width: DashSpace.xs),
                  Expanded(
                    child: Text(
                      dates.dateTime(run.startedAt ?? run.createdAt),
                      style: t.titleSm,
                    ),
                  ),
                  const SizedBox(width: DashSpace.sm),
                  DashPill(
                    dense: true,
                    label: printRunStatusLabel(l10n, run.status),
                    accent: tone,
                    accentInk: toneInk,
                  ),
                ],
              ),
              if (run.userVerdict != null || run.awaitsVerdict) ...[
                const SizedBox(height: DashSpace.xs),
                Wrap(
                  spacing: DashSpace.sm,
                  runSpacing: DashSpace.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _VerdictPill(run: run),
                    // The question is answered from the row itself, as the
                    // web's "Confirm outcome" on it, not only once opened.
                    if (run.awaitsVerdict && runJudgeable(ref, archive, run))
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.thumbs_up_down_outlined),
                        label: Text(l10n.archiveRunSetOutcome),
                        onPressed: () => showOutcomeSheet(
                          context,
                          archive.id,
                          runId: run.id,
                        ),
                      ).tagged('archive.run.answer'),
                  ],
                ),
              ],
              const SizedBox(height: DashSpace.xs),
              Text(
                where.join(' · '),
                style: t.label.copyWith(color: t.textSecondary),
              ),
              if (numbers.isNotEmpty) ...[
                const SizedBox(height: DashSpace.xs),
                Text(
                  numbers.join(' · '),
                  style: t.monoValue.copyWith(color: t.textSecondary),
                ),
              ],
              if (colours.isNotEmpty || types.isNotEmpty) ...[
                const SizedBox(height: DashSpace.xs),
                Wrap(
                  spacing: DashSpace.xs,
                  runSpacing: DashSpace.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final hex in colours) FilamentDot(hex: hex),
                    if (types.isNotEmpty)
                      Text(types.join(', '), style: t.labelSoft),
                  ],
                ),
              ],
              if (open) ...[
                const SizedBox(height: DashSpace.md),
                _RunDetails(
                  archive: archive,
                  run: run,
                  media: media,
                  onPhotos: onPhotos,
                  onVideo: onVideo,
                  onReprint: onReprint,
                ),
              ],
            ],
          ),
        ),
      ).tagged('archive.run'),
    );
  }
}

class _VerdictPill extends StatelessWidget {
  const _VerdictPill({required this.run});

  final PrintLogEntry run;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final verdict = run.userVerdict;
    final (label, icon, accent, ink) = switch (verdict) {
      PrintVerdict.good => (
        l10n.outcomeGoodPart,
        Icons.thumb_up_alt,
        t.accentGreen,
        t.accentGreenInk,
      ),
      PrintVerdict.reject => (
        l10n.outcomeRejected,
        Icons.thumb_down_alt,
        t.danger,
        t.dangerInk,
      ),
      null => (
        l10n.outcomeAwaiting,
        Icons.help_outline,
        t.accentOrange,
        t.accentOrangeInk,
      ),
    };
    final source = verdict == null
        ? null
        : verdictSourceLabel(l10n, run.userVerdictSource);
    final pill = DashPill(
      dense: true,
      label: label,
      icon: icon,
      accent: accent,
      accentInk: ink,
    );
    return source == null ? pill : Tooltip(message: source, child: pill);
  }
}

/// What a print opens onto: its photos and video, then its facts.
class _RunDetails extends ConsumerStatefulWidget {
  const _RunDetails({
    required this.archive,
    required this.run,
    required this.media,
    required this.onPhotos,
    required this.onVideo,
    required this.onReprint,
  });

  final Archive archive;
  final PrintLogEntry run;
  final RunMedia media;
  final ValueChanged<List<String>> onPhotos;
  final ValueChanged<int?> onVideo;
  final ValueChanged<int?> onReprint;

  @override
  ConsumerState<_RunDetails> createState() => _RunDetailsState();
}

class _RunDetailsState extends ConsumerState<_RunDetails> {
  bool _saving = false;

  PrintLogEntry get run => widget.run;

  /// Writes the print's note, an empty one clearing it, and reloads the list.
  Future<void> _editNote() async {
    final l10n = AppLocalizations.of(context);
    final notes = await promptName(
      context,
      title: run.notes == null
          ? l10n.archiveRunAddNote
          : l10n.archiveRunEditNote,
      label: l10n.archiveRunNote,
      initial: run.notes,
      id: 'archive.run.note_prompt',
      allowEmpty: true,
      maxLines: 6,
      keyboardType: TextInputType.multiline,
    );
    if (notes == null || !mounted || _saving) return;
    final (:providers, :messenger) = detachFrom(context);
    setState(() => _saving = true);
    try {
      await providers
          .read(printLogRepositoryProvider)
          .updateEntry(run.id, notes: notes);
      providers.invalidate(archiveRunsProvider(widget.archive.id));
      messenger.snack(l10n.archiveRunNoteSaved);
    } on AppApiException catch (e) {
      showApiFailure(
        mounted ? messenger : null,
        e,
        l10n,
        action: 'archive.run.edit_note',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final dates = DateTimeFormats.of(context);
    final started = dates.dateTime(run.startedAt ?? run.createdAt);
    final ended = run.completedAt == null
        ? null
        : dates.dateTime(run.completedAt!);
    final hasVideo = media.ownVideo || media.archiveVideo;
    // Both writes are silent drops before the archive redesign.
    final perPrint = ref.watch(archiveRunsSupportedProvider).orFalse;
    final canJudge = runJudgeable(ref, widget.archive, run);
    final canNote =
        perPrint && ref.watch(archiveUpdateAllowedProvider(run.createdById));
    final actions = [
      if (canJudge)
        OutlinedButton.icon(
          icon: const Icon(Icons.thumbs_up_down_outlined),
          label: Text(
            run.userVerdict == null
                ? l10n.archiveRunSetOutcome
                : l10n.archiveRunChangeOutcome,
          ),
          onPressed: () =>
              showOutcomeSheet(context, widget.archive.id, runId: run.id),
        ).tagged('archive.run.outcome'),
      if (canNote)
        OutlinedButton.icon(
          icon: const Icon(Icons.sticky_note_2_outlined),
          label: Text(
            run.notes == null
                ? l10n.archiveRunAddNote
                : l10n.archiveRunEditNote,
          ),
          onPressed: _saving ? null : _editNote,
        ).tagged('archive.run.edit_note'),
      // Only a sliced file prints; the reason a reprint is refused is on the
      // sheet's own print buttons above.
      if (widget.archive.isSliced)
        OutlinedButton.icon(
          icon: const Icon(Icons.replay),
          label: Text(l10n.archiveRunReprint),
          onPressed:
              ref.watch(
                    archiveReprintBlockProvider(widget.archive.createdById),
                  ) ==
                  null
              ? () => widget.onReprint(run.plateId ?? widget.archive.plateId)
              : null,
        ).tagged('archive.run.reprint'),
    ];
    final facts = <(String, String)>[
      (
        l10n.archiveRunStartedEnded,
        ended == null ? started : '$started – $ended',
      ),
      if (run.energyKwh != null)
        (
          l10n.archiveRunEnergy,
          l10n.printLogEnergy(run.energyKwh!.toStringAsFixed(2)),
        ),
      if (run.failureReason != null)
        (
          l10n.archiveRunFailureReason,
          failureReasonLabel(l10n, run.failureReason),
        ),
      if (run.createdByUsername != null)
        (l10n.archiveRunStartedBy, run.createdByUsername!),
      (l10n.archiveRunNote, run.notes ?? '—'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DashSpace.sm,
      children: [
        if (media.photos.isNotEmpty || hasVideo)
          Wrap(
            spacing: DashSpace.sm,
            runSpacing: DashSpace.sm,
            children: [
              if (media.photos.isNotEmpty)
                OutlinedButton.icon(
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(l10n.archiveRunPhotos(media.photos.length)),
                  onPressed: () => widget.onPhotos(media.photos),
                ).tagged('archive.run.photos'),
              if (hasVideo)
                OutlinedButton.icon(
                  icon: const Icon(Icons.movie_outlined),
                  label: Text(l10n.archiveRunVideo),
                  onPressed: () =>
                      widget.onVideo(media.ownVideo ? run.id : null),
                ).tagged('archive.run.video'),
            ],
          ),
        for (final (label, value) in facts)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: t.labelSoft),
              Text(value, style: t.body),
            ],
          ),
        if (actions.isNotEmpty)
          Wrap(
            spacing: DashSpace.sm,
            runSpacing: DashSpace.sm,
            children: actions,
          ),
      ],
    );
  }
}
