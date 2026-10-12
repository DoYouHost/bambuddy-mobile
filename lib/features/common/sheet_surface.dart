import 'package:flutter/material.dart';

import '../../core/theme/dash_theme.dart';

/// A draggable sheet standing on a [SheetSurface] — the pair every content sheet
/// opened with `dashSurfaceSheet` is built from. One line of it is easy to drop:
/// without `expand: false` the sheet ignores [initialSize] and opens at full height.
/// State a size only where the sheet wants a different one.
///
/// Only for a sheet shown with `dashSurfaceSheet`. The three shown with `dashSheet`
/// (the AMS slot assignment, the maintenance type form, the slicer's preset picker)
/// stand on Material's own surface and keep a bare [DraggableScrollableSheet]: this
/// one would draw a second surface and a second drag handle inside the first.
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
    final navInset = (mq.viewPadding.bottom - mq.viewInsets.bottom).clamp(
      0.0,
      double.infinity,
    );
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
          const SizedBox(height: DashSpace.md),
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
          const SizedBox(height: DashSpace.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: navInset),
              // The decoration above paints over any Material further up, so a
              // ListTile's ink would be drawn underneath it and never seen.
              child: Material(type: MaterialType.transparency, child: child),
            ),
          ),
        ],
      ),
    );
  }
}

/// The surface a sheet that is **as tall as its content** stands on: rounded top, a
/// hairline, the drag handle, and nothing below it but [child].
///
/// The other half of [SheetSurface], and deliberately not the same widget: that one
/// is for a `DraggableScrollableSheet` and owns its background colour, a lifted
/// shadow and the navigation-bar inset. This one sits on `t.overlaySurface`, takes
/// its height from its content and lets a plain `SafeArea` handle the bottom. [child]
/// goes straight into the surface's `Column`, so it can be a `Padding` or a
/// `Flexible` around a scroll view for content that may outgrow the screen.
class FittedSheetSurface extends StatelessWidget {
  const FittedSheetSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return SafeArea(
      top: false,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: t.overlaySurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: t.subCardBorder)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: DashSpace.md),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: t.textTertiary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}
