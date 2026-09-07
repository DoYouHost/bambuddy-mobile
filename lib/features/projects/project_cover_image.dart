import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart';
import '../../core/theme/dash_theme.dart';
import '../common/media_image.dart';

/// Project cover image. Authenticated with the media credential — the Bearer
/// header does NOT work for this resource, same as [LibraryThumbnail] / archive
/// cover. Shows a placeholder instead of an error so cards never crash.
///
/// [cacheBust] (e.g. the project `updated_at`) is appended to the URL so the
/// image reloads after an upload/delete instead of serving the stale cache.
class ProjectCoverImage extends ConsumerWidget {
  const ProjectCoverImage({
    super.key,
    required this.projectId,
    this.hasCover = true,
    this.width = 56,
    this.height = 56,
    this.borderRadius,
    this.cacheBust,
  });

  final int projectId;
  final bool hasCover;
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final String? cacheBust;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final radius = borderRadius ?? BorderRadius.circular(12);

    Widget placeholder([IconData icon = Icons.folder_special_outlined]) =>
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: t.subCard,
            borderRadius: radius,
            border: Border.all(color: t.subCardBorder),
          ),
          child: Icon(
            icon,
            color: t.textTertiary,
            size: (width < height ? width : height) * 0.4,
          ),
        );

    if (!hasCover) return placeholder();

    final bust = cacheBust;
    return MediaImage(
      path:
          '${Endpoints.projectCoverImage(projectId)}'
          '${bust == null ? '' : '?v=${Uri.encodeQueryComponent(bust)}'}',
      width: width,
      height: height,
      borderRadius: radius,
      placeholder: (status) => placeholder(
        status == MediaImageStatus.unauthenticated
            ? Icons.broken_image_outlined
            : Icons.folder_special_outlined,
      ),
    );
  }
}
