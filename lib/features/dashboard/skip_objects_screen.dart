import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/models/printable_object.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/camera_token_image_recovery.dart';
import 'controls_providers.dart' show ControlResult;
import 'skip_objects_providers.dart';
import 'ws_providers.dart';

/// Skip-objects screen: shows the current print's objects (with their printer
/// display IDs) over a top-down build-plate render, and lets the user skip a
/// failed one. Skipping is irreversible, so every skip is confirmed. Skips are
/// blocked until layer 2 (the printer can't skip the first layer) and when the
/// API key lacks `can_control_printer`.
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
  /// Object ids with a skip request in flight (button spinner + lock).
  final _inFlight = <int>{};

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
                      onInteractingChanged: (v) {
                        if (v != _plateInteracting) {
                          setState(() => _plateInteracting = v);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    for (final obj in data.objects)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ObjectTile(
                          object: obj,
                          busy: _inFlight.contains(obj.id),
                          canSkip: canSkipLayer && !_forbidden,
                          blockedReason: _forbidden
                              ? l10n.ctrlForbidden
                              : (!canSkipLayer
                                  ? l10n.skipObjectsWaitForLayer(layerNum)
                                  : null),
                          onSkip: () => _confirmSkip(obj),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Future<void> _confirmSkip(PrintableObject obj) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.skipObjectsConfirmTitle),
        content: Text(l10n.skipObjectsConfirmBody(obj.name)),
        actions: [
          logTag(
            'skip_object.cancel',
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
          ),
          logTag(
            'skip_object.confirm',
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.skipObjectsSkip),
            ),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) return;

    setState(() => _inFlight.add(obj.id));
    final result = await ref
        .read(skipObjectsProvider(widget.printerId).notifier)
        .skip(obj.id);
    if (!mounted) return;
    setState(() {
      _inFlight.remove(obj.id);
      if (result == ControlResult.forbidden) _forbidden = true;
    });

    final msg = switch (result) {
      ControlResult.ok => l10n.skipObjectsSkippedToast(obj.name),
      ControlResult.forbidden => l10n.ctrlForbidden,
      ControlResult.error => l10n.ctrlFailed,
    };
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
    required this.onInteractingChanged,
  });

  final int printerId;
  final String? coverUrl;
  final PrintableObjects data;
  final CameraTokenImageRecovery recovery;

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
              tokens: t,
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

/// Circular ID chip placed on the plate render (green = active, red = skipped).
class _ObjectMarker extends StatelessWidget {
  const _ObjectMarker({
    required this.object,
    required this.fraction,
    required this.tokens,
  });

  final PrintableObject object;
  final Offset fraction;
  final DashTokens tokens;

  @override
  Widget build(BuildContext context) {
    final skipped = object.skipped;
    final bg = skipped ? const Color(0xFFEF4444) : tokens.accentGreen;
    final fg = skipped ? Colors.white : Colors.black;
    return Align(
      alignment: FractionalOffset(fraction.dx, fraction.dy),
      child: Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 1)),
          ],
        ),
        child: Text(
          '${object.id}',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: fg,
            decoration: skipped ? TextDecoration.lineThrough : null,
          ),
        ),
      ),
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

/// One object row: prominent ID badge, name, and a Skip button (or "Skipped").
class _ObjectTile extends StatelessWidget {
  const _ObjectTile({
    required this.object,
    required this.busy,
    required this.canSkip,
    required this.blockedReason,
    required this.onSkip,
  });

  final PrintableObject object;
  final bool busy;
  final bool canSkip;
  final String? blockedReason;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final skipped = object.skipped;
    const red = Color(0xFFEF4444);
    final badgeColor = skipped ? red : t.accentGreenInk;
    final badgeBg = (skipped ? red : t.accentGreen).withValues(alpha: 0.15);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: skipped ? red.withValues(alpha: 0.06) : t.subCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: skipped ? red.withValues(alpha: 0.3) : t.subCardBorder,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
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
                    color: badgeColor,
                  ),
                ),
                Text(
                  'ID',
                  style: TextStyle(
                    fontSize: 8,
                    letterSpacing: 1,
                    color: badgeColor.withValues(alpha: 0.7),
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
                color: skipped ? red : t.textPrimary,
                decoration: skipped ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (skipped)
            Text(
              l10n.skipObjectsSkippedTag,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: red,
              ),
            )
          else
            Tooltip(
              message: blockedReason ?? '',
              triggerMode: blockedReason == null
                  ? TooltipTriggerMode.manual
                  : TooltipTriggerMode.tap,
              child: FilledButton(
                onPressed: (canSkip && !busy) ? onSkip : null,
                style: FilledButton.styleFrom(
                  backgroundColor: red.withValues(alpha: 0.15),
                  foregroundColor: red,
                  disabledBackgroundColor: t.subCard,
                  disabledForegroundColor: t.textTertiary,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                child: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.skipObjectsSkip),
              ).tagged('skip_objects.skip'),
            ),
        ],
      ),
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
