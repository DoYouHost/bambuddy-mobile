import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart';
import '../../providers.dart';
import 'media_image.dart';

/// Print thumbnail from archive (queue + archive). Auth via the media
/// credential — the Bearer header does NOT work for this resource,
/// live-verified. Pattern identical to cover in printer_card. Placeholder
/// instead of error — never crashes card.
///
/// Rendered thumbnails have lots of empty margin around model, so we scale
/// content ([zoom], default 140%) inside crop to "frame" the print and fill tile.
class PrintThumbnail extends ConsumerWidget {
  const PrintThumbnail({
    super.key,
    required this.archiveId,
    this.size = 52,
    this.zoom = 1.4,
  }) : printLogEntryId = null,
       path = null;

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
  }) : archiveId = null,
       path = null;

  /// A render the caller already holds the path of — one plate of a multi-plate
  /// 3MF, whose row carries its own `thumbnail_url` because the archive and
  /// library routes spell it differently.
  ///
  /// Same crop and the same token handling as the print tile: a plate render is
  /// the same kind of image, margins included.
  const PrintThumbnail.path({
    super.key,
    required this.path,
    this.size = 52,
    this.zoom = 1.4,
  }) : archiveId = null,
       printLogEntryId = null;

  /// Archive id; when null → placeholder (e.g. queue item without archive).
  final int? archiveId;

  /// Print-log entry id; set instead of [archiveId] by
  /// [PrintThumbnail.printLogEntry].
  final int? printLogEntryId;

  /// Ready-made server path, set instead of either id by
  /// [PrintThumbnail.path].
  final String? path;

  final double size;

  /// Scale factor of thumbnail content (crop empty margin).
  final double zoom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
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

    final entryId = printLogEntryId;
    final route =
        path ??
        (entryId != null
            ? Endpoints.printLogThumbnail(entryId)
            : (archiveId == null
                  ? null
                  : Endpoints.archiveThumbnail(archiveId!)));
    // Neither demo mode nor an unconfigured app has a render to serve, and
    // neither is a broken thumbnail — say nothing rather than draw a fault.
    final profile = ref.watch(serverProfileProvider);
    if (route == null || profile == null || profile.isDemo) {
      return placeholder();
    }

    return MediaImage(
      path: route,
      width: size,
      height: size,
      borderRadius: radius,
      zoom: zoom,
      placeholder: (status) => placeholder(
        status == MediaImageStatus.loading
            ? Icons.image_outlined
            : Icons.broken_image_outlined,
      ),
    );
  }
}
