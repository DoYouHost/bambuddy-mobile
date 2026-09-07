import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart';
import '../../providers.dart';

/// MakerWorld cover thumbnail. Rendered via public server proxy (`/makerworld/thumbnail?url=`) —
/// no token/auth (unlike library/archive thumbnails). Placeholder instead of error.
class MakerWorldThumbnail extends ConsumerWidget {
  const MakerWorldThumbnail({
    super.key,
    required this.coverUrl,
    this.size = 56,
  });

  /// Cover URL from MakerWorld (design/instance). `null` → show placeholder immediately.
  final String? coverUrl;
  final double size;

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
    final cover = coverUrl;
    if (baseUrl == null || cover == null || cover.isEmpty) {
      return placeholder();
    }

    final src =
        '$baseUrl${Endpoints.makerworldThumbnail}'
        '?url=${Uri.encodeQueryComponent(cover)}';
    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        src,
        width: size,
        height: size,
        // MakerWorld covers arrive full-res — cap decode resolution for the
        // tile size (models can list dozens of plates).
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => placeholder(Icons.broken_image_outlined),
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : placeholder(),
      ),
    );
  }
}
