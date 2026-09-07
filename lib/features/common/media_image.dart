import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import 'media_auth_image_recovery.dart';

/// Why a [MediaImage] is showing its placeholder.
///
/// Three, not a flag: the tiles already drew a credential that would not mint
/// differently from a render the server lost.
enum MediaImageStatus { loading, unauthenticated, unavailable }

/// An image on one of the server's media routes — a thumbnail, a cover, a plate
/// render, a photo.
///
/// The element builds its own request, so the Dio client never sees these: each
/// has to carry the media credential itself, in the URL or in a header when the
/// session is an API key ([MediaAuth]). [timelapsePlayer] is the same idea for
/// the one media route that is a video.
class MediaImage extends ConsumerStatefulWidget {
  const MediaImage({
    super.key,
    required this.path,
    required this.placeholder,
    this.width,
    this.height,
    this.borderRadius,
    this.zoom = 1,
    this.fit = BoxFit.cover,
    this.imageKey,
  });

  /// Server-relative, query and all (`/api/v1/…/cover?view=top`).
  final String path;

  /// Drawn whenever the picture is not on screen.
  final Widget Function(MediaImageStatus status) placeholder;

  final double? width;
  final double? height;

  /// Null leaves the picture unclipped.
  final BorderRadius? borderRadius;

  /// Crops the empty margin a slicer leaves around a render.
  final double zoom;

  final BoxFit fit;

  /// Key on the `Image`, for tests looking past the placeholder.
  final Key? imageKey;

  @override
  ConsumerState<MediaImage> createState() => _MediaImageState();
}

class _MediaImageState extends ConsumerState<MediaImage>
    with MediaAuthImageRecovery {
  /// The width alone: capping the height too makes `ResizeImage` decode to
  /// exactly the box, stretching a source of another shape instead of letting
  /// [BoxFit.cover] crop it.
  int? get _decodeWidth {
    final width = widget.width;
    if (width == null || !width.isFinite) return null;
    return (width * widget.zoom * MediaQuery.devicePixelRatioOf(context))
        .round();
  }

  @override
  Widget build(BuildContext context) {
    // No profile is terminal, not transient: there is no server to ask.
    final baseUrl = ref.watch(serverProfileProvider)?.baseUrl;
    if (baseUrl == null) {
      return widget.placeholder(MediaImageStatus.unavailable);
    }

    return ref
        .watch(mediaAuthProvider)
        .when(
          loading: () => widget.placeholder(MediaImageStatus.loading),
          error: (_, _) => widget.placeholder(MediaImageStatus.unauthenticated),
          data: (auth) => _clipped(
            Image.network(
              auth.sign('$baseUrl${widget.path}'),
              headers: auth.headers,
              key: widget.imageKey,
              width: widget.width,
              height: widget.height,
              // Without this the decoder allocates the server's full-res
              // bitmap for a 50 dp tile, once per row of a long list.
              cacheWidth: _decodeWidth,
              fit: widget.fit,
              gaplessPlayback: true,
              errorBuilder: (_, error, _) {
                recoverMediaAuthOnError(error, auth);
                return widget.placeholder(MediaImageStatus.unavailable);
              },
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : widget.placeholder(MediaImageStatus.loading),
            ),
          ),
        );
  }

  Widget _clipped(Widget image) {
    final scaled = widget.zoom == 1
        ? image
        : Transform.scale(scale: widget.zoom, child: image);
    final radius = widget.borderRadius;
    return radius == null
        ? scaled
        : ClipRRect(borderRadius: radius, child: scaled);
  }
}
