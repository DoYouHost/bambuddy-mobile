import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart';
import '../../providers.dart';

/// Project cover image. Authenticated via `?token=` (camera token) — the auth
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
    final scheme = Theme.of(context).colorScheme;
    final radius = borderRadius ?? BorderRadius.circular(12);

    Widget placeholder([IconData icon = Icons.folder_special_outlined]) =>
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: radius,
          ),
          child: Icon(icon,
              color: scheme.onSurfaceVariant,
              size: (width < height ? width : height) * 0.4),
        );

    final baseUrl = ref.watch(serverProfileProvider)?.baseUrl;
    if (!hasCover || baseUrl == null) return placeholder();

    return ref.watch(cameraTokenProvider).when(
          loading: placeholder,
          error: (_, _) => placeholder(Icons.broken_image_outlined),
          data: (token) {
            final bust = cacheBust == null ? '' : '&v=${Uri.encodeQueryComponent(cacheBust!)}';
            return ClipRRect(
              borderRadius: radius,
              child: Image.network(
                '$baseUrl${Endpoints.projectCoverImage(projectId)}?token=$token$bust',
                width: width,
                height: height,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => placeholder(),
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : placeholder(),
              ),
            );
          },
        );
  }
}
