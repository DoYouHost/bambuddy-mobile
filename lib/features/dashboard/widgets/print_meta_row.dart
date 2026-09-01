import 'package:flutter/material.dart';

import '../../../core/theme/dash_text.dart';
import '../../../core/theme/dash_theme.dart';

/// Print-panel metadata item (remaining/ETA/layers): mono text with a leading icon.
class PrintMetaItem extends StatelessWidget {
  const PrintMetaItem({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  static const _iconSize = 14.0;
  static const _iconGap = 4.0;

  /// The style the label paints with — the item's own, merged onto the ambient
  /// [DefaultTextStyle] exactly the way [Text] merges it. Painting and measuring
  /// both go through here: measuring `monoLabel` alone left out the theme's
  /// letter spacing (0.25 on `bodyMedium`, which every label inherits), read the
  /// row some 8 px narrow, kept it on one line and painted the overflow stripes
  /// on a real card.
  static TextStyle resolveStyle(BuildContext context) {
    final t = DashTokens.of(context);
    return DefaultTextStyle.of(context)
        .style
        .merge(t.monoLabel.copyWith(color: t.textSecondary));
  }

  /// How wide this item wants to be, at the font size the device is set to.
  double measure(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: resolveStyle(context)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return _iconWidth(context) + _iconGap + painter.width;
  }

  /// An icon follows the system font size only where the theme says so, and the
  /// row's arithmetic has to say the same thing the [Icon] will.
  static double _iconWidth(BuildContext context) =>
      (IconTheme.of(context).applyTextScaling ?? false)
          ? MediaQuery.textScalerOf(context).scale(_iconSize)
          : _iconSize;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: _iconSize, color: t.textSecondary),
        const SizedBox(width: _iconGap),
        // Flexible for the case [PrintMetaRow] cannot design its way out of: a
        // system font size at which no item fits any column. Cut short beats
        // overflow stripes.
        Flexible(
          child: Text(
            text,
            style: resolveStyle(context),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// The metadata line under the progress bar, placed by measurement.
///
/// A `Wrap` used to break it wherever it ran out of room, which is a different
/// place depending on the clock: a 12-hour ETA is some 20 px wider than
/// `ETA 23:07` and pushed the layer count onto a second line of its own, lined
/// up with nothing. The items are the same; only the fallback is deliberate now
/// — one row while one row fits, otherwise a two-column grid whose second line
/// starts under the first item instead of somewhere after it.
class PrintMetaRow extends StatelessWidget {
  const PrintMetaRow({super.key, required this.items});

  final List<PrintMetaItem> items;

  /// Between two items on a line, and between the lines.
  static const _gap = 14.0;
  static const _runGap = 8.0;

  /// Room kept in hand, so that a difference of a pixel between what a
  /// [TextPainter] answers and what the paragraph lays out cannot be what
  /// decides the layout. Breaking a touch early costs nothing here; the other
  /// direction is the striped bar.
  static const _slack = 6.0;

  @override
  Widget build(BuildContext context) {
    final widths = [for (final item in items) item.measure(context)];

    return LayoutBuilder(
      builder: (context, constraints) {
        final oneLine =
            widths.reduce((a, b) => a + b) + _gap * (items.length - 1);
        if (oneLine + _slack <= constraints.maxWidth) {
          return _line(items, widths, grid: false);
        }

        // Two columns while the widest item fits in one. At a large system font
        // size it does not, and a single column reads better than two columns of
        // text cut in half.
        final columnWidth = (constraints.maxWidth - _gap) / 2;
        final grid = widths.every((w) => w <= columnWidth);
        final perLine = grid ? 2 : 1;
        final cell = grid ? columnWidth : constraints.maxWidth;
        final lines = <Widget>[
          for (var i = 0; i < items.length; i += perLine)
            _line(items.skip(i).take(perLine).toList(),
                List.filled(perLine, cell),
                grid: true),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < lines.length; i++) ...[
              if (i > 0) const SizedBox(height: _runGap),
              lines[i],
            ],
          ],
        );
      },
    );
  }

  /// One line of items. In a [grid] each [share] is the column width, so the
  /// columns line up; on the single line they are the measured widths, handed to
  /// the flex as ratios.
  ///
  /// Ratios rather than natural sizes because a `Row` gives an unflexed child
  /// unbounded width: an item then measures itself against infinity and paints
  /// the overflow stripes. Flexed in proportion, an item with room to spare is
  /// offered more than it asked for and keeps its own width — nothing moves —
  /// while a measurement that turns out a few pixels short shortens the longest
  /// label instead of the card.
  static Widget _line(
    List<PrintMetaItem> line,
    List<double> share, {
    required bool grid,
  }) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < line.length; i++) ...[
            if (i > 0) const SizedBox(width: _gap),
            if (grid)
              SizedBox(width: share[i], child: line[i])
            else
              Flexible(
                flex: share[i].round().clamp(1, 1 << 20),
                child: line[i],
              ),
          ],
        ],
      );
}
