/// Where the compact AMS tiles of one unit go: which tiles share a row, and how
/// wide a slot is. Pure arithmetic, so every width and text size is a test case.
///
/// A block is one AMS unit's tiles, followed by the external spools when this is
/// the printer's last unit. Tiles are indexed AMS first, then external.
///
/// - A visible tile is never narrower than [compactTileMinWidth] times the text
///   scale, so the tap target passes the accessibility guideline without
///   counting the gap beside it.
/// - A row of n tiles has n - 1 gaps, not n: the last tile of a row has nothing
///   beside it. The layout counts one extra gap in the width, and the widget
///   draws the last tile of a row one gap narrower, so the row ends flush with
///   its container. Counting n gaps cost a 411.43 dp phone (1080 px at 420 dpi)
///   its sixth tile by 0.57 dp.
/// - When every tile of the block fits one row at that minimum they share it.
///   Otherwise the external group moves, whole, to rows of its own.
/// - Tiles stretch to fill their row. A group too long for one row splits into
///   equal rows, and an external group under it reuses the tile width above it.
/// - Only a single row of fewer than four tiles is capped, at the slot of a row
///   of four, so one AMS HT does not become a full-width slab.
library;

import 'dart:math' as math;

import 'package:dash_kit/dash_kit.dart' show DashSpace;
import 'package:material_ui/material_ui.dart' show kMinInteractiveDimension;

/// The smallest visible tile, in dp, at 100 % text.
const compactTileMinWidth = kMinInteractiveDimension;

/// Space between two tiles. Each slot owns it; the visible tile is the slot
/// minus this.
const compactTileGap = DashSpace.xs;

/// A float rounding must not push a block that fits exactly onto a second row.
const _epsilon = 0.001;

/// One row: tiles `[start, end)` of the block, each in a slot [slot] wide.
class CompactRow {
  const CompactRow(this.start, this.end, this.slot);

  final int start;
  final int end;

  /// The tile plus its gap; the last tile of the row has no gap after it.
  final double slot;

  int get count => end - start;

  double get tileWidth => math.max(0, slot - compactTileGap);

  @override
  bool operator ==(Object other) =>
      other is CompactRow &&
      other.start == start &&
      other.end == end &&
      other.slot == slot;

  @override
  int get hashCode => Object.hash(start, end, slot);

  @override
  String toString() => 'CompactRow([$start, $end) × $slot)';
}

class CompactBlockLayout {
  const CompactBlockLayout(this.rows, {this.externalFromRow});

  final List<CompactRow> rows;

  /// Index into [rows] of the first external row, which takes the "External"
  /// heading; null when there are no external tiles or they share a row with
  /// the AMS tiles.
  final int? externalFromRow;
}

/// Lays out [amsCount] AMS tiles and [externalCount] external tiles in
/// [width] dp. [textScale] below 1 counts as 1: a smaller font must not make a
/// tap target smaller.
///
/// A [width] under one tile cannot honour the minimum; every tile then gets a
/// row of its own, [width] wide, instead of failing.
CompactBlockLayout compactBlockLayout({
  required double width,
  required double textScale,
  required int amsCount,
  required int externalCount,
}) {
  assert(width.isFinite && width >= 0, 'width must be a finite, bounded size');
  assert(textScale.isFinite, 'textScale must be finite');
  assert(amsCount >= 0 && externalCount >= 0);
  final scale = math.max(1.0, textScale);
  final total = amsCount + externalCount;
  if (total == 0) return const CompactBlockLayout([]);
  final minSlot = compactTileMinWidth * scale + compactTileGap;
  // One gap more than the row shows: every slot carries its gap, the last one
  // included, and the widget takes that last gap back.
  final span = width + compactTileGap;

  if (amsCount > 0 && externalCount > 0 && total * minSlot <= span + _epsilon) {
    return CompactBlockLayout([
      CompactRow(0, total, _singleRowSlot(span, total, minSlot)),
    ]);
  }

  final ams = _group(span, amsCount, minSlot, 0);
  final external = _group(span, externalCount, minSlot, amsCount);
  // The external row keeps the AMS tile width when it fits at it, so the two
  // groups line up. At a narrow width it can hold more tiles per row than the
  // AMS rows do, and then it takes the slot its own tile count allows.
  final externalSlot =
      ams.rows.isNotEmpty && external.perRow * ams.slot <= span + _epsilon
      ? math.min(ams.slot, span / external.perRow)
      : external.slot;
  return CompactBlockLayout([
    ...ams.rows,
    for (final row in external.rows)
      CompactRow(row.start, row.end, externalSlot),
  ], externalFromRow: external.rows.isEmpty ? null : ams.rows.length);
}

double _singleRowSlot(double width, int count, double minSlot) {
  final slot = width / count;
  return count < 4 ? math.min(slot, math.max(minSlot, width / 4)) : slot;
}

({List<CompactRow> rows, double slot, int perRow}) _group(
  double width,
  int count,
  double minSlot,
  int offset,
) {
  if (count == 0) return (rows: const [], slot: 0, perRow: 0);
  final fits = math.max(1, ((width + _epsilon) / minSlot).floor());
  final rowCount = (count / fits).ceil();
  final perRow = (count / rowCount).ceil();
  final slot = rowCount == 1
      ? _singleRowSlot(width, count, minSlot)
      : width / perRow;
  return (
    rows: [
      for (var start = 0; start < count; start += perRow)
        CompactRow(
          offset + start,
          offset + math.min(start + perRow, count),
          slot,
        ),
    ],
    slot: slot,
    perRow: perRow,
  );
}
