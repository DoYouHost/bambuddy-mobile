import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/datetime_format.dart';
import '../../core/format/duration_format.dart';
import '../../core/models/printer_status.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../common/media_image.dart';
import '../dashboard/controls_providers.dart';
import '../dashboard/print_lifecycle.dart';
import '../dashboard/skip_objects_screen.dart';
import '../dashboard/widgets/print_meta_row.dart';
import '../wall/wall_camera.dart';
import 'controller_providers.dart';

/// The Overview tab: what the printer is doing and the controls used while it
/// does it ([docs/single-printer-controller.md] §2). Reads its printer through
/// [controllerPrinterProvider] only.
class ControllerOverview extends ConsumerWidget {
  const ControllerOverview({super.key, required this.printerId});

  final int printerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(controllerPrinterProvider(printerId)).item;
    final status = item?.status;
    final printing = status?.isPrinting ?? false;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _ViewCard(printerId: printerId, status: status),
              ),
              if (printing && status != null) ...[
                const SizedBox(height: DashSpace.md),
                _Lifecycle(printerId: printerId, status: status),
                const SizedBox(height: DashSpace.md),
                _SkipObjectsRow(
                  printerId: printerId,
                  printerName: item!.printer.name,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: DashSpace.md),
        Expanded(
          flex: 5,
          child: Align(
            alignment: Alignment.topCenter,
            child: printing && status != null
                ? _JobCard(status: status)
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

/// The camera, or — with "Live camera" off — the cover of the file being
/// printed. Without a cover, an icon and "No preview".
class _ViewCard extends ConsumerWidget {
  const _ViewCard({required this.printerId, required this.status});

  final int printerId;
  final PrinterStatus? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final liveSetting = ref.watch(
      controllerPrefsProvider.select((p) => p.liveCamera),
    );
    // A printer that does not answer has no stream; the file preview is what is
    // left to show, so it takes the place of a dark rectangle.
    final live = liveSetting && (status?.connected ?? false);
    return Container(
      decoration: t.cardBox,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          LayoutBuilder(
            builder: (context, box) => live
                ? WallCamera(
                    printerId: printerId,
                    cacheWidth:
                        (box.maxWidth * MediaQuery.devicePixelRatioOf(context))
                            .round(),
                  )
                : _Preview(
                    coverUrl: (status?.isCalibration ?? false)
                        ? null
                        : status?.coverUrl,
                    size: box.biggest,
                  ),
          ),
          Positioned(
            left: DashSpace.md,
            top: DashSpace.md,
            child: live
                ? DashPill(
                    label: l10n.controllerLiveBadge,
                    accent: t.danger,
                    accentInk: t.dangerInk,
                    leadingDot: true,
                    dense: true,
                  )
                : DashPill(
                    label: l10n.controllerPreviewBadge,
                    accent: t.textSecondary,
                    icon: Icons.image_outlined,
                    dense: true,
                  ),
          ),
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.coverUrl, required this.size});

  final String? coverUrl;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final url = coverUrl;
    if (url == null || url.isEmpty) return const _NoPreview();
    return MediaImage(
      path: url,
      width: size.width,
      height: size.height,
      fit: BoxFit.contain,
      placeholder: (status) => status == MediaImageStatus.loading
          ? const SizedBox.expand()
          : const _NoPreview(),
    );
  }
}

class _NoPreview extends StatelessWidget {
  const _NoPreview();

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_not_supported_outlined, color: t.textTertiary),
          const SizedBox(height: DashSpace.sm),
          Text(
            AppLocalizations.of(context).controllerNoPreview,
            style: t.bodySoft,
          ),
        ],
      ),
    );
  }
}

/// Pause or resume, and stop. Stop goes through the same confirmation as the
/// printer card's; a session the server refuses control to sees why instead of
/// buttons that would only fail.
class _Lifecycle extends ConsumerWidget {
  const _Lifecycle({required this.printerId, required this.status});

  final int printerId;
  final PrinterStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    if (ref.watch(controlRefusedProvider(ControlPermission.control))) {
      return Row(
        children: [
          Icon(Icons.lock_outline, size: DashSpace.lg, color: t.textSecondary),
          const SizedBox(width: DashSpace.sm),
          Expanded(
            child: Text(
              l10n.ctrlForbidden,
              style: t.labelSoft.copyWith(color: t.textSecondary),
            ),
          ),
        ],
      );
    }
    final pending = ref.watch(
      controlsProvider.select((s) => s.pendingFor(printerId)),
    );
    final paused = status.isPaused;
    final first = paused ? ControlAction.resume : ControlAction.pause;
    final firstLabel = paused ? l10n.ctrlResume : l10n.ctrlPause;
    return ButtonPair(
      primaryLabel: firstLabel,
      secondaryLabel: l10n.ctrlStop,
      secondaryStyle: dashDangerButtonStyle(t),
      primary: logTag(
        paused ? 'controller.resume' : 'controller.pause',
        FilledButton.icon(
          icon: Icon(paused ? Icons.play_arrow : Icons.pause),
          label: Text(firstLabel),
          onPressed: pending.isBusy(first)
              ? null
              : () => runPrintAction(context, ref, printerId, first),
        ),
      ),
      secondary: logTag(
        'controller.stop',
        FilledButton.icon(
          style: dashDangerButtonStyle(t),
          icon: const Icon(Icons.stop),
          label: Text(l10n.ctrlStop),
          onPressed: pending.isBusy(ControlAction.stop)
              ? null
              : () => stopPrintConfirmed(
                  context,
                  ref,
                  printerId,
                  confirmId: 'controller.stop_confirm',
                ),
        ),
      ),
    );
  }
}

class _SkipObjectsRow extends StatelessWidget {
  const _SkipObjectsRow({required this.printerId, required this.printerName});

  final int printerId;
  final String printerName;

  static const _minHeight = 48.0;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final radius = BorderRadius.circular(DashSpace.md + DashSpace.xs);
    return logTag(
      'controller.skip_objects',
      Material(
        color: t.subCard,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: t.subCardBorder),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SkipObjectsScreen(
                printerId: printerId,
                printerName: printerName,
              ),
            ),
          ),
          child: Container(
            constraints: const BoxConstraints(minHeight: _minHeight),
            padding: const EdgeInsets.symmetric(horizontal: DashSpace.md),
            child: Row(
              children: [
                Icon(Icons.layers_clear_outlined, color: t.textSecondary),
                const SizedBox(width: DashSpace.md),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).skipObjectsTitle,
                    style: t.bodyBold.copyWith(color: t.textPrimary),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: t.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The job: file, progress with its percentage, time left, ETA and layer.
class _JobCard extends StatelessWidget {
  const _JobCard({required this.status});

  final PrinterStatus status;

  /// The percentage is the one number read across the room, so it is large.
  static const _percentSize = 44.0;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final name = status.currentPrint ?? status.gcodeFile;
    final progress = status.progress;
    // While the printer is still heating or levelling the bar runs
    // indeterminate and no percentage is shown: a 0% there reads as a stall.
    final preparing = status.isPreparing;
    final remaining = status.remainingTime;
    final fmt = DateTimeFormats.of(context);
    final meta = <PrintMetaItem>[
      if (remaining != null && remaining > 0) ...[
        PrintMetaItem(
          icon: Icons.schedule,
          text: l10n.remaining(formatMinutes(l10n, remaining)),
        ),
        PrintMetaItem(
          icon: Icons.flag_outlined,
          text: l10n.eta(
            fmt.time(DateTime.now().add(Duration(minutes: remaining))),
          ),
        ),
      ],
      if (status.layerNum != null && status.totalLayers != null)
        PrintMetaItem(
          icon: Icons.layers_outlined,
          text: '${status.layerNum}/${status.totalLayers}',
        ),
    ];
    return Container(
      padding: const EdgeInsets.all(DashSpace.lg),
      decoration: t.cardBox,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (name != null)
            Text(
              name,
              style: t.titleMd,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (progress != null && !preparing) ...[
            const SizedBox(height: DashSpace.sm),
            Text(
              '${progress.toStringAsFixed(0)}%',
              style: t.monoValue.copyWith(fontSize: _percentSize),
            ),
          ],
          const SizedBox(height: DashSpace.md),
          DashProgressBar(
            value: preparing || progress == null
                ? null
                : (progress / 100).clamp(0.0, 1.0),
            height: DashSpace.sm,
            color: status.isPaused ? t.accentOrange : null,
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: DashSpace.md),
            PrintMetaRow(items: meta),
          ],
        ],
      ),
    );
  }
}
