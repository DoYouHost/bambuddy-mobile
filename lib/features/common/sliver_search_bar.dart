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
  const DashSliverSearchBar({super.key, required this.child});

  /// A [DashSearchField], with its buttons as `trailing`.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _SearchBarDelegate(child: child),
    );
  }
}

/// The search row as every list screen shows it: the field between the
/// gutters, then a soft band closing the header off from the list. Without it
/// the first card sits right under the field and reads as a layout bug; a
/// hard hairline was either lost in the gradient or too loud.
class DashSearchBarBody extends StatelessWidget {
  const DashSearchBarBody({super.key, required this.child});

  static const _band = DashSpace.xs;

  /// The 48 dp field, its padding and the band.
  static const height = 48 + 2 * DashSpace.sm + _band;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ink = DashTokens.of(context).textTertiary.withValues(alpha: 0.3);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DashSpace.gutter,
            vertical: DashSpace.sm,
          ),
          child: child,
        ),
        SizedBox(
          height: _band,
          width: double.infinity,
          // The vertical gradient softens the band top and bottom; the mask
          // multiplies it by a horizontal ramp, so it also fades out towards
          // both screen edges.
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => const LinearGradient(
              colors: [
                Colors.transparent,
                Colors.white,
                Colors.white,
                Colors.transparent,
              ],
              stops: [0, 0.25, 0.75, 1],
            ).createShader(rect),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, ink, Colors.transparent],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchBarDelegate extends SliverPersistentHeaderDelegate {
  _SearchBarDelegate({required this.child});

  static const height = DashSearchBarBody.height;

  final Widget child;

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
                  child: DashSearchBarBody(child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SearchBarDelegate old) => old.child != child;
}
