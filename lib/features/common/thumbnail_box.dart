import 'package:flutter/material.dart';

/// Corner radius of a thumbnail tile, from its size.
///
/// The step at 64 is the whole rule: a 52 px row thumbnail and a 96 px grid
/// cover are the same design at two sizes, and a single radius makes the small
/// one look blunt and the large one look sharp.
BorderRadius thumbnailRadius(double size) =>
    BorderRadius.circular(size < 64 ? 8 : 10);

/// What a thumbnail tile shows when there is no image: nothing is loaded yet,
/// the server has none, or the fetch failed.
///
/// A placeholder rather than an error widget, everywhere. These tiles sit in
/// list rows and on cards, and a broken-image fault drawn at row height reads
/// as "the app is broken" for what is usually "this file has no render".
class ThumbnailPlaceholder extends StatelessWidget {
  const ThumbnailPlaceholder({
    super.key,
    required this.size,
    required this.icon,
  });

  final double size;

  /// What this kind of thing looks like — a picture, a model, a broken fetch.
  /// The one thing the three call sites genuinely differ on.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: thumbnailRadius(size),
      ),
      child: Icon(icon, color: scheme.onSurfaceVariant, size: size * 0.4),
    );
  }
}
