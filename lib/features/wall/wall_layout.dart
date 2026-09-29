import 'dart:math' as math;
import 'dart:ui';

/// Tiles are drawn for a camera picture, so the grid is sized for 16:9 cells.
const wallTileAspect = 16 / 9;

/// How many columns give [count] tiles in [area] the largest 16:9 picture.
///
/// Every column count is tried: a cell is the area split into columns and the
/// rows that follow from them, and what counts is the biggest 16:9 frame that
/// fits in that cell. Ties go to fewer columns, which leaves wider tiles for
/// the text under the picture.
///
/// When even the best split leaves cells shorter than [minTileHeight], the grid
/// is going to scroll anyway, so the columns are whatever fits 16:9 tiles of
/// that height across the width — not the split that squeezed every tile onto
/// one screen and left them narrower than they are tall.
int wallColumns(
  int count,
  Size area, {
  double gap = 10,
  double minTileHeight = 0,
}) {
  if (count <= 1 || area.isEmpty) return 1;
  var best = 1;
  var bestWidth = 0.0;
  var bestHeight = 0.0;
  for (var cols = 1; cols <= count; cols++) {
    final rows = (count / cols).ceil();
    final cellW = (area.width - gap * (cols - 1)) / cols;
    final cellH = (area.height - gap * (rows - 1)) / rows;
    final frameW = math.min(cellW, cellH * wallTileAspect);
    if (frameW > bestWidth + 0.5) {
      best = cols;
      bestWidth = frameW;
      bestHeight = cellH;
    }
  }
  if (bestHeight >= minTileHeight) return best;
  final fits = ((area.width + gap) / (minTileHeight * wallTileAspect + gap))
      .floor();
  return math.max(1, math.min(fits, count));
}
