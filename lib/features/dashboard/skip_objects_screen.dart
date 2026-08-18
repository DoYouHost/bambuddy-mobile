import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/models/printable_object.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../common/camera_token_image_recovery.dart';
import '../common/confirm_dialog.dart';
import 'skip_objects_providers.dart';
import 'ws_providers.dart';

/// Skip-objects screen: shows the current print's objects (with their printer
/// display IDs) over a top-down build-plate render, and lets the user select
/// failed ones by tapping their shape on the plate or their row in the list
/// below. Skipping is irreversible, so the whole selection is confirmed once,
/// in a single batched request. Selection is blocked until layer 2 (the
/// printer can't skip the first layer) and when the API key lacks
/// `can_control_printer`.
class SkipObjectsScreen extends ConsumerStatefulWidget {
  const SkipObjectsScreen({
    super.key,
    required this.printerId,
    required this.printerName,
  });

  final int printerId;
  final String printerName;

  @override
  ConsumerState<SkipObjectsScreen> createState() => _SkipObjectsScreenState();
}

class _SkipObjectsScreenState extends ConsumerState<SkipObjectsScreen>
    with CameraTokenImageRecovery {
  /// Object ids selected to skip, pending the batch confirmation.
  final _selected = <int>{};

  /// True while the confirmed batch is in flight (bottom bar spinner + lock).
  bool _skipping = false;

  /// Sticky once the server rejects a skip for lack of permission.
  bool _forbidden = false;

  /// True while two fingers manipulate the plate preview — freezes page scroll
  /// so the pinch/pan doesn't also drag the whole list.
  bool _plateInteracting = false;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(skipObjectsProvider(widget.printerId));
    final status =
        ref.watch(printerStatusesProvider.select((m) => m[widget.printerId]));
    final layerNum = status?.layerNum ?? 0;
    final canSkipLayer = layerNum > 1;
    final canSelect = canSkipLayer && !_forbidden && !_skipping;

    return Scaffold(
      appBar: loggedAppBar(
        AppBar(
          title: Text(l10n.skipObjectsTitle),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(20),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.printerName,
                  style: TextStyle(fontSize: 12, color: t.textSecondary),
                ),
              ),
            ),
          ),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _ErrorState(
          message: l10n.skipObjectsLoadFailed,
          onRetry: () =>
              ref.read(skipObjectsProvider(widget.printerId).notifier).refresh(),
        ),
        data: (data) => data.objects.isEmpty
            ? _EmptyState(
                onReload: () => ref
                    .read(skipObjectsProvider(widget.printerId).notifier)
                    .refresh(reload: true),
              )
            : RefreshIndicator(
                onRefresh: () => ref
                    .read(skipObjectsProvider(widget.printerId).notifier)
                    .refresh(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  physics: _plateInteracting
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  children: [
                    _InfoBanner(data: data),
                    const SizedBox(height: 12),
                    if (!canSkipLayer) ...[
                      _LayerWarning(layer: layerNum),
                      const SizedBox(height: 12),
                    ],
                    _PlatePreview(
                      printerId: widget.printerId,
                      coverUrl: status?.coverUrl,
                      data: data,
                      recovery: this,
                      selected: _selected,
                      canSelect: canSelect,
                      onToggle: _toggleSelected,
                      onInteractingChanged: (v) {
                        if (v != _plateInteracting) {
                          setState(() => _plateInteracting = v);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    if (_selected.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          l10n.skipObjectsSelectHint,
                          style: TextStyle(fontSize: 12, color: t.textTertiary),
                        ),
                      ),
                    for (final obj in data.objects)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ObjectTile(
                          object: obj,
                          selected: _selected.contains(obj.id),
                          canSelect: canSelect,
                          blockedReason: _forbidden
                              ? l10n.ctrlForbidden
                              : (!canSkipLayer
                                  ? l10n.skipObjectsWaitForLayer(layerNum)
                                  : null),
                          onToggle: () => _toggleSelected(obj),
                        ),
                      ),
                  ],
                ),
              ),
      ),
      bottomNavigationBar:
          _selected.isEmpty ? null : _confirmBar(t, l10n, canSelect),
    );
  }

  /// Toggles one object in/out of the pending selection. The marker and tile
  /// widgets already withhold this callback (`onTap: null`) for a skipped
  /// object or while selection is blocked, so no gating is repeated here.
  void _toggleSelected(PrintableObject obj) {
    setState(() {
      if (!_selected.remove(obj.id)) _selected.add(obj.id);
    });
  }

  Widget _confirmBar(DashTokens t, AppLocalizations l10n, bool canConfirm) =>
      DecoratedBox(
        decoration: BoxDecoration(
          color: t.navBar,
          border: Border(top: BorderSide(color: t.hairline)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.skipObjectsSelectedCount(_selected.length),
                    style: TextStyle(
                      fontFamily: DashTokens.fontUi,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: t.textSecondary,
                    ),
                  ),
                ),
                if (_skipping)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  FilledButton(
                    onPressed: canConfirm ? _confirmSkipSelected : null,
                    style: FilledButton.styleFrom(backgroundColor: t.danger),
                    child: Text(l10n.skipObjectsSkip),
                  ).tagged('skip_objects.skip'),
              ],
            ),
          ),
        ),
      );

  Future<void> _confirmSkipSelected() async {
    final l10n = AppLocalizations.of(context);
    final data = ref.read(skipObjectsProvider(widget.printerId)).valueOrNull;
    if (data == null) return;
    final objs =
        data.objects.where((o) => _selected.contains(o.id)).toList();
    if (objs.isEmpty) return;

    final names = objs.map((o) => o.name).join(', ');
    final confirmed = await confirmDialog(
      context,
      title: l10n.skipObjectsConfirmTitle(objs.length),
      message: l10n.skipObjectsConfirmBody(objs.length, names),
      confirmLabel: l10n.skipObjectsSkip,
      destructive: true,
      id: 'skip_objects',
    );
    if (!confirmed || !mounted) return;

    setState(() => _skipping = true);
    final ids = _selected.toList();
    final result = await ref
        .read(skipObjectsProvider(widget.printerId).notifier)
        .skip(ids);
    if (!mounted) return;
    setState(() {
      _skipping = false;
      if (result.isForbidden) _forbidden = true;
      if (result.isOk) _selected.clear();
    });

    final msg = result.messageFor(l10n) ??
        l10n.skipObjectsSkippedToast(objs.length, names);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// "Match IDs with your printer display" banner + skipped/total counter.
class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.data});

  final PrintableObjects data;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.accentBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.accentBlue.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.desktop_windows_outlined, size: 20, color: t.accentBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.skipObjectsMatchInfo,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: t.textPrimary,
                  ),
                ),
                Text(
                  l10n.skipObjectsMatchHint,
                  style: TextStyle(fontSize: 11, color: t.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            l10n.skipObjectsCounter(data.skippedCount, data.total),
            style: TextStyle(fontSize: 12, color: t.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Amber warning: the first layer can't be skipped, wait for layer 2+.
class _LayerWarning extends StatelessWidget {
  const _LayerWarning({required this.layer});

  final int layer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const amber = Color(0xFFF59E0B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 18, color: amber),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.skipObjectsWaitForLayer(layer),
              style: const TextStyle(fontSize: 12, color: amber),
            ),
          ),
        ],
      ),
    );
  }
}

/// Top-down plate render with object-ID markers overlaid at their plate
/// positions. Auth for the image is the camera stream token in `?token=`.
class _PlatePreview extends ConsumerStatefulWidget {
  const _PlatePreview({
    required this.printerId,
    required this.coverUrl,
    required this.data,
    required this.recovery,
    required this.selected,
    required this.canSelect,
    required this.onToggle,
    required this.onInteractingChanged,
  });

  final int printerId;
  final String? coverUrl;
  final PrintableObjects data;
  final CameraTokenImageRecovery recovery;

  /// Object ids currently selected to skip — drawn as the marker's "selected"
  /// state on the plate.
  final Set<int> selected;
  final bool canSelect;
  final ValueChanged<PrintableObject> onToggle;

  /// Fires true once a second finger lands on the plate (zoom/pan) and false
  /// when it drops back below two — the screen freezes page scroll while true.
  final ValueChanged<bool> onInteractingChanged;

  @override
  ConsumerState<_PlatePreview> createState() => _PlatePreviewState();
}

class _PlatePreviewState extends ConsumerState<_PlatePreview> {
  final _controller = TransformationController();
  int _pointers = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updatePointers(int delta) {
    setState(() => _pointers = math.max(0, _pointers + delta));
    widget.onInteractingChanged(_pointers >= 2);
  }

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final coverUrl = widget.coverUrl;
    final data = widget.data;
    final baseUrl = ref.watch(serverProfileProvider)?.baseUrl;

    // Synthetic build-plate look for printers without a rendered cover (e.g.
    // demo mode) — nicer than a lone icon and gives the ID markers a surface.
    final placeholderBg = CustomPaint(
      painter: _PlateGridPainter(line: t.textTertiary.withValues(alpha: 0.18)),
      child: const SizedBox.expand(),
    );

    // Background layer: the top-down render when available, else a plain grid
    // (e.g. demo mode, which has no rendered covers). Markers overlay either way.
    Widget background;
    if (baseUrl == null || coverUrl == null) {
      background = placeholderBg;
    } else {
      background = ref.watch(cameraTokenProvider).when(
            loading: () => placeholderBg,
            error: (_, _) => placeholderBg,
            data: (token) => Image.network(
              '$baseUrl$coverUrl?view=top&token=$token',
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (_, error, _) {
                widget.recovery.recoverCameraTokenOnError(error, token);
                return placeholderBg;
              },
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : placeholderBg,
            ),
          );
    }

    // Plate content (background + ID markers). Wrapped in an InteractiveViewer
    // so it pinch-zooms in place — no separate fullscreen view. The count badge
    // sits outside the viewer so it stays fixed while the plate zooms/pans.
    final plate = Container(
      color: const Color(0xFF0A0C08),
      child: Stack(
        fit: StackFit.expand,
        children: [
          background,
          for (var i = 0; i < data.objects.length; i++)
            _ObjectMarker(
              object: data.objects[i],
              fraction: _markerFraction(data, i),
              sizeFraction: _markerSizeFraction(data, i),
              tokens: t,
              selected: widget.selected.contains(data.objects[i].id),
              canSelect: widget.canSelect,
              onTap: () => widget.onToggle(data.objects[i]),
            ),
        ],
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // A single finger never manipulates the plate — it falls through to
            // page scroll / pull-to-refresh. Two fingers zoom AND pan; while
            // they're down the screen freezes list scroll (via
            // onInteractingChanged) so the gesture doesn't drag the whole page.
            // Double-tap resets to 1× to hand scrolling back to the page.
            Listener(
              onPointerDown: (_) => _updatePointers(1),
              onPointerUp: (_) => _updatePointers(-1),
              onPointerCancel: (_) => _updatePointers(-1),
              child: GestureDetector(
                onDoubleTap: () => _controller.value = Matrix4.identity(),
                child: InteractiveViewer(
                  transformationController: _controller,
                  minScale: 1,
                  maxScale: 6,
                  // Pan only with two fingers down; a lone finger stays free for
                  // page scroll instead of dragging the plate.
                  panEnabled: _pointers >= 2,
                  clipBehavior: Clip.hardEdge,
                  child: plate,
                ),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: _CountBadge(count: data.activeCount),
            ),
          ],
        ),
      ),
    );
  }
}

/// Maps an object's plate coordinates to a 0..1 fraction of the square render.
/// Uses [PrintableObjects.bboxAll] (the render's visible area) when available,
/// then a full-plate fallback, then a grid when positions are missing —
/// mirrors the web client so IDs land on the right parts.
Offset _markerFraction(PrintableObjects data, int index) {
  final obj = data.objects[index];
  final bbox = data.bboxAll;
  double x, y;
  if (obj.x != null && obj.y != null && bbox != null) {
    final xMin = bbox[0], yMin = bbox[1], xMax = bbox[2], yMax = bbox[3];
    final w = xMax - xMin, h = yMax - yMin;
    const pad = 0.08, content = 1 - pad * 2;
    x = w == 0 ? 0.5 : pad + ((obj.x! - xMin) / w) * content;
    // Image Y grows downward; plate Y grows toward the back → invert.
    y = h == 0 ? 0.5 : pad + ((yMax - obj.y!) / h) * content;
  } else if (obj.x != null && obj.y != null) {
    const plate = 256.0;
    x = obj.x! / plate;
    y = 1 - obj.y! / plate;
  } else {
    final cols = math.max(1, math.sqrt(data.objects.length).ceil());
    final rows = math.max(1, (data.objects.length / cols).ceil());
    final col = index % cols, row = index ~/ cols;
    x = 0.15 + col * (0.7 / cols) + 0.35 / cols;
    y = 0.15 + row * (0.7 / rows) + 0.35 / rows;
  }
  return Offset(x.clamp(0.05, 0.95), y.clamp(0.05, 0.95));
}

/// Maps an object's footprint to a 0..1-fraction (width, height) of the square
/// render, alongside [_markerFraction]'s position. Real objects have no known
/// footprint today (see [PrintableObject]), so this only varies per object in
/// demo — everywhere else every marker gets the same fixed badge size.
Size _markerSizeFraction(PrintableObjects data, int index) {
  const fallback = 0.12;
  final obj = data.objects[index];
  final bbox = data.bboxAll;
  if (obj.width == null || obj.height == null || bbox == null) {
    return const Size(fallback, fallback);
  }
  final bboxW = bbox[2] - bbox[0], bboxH = bbox[3] - bbox[1];
  const pad = 0.08, content = 1 - pad * 2;
  final w = bboxW == 0 ? fallback : (obj.width! / bboxW) * content;
  final h = bboxH == 0 ? fallback : (obj.height! / bboxH) * content;
  return Size(w.clamp(0.08, 0.9), h.clamp(0.08, 0.9));
}

/// Draws a faint 8×8 build-plate grid inside a rounded border — a stand-in for
/// the real top-down render when a printer has no cover image.
class _PlateGridPainter extends CustomPainter {
  const _PlateGridPainter({required this.line});

  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = line
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const cells = 8;
    for (var i = 1; i < cells; i++) {
      final dx = size.width * i / cells;
      final dy = size.height * i / cells;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), paint);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), paint);
    }
    // Brighter outer frame so the plate edge reads clearly.
    canvas.drawRect(
      Offset.zero & size,
      paint..color = line.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(_PlateGridPainter oldDelegate) => oldDelegate.line != line;
}

/// Part-shaped tile placed on the plate render at the object's footprint
/// (green = active, blue = selected to skip, red = skipped). Tappable: taps
/// toggle the object in/out of the pending selection, the same action as
/// tapping its row in the list below.
class _ObjectMarker extends StatelessWidget {
  const _ObjectMarker({
    required this.object,
    required this.fraction,
    required this.sizeFraction,
    required this.tokens,
    required this.selected,
    required this.canSelect,
    required this.onTap,
  });

  final PrintableObject object;
  final Offset fraction;
  final Size sizeFraction;
  final DashTokens tokens;
  final bool selected;
  final bool canSelect;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skipped = object.skipped;
    final bg = skipped
        ? tokens.danger
        : (selected ? tokens.accentBlue : tokens.accentGreen);
    const fg = Colors.black;
    return Align(
      alignment: FractionalOffset(fraction.dx, fraction.dy),
      child: FractionallySizedBox(
        widthFactor: sizeFraction.width,
        heightFactor: sizeFraction.height,
        child: GestureDetector(
          onTap: (skipped || !canSelect) ? null : onTap,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? Colors.white : Colors.black38,
                width: selected ? 2 : 1,
              ),
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 1)),
              ],
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Text(
                  '${object.id}',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: skipped ? Colors.white : fg,
                    decoration: skipped ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ).tagged('skip_objects.marker'),
    );
  }
}

/// "N active" badge in the plate corner.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        l10n.skipObjectsActiveCount(count),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// One object row: prominent ID badge, name, and a selection indicator (or
/// "Skipped"). Tapping the row toggles the same selection as tapping the
/// object's shape on the plate preview above.
class _ObjectTile extends StatelessWidget {
  const _ObjectTile({
    required this.object,
    required this.selected,
    required this.canSelect,
    required this.blockedReason,
    required this.onToggle,
  });

  final PrintableObject object;
  final bool selected;
  final bool canSelect;
  final String? blockedReason;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final skipped = object.skipped;
    final accent = skipped
        ? t.danger
        : (selected ? t.accentBlue : t.accentGreenInk);
    final accentBg = (skipped ? t.danger : (selected ? t.accentBlue : t.accentGreen))
        .withValues(alpha: 0.15);

    return Tooltip(
      message: blockedReason ?? '',
      triggerMode: blockedReason == null
          ? TooltipTriggerMode.manual
          : TooltipTriggerMode.tap,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: (canSelect && !skipped) ? onToggle : null,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: skipped
                ? t.danger.withValues(alpha: 0.06)
                : (selected ? t.accentBlue.withValues(alpha: 0.08) : t.subCard),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: skipped
                  ? t.danger.withValues(alpha: 0.3)
                  : (selected
                      ? t.accentBlue.withValues(alpha: 0.5)
                      : t.subCardBorder),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accentBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accent.withValues(alpha: 0.4)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${object.id}',
                      style: TextStyle(
                        fontFamily: DashTokens.fontMono,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        color: accent,
                      ),
                    ),
                    Text(
                      'ID',
                      style: TextStyle(
                        fontSize: 8,
                        letterSpacing: 1,
                        color: accent.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  object.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: skipped ? t.danger : t.textPrimary,
                    decoration: skipped ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (skipped)
                Text(
                  l10n.skipObjectsSkippedTag,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: t.danger,
                  ),
                )
              else
                Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: selected ? t.accentBlue : t.textTertiary,
                ),
            ],
          ),
        ),
      ).tagged('skip_objects.object_tile'),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onReload});

  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.view_in_ar_outlined, size: 48, color: t.textTertiary),
            const SizedBox(height: 16),
            Text(
              l10n.skipObjectsEmpty,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: t.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.skipObjectsEmptyHint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: t.textSecondary),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onReload,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l10n.skipObjectsReload),
            ).tagged('skip_objects.reload'),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: t.textTertiary),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: t.textSecondary),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l10n.retry),
            ).tagged('skip_objects.retry'),
          ],
        ),
      ),
    );
  }
}
