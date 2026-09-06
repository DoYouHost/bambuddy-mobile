import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart';
import '../../core/theme/dash_theme.dart';
import '../../providers.dart';
import '../common/camera_token_image_recovery.dart';

/// Project cover image. Authenticated via `?token=` (camera token) — the auth
/// header does NOT work for this resource, same as [LibraryThumbnail] / archive
/// cover. Shows a placeholder instead of an error so cards never crash.
///
/// [cacheBust] (e.g. the project `updated_at`) is appended to the URL so the
/// image reloads after an upload/delete instead of serving the stale cache.
class ProjectCoverImage extends ConsumerStatefulWidget {
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
  ConsumerState<ProjectCoverImage> createState() => _ProjectCoverImageState();
}

class _ProjectCoverImageState extends ConsumerState<ProjectCoverImage>
    with CameraTokenImageRecovery {
  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final width = widget.width;
    final height = widget.height;
    final radius = widget.borderRadius ?? BorderRadius.circular(12);

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

    final baseUrl = ref.watch(serverProfileProvider)?.baseUrl;
    if (!widget.hasCover || baseUrl == null) return placeholder();

    return ref
        .watch(cameraTokenProvider)
        .when(
          loading: placeholder,
          error: (_, _) => placeholder(Icons.broken_image_outlined),
          data: (token) {
            final cacheBust = widget.cacheBust;
            final bust = cacheBust == null
                ? ''
                : '&v=${Uri.encodeQueryComponent(cacheBust)}';
            return ClipRRect(
              borderRadius: radius,
              child: Image.network(
                '$baseUrl${Endpoints.projectCoverImage(widget.projectId)}?token=$token$bust',
                width: width,
                height: height,
                // Server serves a full-res cover — cap decode resolution for
                // the tile (project lists/cards render many of these).
                cacheWidth: (width * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                cacheHeight: (height * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, error, _) {
                  recoverCameraTokenOnError(error, token);
                  return placeholder();
                },
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : placeholder(),
              ),
            );
          },
        );
  }
}
