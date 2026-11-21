import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/format/duration_format.dart';
import '../../core/models/archive.dart';
import '../../core/models/plate_list.dart';
import '../../core/models/print_log_entry.dart';
import '../../core/models/print_run.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../common/print_thumbnail.dart';
import '../slicer/slice_providers.dart';
import 'archive_details.dart';
import 'archive_providers.dart';
import 'archive_runs.dart';

/// One card per plate of a multi-plate file — `PlateCard` of the web's archive
/// page: what is on it, its estimate, how its prints went, and a way to print
/// it again or to see its prints. Nothing for a single-plate file.
class ArchivePlatesSection extends ConsumerWidget {
  const ArchivePlatesSection({
    super.key,
    required this.archive,
    required this.onPhotos,
    required this.onVideo,
    required this.onPrintPlate,
  });

  final Archive archive;
  final ValueChanged<List<String>> onPhotos;
  final ValueChanged<int?> onVideo;
  final ValueChanged<int> onPrintPlate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plates =
        ref.watch(plateListProvider((true, archive.id))).value?.plates ??
        const <PlateInfo>[];
    if (plates.length < 2) return const SizedBox.shrink();
    final t = DashTokens.of(context);
    final runs = ref.watch(archiveRunsProvider(archive.id)).value ?? const [];
    return Padding(
      padding: const EdgeInsets.only(bottom: DashSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DashSpace.sm,
        children: [
          Text(
            AppLocalizations.of(context).archivePlatesTitle,
            style: t.bodyBold.copyWith(color: t.textPrimary),
          ),
          for (final plate in plates)
            _PlateCard(
              archive: archive,
              plate: plate,
              allRuns: runs,
              runs: [
                for (final r in runs)
                  if (r.plateId == plate.index) r,
              ],
              onPhotos: onPhotos,
              onVideo: onVideo,
              onPrint: () => onPrintPlate(plate.index),
              onShowPrints: () =>
                  ref
                          .read(archiveRunsPlateProvider(archive.id).notifier)
                          .state =
                      plate.index,
            ),
        ],
      ),
    );
  }
}

class _PlateCard extends ConsumerWidget {
  const _PlateCard({
    required this.archive,
    required this.plate,
    required this.allRuns,
    required this.runs,
    required this.onPhotos,
    required this.onVideo,
    required this.onPrint,
    required this.onShowPrints,
  });

  final Archive archive;
  final PlateInfo plate;

  /// Every print of the archive, which decides what a print without photos of
  /// its own shares ([runMedia]).
  final List<PrintLogEntry> allRuns;

  /// This plate's prints, newest first.
  final List<PrintLogEntry> runs;
  final ValueChanged<List<String>> onPhotos;
  final ValueChanged<int?> onVideo;
  final VoidCallback onPrint;
  final VoidCallback onShowPrints;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final media = [
      for (final r in runs) (run: r, media: runMedia(archive, allRuns, r)),
    ];
    // Its prints' photos, newest first, and the newest print's video.
    final photos = {for (final m in media) ...m.media.photos}.toList();
    final video = media
        .where((m) => m.media.ownVideo || m.media.archiveVideo)
        .firstOrNull;
    final good = runs.where((r) => r.status == 'completed').length;
    final failed = runs.where((r) => printRunIsFailure(r.status)).length;
    // The newest finished print with a measured time, against the estimate.
    final last = runs
        .where(
          (r) =>
              r.status == 'completed' &&
              (r.durationSeconds ?? 0) > 0 &&
              !r.durationUnmeasured,
        )
        .firstOrNull;
    final estimateSeconds = plate.printTimeSeconds ?? 0;
    final estimate = [
      if (estimateSeconds > 0) formatSeconds(l10n, estimateSeconds),
      if ((plate.filamentUsedGrams ?? 0) > 0)
        '${plate.filamentUsedGrams!.toStringAsFixed(1)} g',
    ].join(' · ');
    final contents = plate.objects.isNotEmpty
        ? plate.objects.join(', ')
        : plate.name;
    final blocked =
        ref.watch(archiveReprintBlockProvider(archive.createdById)) != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DashSpace.md),
      decoration: t.subCardBox(DashRadius.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DashSpace.xs,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (plate.thumbnailPath case final path?) ...[
                PrintThumbnail.path(path: path, size: DashSize.d56),
                const SizedBox(width: DashSpace.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: DashSpace.xs,
                  children: [
                    Text(l10n.archiveRunPlate(plate.index), style: t.titleSm),
                    if (contents != null && contents.isNotEmpty)
                      Text(contents, style: t.labelSoft),
                    if (estimate.isNotEmpty)
                      Text(
                        l10n.archivePlateEstimate(estimate),
                        style: t.label.copyWith(color: t.textSecondary),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (plate.filaments.isNotEmpty)
            Wrap(
              spacing: DashSpace.sm,
              runSpacing: DashSpace.xs,
              children: [
                for (final f in plate.filaments)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilamentDot(hex: f.color),
                      const SizedBox(width: DashSpace.xs),
                      Text(f.type, style: t.labelSoft),
                    ],
                  ),
              ],
            ),
          Wrap(
            spacing: DashSpace.md,
            runSpacing: DashSpace.xs,
            children: [
              Text(
                l10n.archiveGoodCount(good),
                style: t.label.copyWith(color: t.accentGreenInk),
              ),
              Text(
                l10n.archiveFailedCount(failed),
                style: t.label.copyWith(color: t.dangerInk),
              ),
              if (last != null && estimateSeconds > 0)
                Text(
                  l10n.archivePlateLastVsEstimate(
                    estimateDelta(last.durationSeconds!, estimateSeconds),
                  ),
                  style: t.label.copyWith(color: t.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: DashSpace.xs),
          Wrap(
            spacing: DashSpace.sm,
            runSpacing: DashSpace.sm,
            children: [
              if (photos.isNotEmpty)
                OutlinedButton.icon(
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(l10n.archiveRunPhotos(photos.length)),
                  onPressed: () => onPhotos(photos),
                ).tagged('archive.plate.photos'),
              if (video != null)
                OutlinedButton.icon(
                  icon: const Icon(Icons.movie_outlined),
                  label: Text(l10n.archiveRunVideo),
                  onPressed: () =>
                      onVideo(video.media.ownVideo ? video.run.id : null),
                ).tagged('archive.plate.video'),
              if (archive.isSliced)
                FilledButton.icon(
                  icon: const Icon(Icons.print),
                  label: Text(l10n.archivePrintThisPlate),
                  onPressed: blocked ? null : onPrint,
                ).tagged('archive.plate.print'),
              OutlinedButton(
                onPressed: runs.isEmpty ? null : onShowPrints,
                child: Text(l10n.archiveShowPlatePrints),
              ).tagged('archive.plate.show_prints'),
            ],
          ),
        ],
      ),
    );
  }
}
