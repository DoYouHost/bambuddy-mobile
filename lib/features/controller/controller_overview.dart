import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/printers_repository.dart';
import '../../core/format/datetime_format.dart';
import '../../core/format/duration_format.dart';
import '../../core/models/printer_status.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../common/media_image.dart';
import '../dashboard/controls_providers.dart';
import '../dashboard/print_lifecycle.dart';
import '../dashboard/skip_objects_screen.dart';
import '../dashboard/smart_plugs_providers.dart';
import '../dashboard/widgets/print_meta_row.dart';
import '../wall/wall_camera.dart';
import 'scale_to_fit.dart';
import 'controller_controls.dart';
import 'controller_faults.dart';
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
    // A large text size needs more room than the box has for everything at
    // once, so it has a layout of its own: still one screen, more compact.
    if (controllerPaged(context) && item != null) {
      return _LargeOverview(printerId: printerId, item: item);
    }
    final status = item?.status;
    final printing = status?.isPrinting ?? false;
    // A printer that does not answer cannot be told to pause: the card hides
    // the buttons then, and so does this.
    final controls = <Widget>[
      if (printing && status != null && (status.connected ?? false))
        _Lifecycle(printerId: printerId, status: status),
      if (printing && item != null)
        _SkipObjectsRow(printerId: printerId, printerName: item.printer.name),
    ];
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
              for (final control in controls) ...[
                const SizedBox(height: DashSpace.md),
                control,
              ],
            ],
          ),
        ),
        const SizedBox(width: DashSpace.md),
        Expanded(
          flex: 5,
          child: status == null
              ? const SizedBox.shrink()
              : _RightColumn(printerId: printerId, status: status),
        ),
      ],
    );
  }
}

/// The job, the readings, the speed and the switches, sharing the column's
/// height in the proportions of the design at 390 dp. Whatever the screen, the
/// column fills it and never scrolls: a taller screen stretches every row, a
/// shorter one squeezes them, and each row scales its text instead of
/// overflowing.
class _RightColumn extends ConsumerWidget {
  const _RightColumn({required this.printerId, required this.status});

  final int printerId;
  final PrinterStatus status;

  // Heights of the design (116 / 64 / 52 / 54 dp), used as shares.
  static const _jobShare = 116;
  static const _readingsShare = 64;
  static const _speedShare = 52;
  static const _switchesShare = 54;

  /// Without a job there is nothing to anchor the rows to, so they keep a
  /// reasonable height and sit in the middle instead of stretching over the
  /// whole column.
  static const _idleMaxHeight = 88.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refused = ref.watch(
      controlRefusedProvider(ControlPermission.control),
    );
    final hasPlug = ref.watch(
      smartPlugsProvider.select((s) => s.plugForPrinterCard(printerId) != null),
    );
    final job = status.isPrinting;
    final sections = <({int share, Widget child})>[
      if (job) (share: _jobShare, child: _JobCard(status: status)),
      if (controllerReadings(status).isNotEmpty)
        (share: _readingsShare, child: ControllerReadings(status: status)),
      if (controllerSpeedVisible(status, refused: refused))
        (
          share: _speedShare,
          child: ControllerSpeed(printerId: printerId, status: status),
        ),
      if (controllerLightVisible(status, refused: refused) || hasPlug)
        (
          share: _switchesShare,
          child: ControllerSwitches(printerId: printerId, status: status),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: job
          ? MainAxisAlignment.start
          : MainAxisAlignment.center,
      children: [
        for (final (i, section) in sections.indexed) ...[
          if (i > 0) const SizedBox(height: DashSpace.md),
          job
              ? Expanded(flex: section.share, child: section.child)
              : Flexible(
                  flex: section.share,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: _idleMaxHeight,
                    ),
                    child: section.child,
                  ),
                ),
        ],
      ],
    );
  }
}

/// The Overview at a large text size, still one screen: what grows with the text
/// is text, so what is not text gives way. The camera is a strip above the
/// buttons, and the readings are lines of a grid of two with no bar.
class _LargeOverview extends ConsumerWidget {
  const _LargeOverview({required this.printerId, required this.item});

  final int printerId;
  final PrinterWithStatus item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = item.status;
    final refused = ref.watch(
      controlRefusedProvider(ControlPermission.control),
    );
    final hasPlug = ref.watch(
      smartPlugsProvider.select((s) => s.plugForPrinterCard(printerId) != null),
    );
    final printing = status?.isPrinting ?? false;
    final reachable = status != null && (status.connected ?? false);
    final readings = status != null && controllerReadings(status).isNotEmpty;
    Widget column(List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) const SizedBox(height: DashSpace.sm),
          child,
        ],
      ],
    );
    final left = column([
      SizedBox(
        height: _stripHeight,
        child: _ViewCard(printerId: printerId, status: status),
      ),
      if (printing && reachable)
        _Lifecycle(printerId: printerId, status: status),
      if (printing)
        _SkipObjectsRow(printerId: printerId, printerName: item.printer.name),
      // The select's label sits on its top edge and, at this size, reaches
      // into the gap above it.
      if (status != null && controllerSpeedVisible(status, refused: refused))
        Padding(
          padding: const EdgeInsets.only(top: DashSpace.sm),
          child: ControllerSpeed(printerId: printerId, status: status),
        ),
    ]);
    final right = status == null
        ? const SizedBox.shrink()
        : column([
            if (printing) _JobCard(status: status),
            if (readings) ControllerReadings(status: status),
            if (controllerLightVisible(status, refused: refused) || hasPlug)
              ControllerSwitches(printerId: printerId, status: status),
          ]);
    return ControllerPage(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 4, child: left),
          const SizedBox(width: DashSpace.md),
          Expanded(flex: 6, child: right),
        ],
      ),
    );
  }

  /// The camera is a strip, as tall as this whatever the text.
  static const _stripHeight = 152.0;
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
    final onDark = DashTokens.resolve(Brightness.dark, t.brand);
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
            // On the picture, whatever it shows (a white bed too): a dark scrim and
            // the inks the dark theme uses, whichever theme the app is in.
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: DashAlpha.cover),
                borderRadius: BorderRadius.circular(DashRadius.xl),
              ),
              child: live
                  ? DashPill(
                      label: l10n.controllerLiveBadge,
                      accent: onDark.danger,
                      accentInk: onDark.dangerInk,
                      leadingDot: true,
                      dense: true,
                    )
                  : DashPill(
                      label: l10n.controllerPreviewBadge,
                      accent: onDark.textSecondary,
                      icon: Icons.image_outlined,
                      dense: true,
                    ),
            ),
          ),
          Positioned(
            right: DashSpace.md,
            top: DashSpace.md,
            // Opaque under its tint: the picture behind it is a camera frame.
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: t.cardGradient,
                borderRadius: BorderRadius.circular(DashSpace.xl),
              ),
              child: ControllerFaultChip(printerId: printerId),
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
          Icon(
            Icons.lock_outline,
            size: controllerIconSize(context, DashSpace.lg),
            color: t.textSecondary,
          ),
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

  /// The percentage is the one number read across the room, so it is large and
  /// grows with the card, between these bounds.
  static const _percentShare = 0.3;
  static const _percentMin = 28.0;
  static const _percentMax = 96.0;
  static const _percentOnPage = 52.0;

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
      // The least used of the three: left out where there is room for two.
      if (!controllerLargeText(context) &&
          status.layerNum != null &&
          status.totalLayers != null)
        PrintMetaItem(
          icon: Icons.layers_outlined,
          text: '${status.layerNum}/${status.totalLayers}',
        ),
    ];
    return Container(
      padding: EdgeInsets.all(
        controllerLargeText(context) ? DashSpace.sm : DashSpace.md,
      ),
      decoration: t.cardBox,
      child: LayoutBuilder(
        builder: (context, box) {
          // On a page there is no height to take a share of.
          final percentSize = box.hasBoundedHeight
              ? (box.maxHeight * _percentShare).clamp(_percentMin, _percentMax)
              : _percentOnPage;
          // At its size, whatever the share: the percentage is what gives, by
          // the card's height, and no text is scaled to fit.
          return Center(
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
                const SizedBox(height: DashSpace.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (progress != null && !preparing)
                      Text(
                        '${progress.toStringAsFixed(0)}%',
                        style: t.monoValue.copyWith(fontSize: percentSize),
                        // Already the biggest figure on the screen: it keeps its
                        // size at any text size so the lines under it stay in the card.
                        textScaler: MediaQuery.textScalerOf(
                          context,
                        ).clamp(maxScaleFactor: 1),
                      ),
                    const SizedBox(width: DashSpace.md),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: PrintMetaRow(items: meta),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DashSpace.md),
                DashProgressBar(
                  value: preparing || progress == null
                      ? null
                      : (progress / 100).clamp(0.0, 1.0),
                  height: DashSpace.sm,
                  color: status.isPaused ? t.accentOrange : null,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
