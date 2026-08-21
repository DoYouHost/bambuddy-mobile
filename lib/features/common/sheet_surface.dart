import 'package:flutter/material.dart';

import '../../core/theme/dash_theme.dart';

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
