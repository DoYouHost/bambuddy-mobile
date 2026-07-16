import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/theme/dash_theme.dart';

/// A search bar that lives inside a [CustomScrollView] and rolls away as the
/// list scrolls down, sliding back in only once the list returns to the top.
///
/// It is a *pinned* [SliverPersistentHeader] that shrinks from [height] to zero
/// — so, unlike a `floating` app bar, it reserves layout space and the list
/// content is always positioned below it. That is what stops it from painting
/// over the first rows when it re-expands on an upward scroll. Motion is fully
/// scroll-linked (derived from the sliver's own `shrinkOffset`), so it tracks
/// the finger exactly with no listeners or setState.
///
/// While it overlaps content mid-collapse it frosts (blur + light tint that
/// sample whatever is behind it) instead of a solid fill that would clash with
/// the screen's background gradient; at the very top it stays fully clear.
class DashSliverSearchBar extends StatelessWidget {
  const DashSliverSearchBar({
    super.key,
    required this.child,
    this.height = 64,
    this.padding = const EdgeInsets.fromLTRB(12, 8, 12, 8),
  });

  /// The search field (optionally in a Row with a trailing filter/action).
  final Widget child;

  /// Toolbar height reserved for the bar — must comfortably fit [child].
  final double height;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _SearchBarDelegate(
        child: child,
        height: height,
        padding: padding,
      ),
    );
  }
}

class _SearchBarDelegate extends SliverPersistentHeaderDelegate {
  _SearchBarDelegate({
    required this.child,
    required this.height,
    required this.padding,
  });

  final Widget child;
  final double height;
  final EdgeInsets padding;

  @override
  double get maxExtent => height;

  // Collapses all the way to zero so nothing lingers pinned at the top.
  @override
  double get minExtent => 0;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final t = DashTokens.of(context);
    final extent = (height - shrinkOffset).clamp(0.0, height);
    final shrink = height <= 0 ? 1.0 : (shrinkOffset / height).clamp(0.0, 1.0);
    // Frost only once the list scrolls under the bar; at the very top it stays
    // clear so the background gradient shows through untouched.
    final bgAlpha = (shrink * 2).clamp(0.0, 1.0);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18 * bgAlpha, sigmaY: 18 * bgAlpha),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.overlaySurface.withValues(alpha: 0.5 * bgAlpha),
          ),
          child: SizedBox(
            height: extent,
            width: double.infinity,
            // Render the field at full size and clip as the bar shrinks, so the
            // field itself never reflows — only how much of it shows changes.
            child: ClipRect(
              child: OverflowBox(
                minHeight: height,
                maxHeight: height,
                alignment: Alignment.topCenter,
                child: Opacity(
                  opacity: (1 - shrink * 1.4).clamp(0.0, 1.0),
                  child: Padding(padding: padding, child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SearchBarDelegate old) =>
      old.child != child || old.height != height || old.padding != padding;
}
