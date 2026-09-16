import 'package:flutter/material.dart';

import '../../core/theme/dash_theme.dart';

/// Rounded tinted square holding one glyph: the leading mark of a settings
/// row, a drawer entry, a folder tile, a printer card header.
///
/// The paint is one decision — the accent at α 0.14 under an `accentGreenInk`
/// glyph — and that is what this widget owns. The geometry is not: the tile
/// runs 36 / 40 / 44 px depending on how dense the row around it is, and a
/// call site whose layout reserves room for the square passes the same
/// constant it reserves (`_HeaderLine.glyphSquare` on the printer card).
class DashIconTile extends StatelessWidget {
  const DashIconTile({
    super.key,
    required this.icon,
    required this.size,
    required this.radius,
    this.iconSize,
    this.ink,
    this.fill,
  });

  final IconData icon;
  final double size;
  final double radius;

  /// Left at Material's default (24) where the call site never set one.
  final double? iconSize;

  /// Glyph colour, when the tile marks something the accent would not.
  final Color? ink;

  /// Fill behind the glyph. Pass one only together with [ink]: the pair is what
  /// reads as a single state (offline, a fault, a plate waiting).
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill ?? t.accentGreen.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(icon, size: iconSize, color: ink ?? t.accentGreenInk),
    );
  }
}
