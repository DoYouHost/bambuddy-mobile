import 'package:flutter/material.dart';

import '../../core/theme/dash_theme.dart';

/// A draggable sheet standing on a [SheetSurface] — the pair every content
/// sheet opened with `dashSurfaceSheet` is built from.
///
/// It exists because the pair was written out twelve times, always identically
/// apart from the three sizes, and one of those lines is load-bearing in a way
/// that is easy to drop: without `expand: false` the sheet ignores
/// [initialSize] and opens at full height.
///
/// The defaults are the sizes most of those twelve settled on. State a size
/// only where the sheet wants a different one — a filter list that should open
/// around half the screen, a form that should open nearly full.
///
/// Only for a sheet shown with `dashSurfaceSheet`. The three shown with
/// `dashSheet` — the AMS slot assignment, the maintenance type form and the
/// slicer's preset picker — stand on Material's own surface and keep a bare
/// [DraggableScrollableSheet] on purpose: giving them this one would draw a
/// second surface and a second drag handle inside the first.
class DraggableSheetSurface extends StatelessWidget {
  const DraggableSheetSurface({
    super.key,
    this.initialSize = 0.7,
    this.maxSize = 0.95,
    this.minSize = 0.4,
    required this.builder,
  });

  final double initialSize;
  final double maxSize;
  final double minSize;

  /// Builds the content on the surface. The scroll view it returns **must**
  /// take the [ScrollController] it is handed: one that ignores it drags the
  /// whole sheet instead of scrolling its own content.
  final Widget Function(BuildContext context, ScrollController controller)
      builder;

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: initialSize,
        maxChildSize: maxSize,
        minChildSize: minSize,
        builder: (context, controller) =>
            SheetSurface(child: builder(context, controller)),
      );
}

/// Rounded surface a draggable sheet sits on: own background, top hairline,
/// lifted shadow and the drag handle above the content.
class SheetSurface extends StatelessWidget {
  const SheetSurface({super.key, required this.child});

  /// The scroll view (typically a `ListView` bound to the drag controller).
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final mq = MediaQuery.of(context);
    // The sheet is drawn edge to edge, so the surface has to end the content
    // above the navigation bar itself. An open keyboard already covers that
    // strip, hence the subtraction rather than the larger of the two.
    final navInset =
        (mq.viewPadding.bottom - mq.viewInsets.bottom).clamp(0.0, double.infinity);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: t.isDark ? const Color(0xFF0E1310) : const Color(0xFFF6F8F4),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(
            color: t.isDark ? const Color(0x24FFFFFF) : const Color(0x14000000),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: t.isDark ? 0.5 : 0.22),
            blurRadius: 40,
            offset: const Offset(0, -12),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: t.isDark
                  ? const Color(0x40FFFFFF)
                  : const Color(0x33000000),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: navInset),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
