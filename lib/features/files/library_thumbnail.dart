import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart';
import '../../providers.dart';

/// Library file thumbnail. Authenticated via `?token=` (camera token) —
/// auth header does NOT work for this resource, same as archive thumbnail
/// (see `PrintThumbnail`). Placeholder instead of error.
class LibraryThumbnail extends ConsumerWidget {
  const LibraryThumbnail({
    super.key,
    required this.fileId,
    this.hasThumbnail = true,
    this.size = 56,
    this.zoom = 1.3,
  });

  final int fileId;

  /// Whether server has thumbnail at all (from `thumbnail_path`). If not —
  /// show placeholder immediately, no wasted image fetch.
  final bool hasThumbnail;
  final double size;
  final double zoom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(size < 64 ? 8 : 10);

    Widget placeholder([IconData icon = Icons.view_in_ar_outlined]) =>
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: radius,
          ),
          child: Icon(icon, color: scheme.onSurfaceVariant, size: size * 0.4),
        );

    final baseUrl = ref.watch(serverProfileProvider)?.baseUrl;
    if (!hasThumbnail || baseUrl == null) return placeholder();

    return ref.watch(cameraTokenProvider).when(
          loading: placeholder,
          error: (_, _) => placeholder(Icons.broken_image_outlined),
          data: (token) => ClipRRect(
            borderRadius: radius,
            child: Transform.scale(
              scale: zoom,
              child: Image.network(
                '$baseUrl${Endpoints.libraryFileThumbnail(fileId)}?token=$token',
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => placeholder(),
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : placeholder(),
              ),
            ),
          ),
        );
  }
}
