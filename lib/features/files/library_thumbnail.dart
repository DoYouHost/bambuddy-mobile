import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart';
import '../common/media_image.dart';
import '../common/thumbnail_box.dart';

/// Library file thumbnail. Authenticated with the media credential — the
/// Bearer header does NOT work for this resource, same as archive thumbnail
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
    final radius = thumbnailRadius(size);

    Widget placeholder([IconData icon = Icons.view_in_ar_outlined]) =>
        ThumbnailPlaceholder(size: size, icon: icon);

    if (!hasThumbnail) return placeholder();

    return MediaImage(
      path: Endpoints.libraryFileThumbnail(fileId),
      width: size,
      height: size,
      borderRadius: radius,
      zoom: zoom,
      placeholder: (status) => placeholder(
        status == MediaImageStatus.unauthenticated
            ? Icons.broken_image_outlined
            : Icons.view_in_ar_outlined,
      ),
    );
  }
}
