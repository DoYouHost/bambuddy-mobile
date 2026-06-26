import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart';
import '../../providers.dart';

/// Print thumbnail from archive (queue + archive). Auth via `?token=`
/// (camera token) — auth header does NOT work for this resource, live-verified.
/// Pattern identical to cover in printer_card. Placeholder instead of error —
/// never crashes card.
///
/// Rendered thumbnails have lots of empty margin around model, so we scale
/// content ([zoom], default 140%) inside crop to "frame" the print and fill tile.
class PrintThumbnail extends ConsumerWidget {
  const PrintThumbnail({
    super.key,
    required this.archiveId,
    this.size = 52,
    this.zoom = 1.4,
  });

  /// Archive id; when null → placeholder (e.g. queue item without archive).
  final int? archiveId;
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

    final id = archiveId;
    final baseUrl = ref.watch(serverProfileProvider)?.baseUrl;
    if (id == null || baseUrl == null) return placeholder();

    return ref.watch(cameraTokenProvider).when(
          loading: placeholder,
          error: (_, _) => placeholder(Icons.broken_image_outlined),
          data: (token) => ClipRRect(
            borderRadius: radius,
            child: Transform.scale(
              scale: zoom,
              child: Image.network(
                '$baseUrl${Endpoints.archiveThumbnail(id)}?token=$token',
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) =>
                    placeholder(Icons.broken_image_outlined),
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : placeholder(),
              ),
            ),
          ),
        );
  }
}
