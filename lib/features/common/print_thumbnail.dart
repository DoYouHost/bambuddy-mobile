import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart';
import '../../providers.dart';
import 'camera_token_image_recovery.dart';

/// Print thumbnail from archive (queue + archive). Auth via `?token=`
/// (camera token) — auth header does NOT work for this resource, live-verified.
/// Pattern identical to cover in printer_card. Placeholder instead of error —
/// never crashes card.
///
/// Rendered thumbnails have lots of empty margin around model, so we scale
/// content ([zoom], default 140%) inside crop to "frame" the print and fill tile.
class PrintThumbnail extends ConsumerStatefulWidget {
  const PrintThumbnail({
    super.key,
    required this.archiveId,
    this.size = 52,
    this.zoom = 1.4,
  }) : printLogEntryId = null;

  /// The same tile for a print-log row, served by the entry's own route.
  ///
  /// Not the archive's: a run outlives the archive it points at, and the log
  /// route is the only one that can still answer for an orphan. Pass null once
  /// `thumbnail_path` is empty — the server has nothing to send, and asking
  /// anyway costs a 404 per row.
  const PrintThumbnail.printLogEntry({
    super.key,
    required this.printLogEntryId,
    this.size = 52,
    this.zoom = 1.4,
  }) : archiveId = null;

  /// Archive id; when null → placeholder (e.g. queue item without archive).
  final int? archiveId;

  /// Print-log entry id; set instead of [archiveId] by
  /// [PrintThumbnail.printLogEntry].
  final int? printLogEntryId;

  final double size;

  /// Scale factor of thumbnail content (crop empty margin).
  final double zoom;

  @override
  ConsumerState<PrintThumbnail> createState() => _PrintThumbnailState();
}

class _PrintThumbnailState extends ConsumerState<PrintThumbnail>
    with CameraTokenImageRecovery {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = widget.size;
    final zoom = widget.zoom;
    final radius = BorderRadius.circular(size < 64 ? 8 : 10);

    Widget placeholder([IconData icon = Icons.image_outlined]) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: radius,
      ),
      child: Icon(icon, color: scheme.onSurfaceVariant, size: size * 0.4),
    );

    final entryId = widget.printLogEntryId;
    final path = entryId != null
        ? Endpoints.printLogThumbnail(entryId)
        : (widget.archiveId == null
            ? null
            : Endpoints.archiveThumbnail(widget.archiveId!));
    final profile = ref.watch(serverProfileProvider);
    final baseUrl = profile?.baseUrl;
    // Demo mode has no thumbnail renders — placeholder beats a broken image.
    if (path == null || baseUrl == null || profile?.isDemo == true) {
      return placeholder();
    }

    return ref
        .watch(cameraTokenProvider)
        .when(
          loading: placeholder,
          error: (_, _) => placeholder(Icons.broken_image_outlined),
          data: (token) => ClipRRect(
            borderRadius: radius,
            child: Transform.scale(
              scale: zoom,
              child: Image.network(
                '$baseUrl$path?token=$token',
                width: size,
                height: size,
                // Server serves full-res renders; without this the decoder
                // allocates a full bitmap for a tile scrolled at ~50dp — memory
                // and jank multiply across a paginated list of these.
                // `* zoom` matches the crop scale above so the cached
                // resolution still covers the cropped-in content.
                cacheWidth: (size *
                        zoom *
                        MediaQuery.devicePixelRatioOf(context))
                    .round(),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, error, _) {
                  recoverCameraTokenOnError(error, token);
                  return placeholder(Icons.broken_image_outlined);
                },
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : placeholder(),
              ),
            ),
          ),
        );
  }
}
