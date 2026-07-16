import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/theme/dash_theme.dart';

/// A search bar that lives inside a [CustomScrollView] and rolls away as the
/// list scrolls down, floating back in on any upward scroll (`floating` +
/// `snap`). The motion is fully scroll-linked — no listeners, no setState —
/// so it never stutters or jumps like a direction-driven header does.
///
/// While floating it sits over list content, so instead of a solid fill (which
/// would clash with the screen's background gradient) it frosts: a blur plus a
/// light tint that sample whatever is behind it.
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
    final t = DashTokens.of(context);
    return SliverAppBar(
      primary: false,
      floating: true,
      snap: true,
      pinned: false,
      automaticallyImplyLeading: false,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: height,
      titleSpacing: 0,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: t.overlaySurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
      title: Padding(padding: padding, child: child),
    );
  }
}
