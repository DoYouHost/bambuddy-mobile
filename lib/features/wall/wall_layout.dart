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
int wallColumns(int count, Size area, {double gap = 10}) {
  if (count <= 1 || area.isEmpty) return 1;
  var best = 1;
  var bestWidth = 0.0;
  for (var cols = 1; cols <= count; cols++) {
    final rows = (count / cols).ceil();
    final cellW = (area.width - gap * (cols - 1)) / cols;
    final cellH = (area.height - gap * (rows - 1)) / rows;
    final frameW = math.min(cellW, cellH * wallTileAspect);
    if (frameW > bestWidth + 0.5) {
      best = cols;
      bestWidth = frameW;
    }
  }
  return best;
}
