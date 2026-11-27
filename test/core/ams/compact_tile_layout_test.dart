import 'package:bambuddy_mobile/core/ams/compact_tile_layout.dart';
import 'package:flutter_test/flutter_test.dart';

/// Width a tile area has on a phone: the phone minus 100 dp, which is 2 × 16 of
/// card margin, card padding and group padding, and the two 1 dp borders each of
/// the card and the group card draws. Measured off the real card in
/// printer_card_test.dart ("the tile area is the phone minus 100 dp").
double _area(double phone) => phone - 100;

/// The slot of a row of [perRow] tiles that fills [area]: every slot carries
/// one gap and the row's last gap is taken back, so the tiles span the area.
double _slot(double area, int perRow) => (area + compactTileGap) / perRow;

/// The area [count] tiles of the minimum width need: n tiles, n - 1 gaps.
double _fit(int count) =>
    count * (compactTileMinWidth + compactTileGap) - compactTileGap;

CompactBlockLayout _layout(
  double width, {
  double scale = 1,
  int ams = 4,
  int external = 0,
}) => compactBlockLayout(
  width: width,
  textScale: scale,
  amsCount: ams,
  externalCount: external,
);

void main() {
  group('rows', () {
    test('four AMS tiles and one external share a row on a 360 dp phone', () {
      final layout = _layout(_area(360), external: 1);
      expect(layout.rows, [CompactRow(0, 5, _slot(_area(360), 5))]);
      expect(layout.externalFromRow, isNull);
      // 260 dp of area: five 48 dp tiles and four gaps need 256.
      expect(layout.rows.single.tileWidth, greaterThanOrEqualTo(48));
    });

    test('two external tiles go under their own heading on a 360 dp phone', () {
      final layout = _layout(_area(360), external: 2);
      final slot = _slot(_area(360), 4);
      expect(layout.rows, [CompactRow(0, 4, slot), CompactRow(4, 6, slot)]);
      expect(layout.externalFromRow, 1);
    });

    test('a 393 dp phone cannot take six, a 412 dp phone can', () {
      expect(_layout(_area(393), external: 2).rows, hasLength(2));
      final layout = _layout(_area(412), external: 2);
      expect(layout.rows, [CompactRow(0, 6, _slot(_area(412), 6))]);
      expect(layout.externalFromRow, isNull);
    });

    test(
      'a 411.43 dp phone takes six: 1080 px at 420 dpi or 1440 px at 560 dpi',
      () {
        // 1440 px at 560 dpi is the same width. The area is 311.43 dp: under six
        // whole slots (312), over six tiles and five gaps (308).
        final phone = 1080 / (420 / 160);
        final layout = _layout(_area(phone), external: 2);
        expect(layout.rows, [CompactRow(0, 6, _slot(_area(phone), 6))]);
        expect(layout.rows.single.tileWidth, greaterThanOrEqualTo(48));
      },
    );

    test('a 407 dp phone cannot take six, a 408 dp phone can', () {
      expect(_layout(_area(407), external: 2).rows, hasLength(2));
      expect(_layout(_area(408), external: 2).rows, hasLength(1));
    });

    test('six tiles fit at six tiles and five gaps and not a hair under', () {
      expect(_layout(_fit(6), external: 2).rows, hasLength(1));
      expect(_layout(_fit(6) - 0.5, external: 2).rows, hasLength(2));
    });

    test('a float error at the boundary does not push a tile to a new row', () {
      // 0.1 + 0.2 style noise: the width is a hair under the six-tile fit.
      expect(_layout(_fit(6) - 1e-9, external: 2).rows, hasLength(1));
    });

    test('a full row ends at the area, not one gap past it', () {
      final area = _area(411.43);
      final row = _layout(area, external: 2).rows.single;
      expect(row.count * row.slot - compactTileGap, closeTo(area, 1e-9));
    });

    test(
      'a lone AMS HT with one external spool stays at the four-slot cap',
      () {
        final layout = _layout(_area(412), ams: 1, external: 1);
        expect(layout.rows, [CompactRow(0, 2, _slot(_area(412), 4))]);
      },
    );

    test(
      'a lone AMS HT alone keeps the same cap, so tiles match between rows',
      () {
        expect(_layout(_area(412), ams: 1).rows, [
          CompactRow(0, 1, _slot(_area(412), 4)),
        ]);
      },
    );

    test('three tiles are capped too, four are not', () {
      final slot = _slot(_area(412), 4);
      expect(_layout(_area(412), ams: 3).rows.single.slot, slot);
      expect(_layout(_area(412), ams: 4).rows.single.slot, slot);
      expect(_layout(_area(412), ams: 2).rows.single.slot, slot);
    });

    test('an AMS group of four fills its row when it is alone', () {
      expect(_layout(_area(360)).rows, [
        CompactRow(0, 4, _slot(_area(360), 4)),
      ]);
    });

    test('five fit at 356 dp of phone and no fewer', () {
      expect(_layout(_fit(5), ams: 5).rows, hasLength(1));
      expect(_layout(_fit(5) - 1, ams: 5).rows, hasLength(2));
      expect(_layout(_area(356), ams: 5).rows, hasLength(1));
    });
  });

  group('text size', () {
    test('at 200 % the AMS group splits two and two and fills both rows', () {
      final slot = _slot(_area(412), 2);
      final layout = _layout(_area(412), scale: 2, external: 2);
      expect(layout.rows, [
        CompactRow(0, 2, slot),
        CompactRow(2, 4, slot),
        CompactRow(4, 6, slot),
      ]);
      expect(layout.externalFromRow, 2);
    });

    test('the minimum grows with the text, the gap does not', () {
      // 150 %: a 72 dp tile and a 4 dp gap, three per row on a 260 dp area.
      final layout = _layout(_area(360), scale: 1.5);
      expect(layout.rows, [
        CompactRow(0, 2, _slot(_area(360), 2)),
        CompactRow(2, 4, _slot(_area(360), 2)),
      ]);
      for (final row in layout.rows) {
        expect(row.tileWidth, greaterThanOrEqualTo(72));
      }
    });

    test('a text scale under 1 counts as 1', () {
      expect(
        _layout(_area(360), scale: 0.8, external: 1).rows,
        _layout(_area(360), external: 1).rows,
      );
    });

    test('an external group below keeps the AMS tile width at 150 %', () {
      final layout = _layout(_area(412), scale: 1.5, external: 2);
      final slots = {for (final row in layout.rows) row.slot};
      expect(slots, hasLength(1));
    });
  });

  group('groups', () {
    test('the external group is never split across the AMS rows', () {
      for (final phone in [320.0, 360.0, 393.0, 412.0, 480.0]) {
        for (final scale in [1.0, 1.5, 2.0]) {
          final layout = _layout(_area(phone), scale: scale, external: 2);
          final from = layout.externalFromRow;
          if (from == null) continue;
          expect(layout.rows[from].start, 4, reason: '$phone dp, $scale×');
          for (final row in layout.rows.take(from)) {
            expect(row.end, lessThanOrEqualTo(4));
          }
        }
      }
    });

    test(
      'an external row holding more tiles than the AMS rows takes its own slot',
      () {
        // 182 dp: the four AMS tiles wrap two and two at 93 dp, but three external
        // tiles still fit one row, and at the AMS slot they would need 275 dp.
        final layout = _layout(182, ams: 4, external: 3);
        final ams = layout.rows.first;
        final external = layout.rows.last;
        expect(layout.externalFromRow, 2);
        expect(external.count, 3);
        expect(external.slot, lessThan(ams.slot));
        expect(
          external.count * external.slot - compactTileGap,
          lessThanOrEqualTo(182),
        );
      },
    );

    test('external tiles alone get their own group', () {
      final layout = _layout(_area(360), ams: 0, external: 2);
      expect(layout.externalFromRow, 0);
      expect(layout.rows.single.start, 0);
      expect(layout.rows.single.end, 2);
    });

    test('an empty block has no rows', () {
      expect(_layout(_area(360), ams: 0).rows, isEmpty);
      expect(_layout(_area(360), ams: 0).externalFromRow, isNull);
    });
  });

  group('odd input', () {
    test('a width under one tile puts every tile on its own row', () {
      // The tile is the whole 40 dp; its slot is that and the gap.
      final layout = _layout(40, ams: 3);
      expect(layout.rows, [
        CompactRow(0, 1, 44),
        CompactRow(1, 2, 44),
        CompactRow(2, 3, 44),
      ]);
      for (final row in layout.rows) {
        expect(row.tileWidth, 40);
      }
    });

    test('a zero width does not throw', () {
      expect(_layout(0, ams: 2, external: 1).rows, isNotEmpty);
    });

    test(
      'a reused AMS slot never makes the external row wider than the area',
      () {
        // 1 AMS tile is capped at the 52 dp minimum; two external tiles need
        // 100 dp, and the area is a hair under that, inside the float tolerance.
        final layout = _layout(99.9995, ams: 1, external: 2);
        final external = layout.rows.last;
        expect(
          external.count * external.slot - compactTileGap,
          lessThanOrEqualTo(99.9995 + 1e-9),
        );
      },
    );

    test('a tile is never negative, even in an area under the gap', () {
      for (final row in _layout(0, ams: 2, external: 1).rows) {
        expect(row.tileWidth, greaterThanOrEqualTo(0));
      }
      expect(_layout(0, ams: 1).rows.single.tileWidth, 0);
    });

    test('a text scale that is not a number is refused', () {
      expect(() => _layout(262, scale: double.nan), throwsAssertionError);
    });

    test('a narrow phone drops from five to four per row', () {
      // 320 dp phone: 220 dp, room for four tiles (204) and not five (256).
      final layout = _layout(_area(320), external: 1);
      expect(layout.rows, [
        CompactRow(0, 4, _slot(_area(320), 4)),
        CompactRow(4, 5, _slot(_area(320), 4)),
      ]);
      expect(layout.externalFromRow, 1);
    });
  });

  group('invariants', () {
    test('every tile appears once, in order, and no row overflows', () {
      final widths = [
        0.0,
        2.0,
        40.0,
        99.9995,
        for (var phone = 280.0; phone <= 600; phone += 7) _area(phone),
      ];
      for (final width in widths) {
        for (final scale in [0.8, 1.0, 1.3, 1.5, 2.0, 3.0]) {
          for (var ams = 0; ams <= 8; ams++) {
            for (var external = 0; external <= 3; external++) {
              final layout = _layout(
                width,
                scale: scale,
                ams: ams,
                external: external,
              );
              final reason = '$width dp, $scale×, $ams+$external';
              var next = 0;
              for (final row in layout.rows) {
                expect(row.start, next, reason: reason);
                expect(row.count, greaterThan(0), reason: reason);
                next = row.end;
                expect(
                  row.count * row.slot - compactTileGap,
                  lessThanOrEqualTo(width + 1e-9),
                  reason: reason,
                );
                // The floor holds whenever the area can honour it.
                final floor = 48 * (scale < 1 ? 1 : scale);
                if (width >= floor) {
                  expect(
                    row.tileWidth,
                    greaterThanOrEqualTo(floor - 0.01),
                    reason: reason,
                  );
                }
              }
              expect(next, ams + external, reason: reason);
              final from = layout.externalFromRow;
              if (external == 0) {
                expect(from, isNull, reason: reason);
              } else if (from != null) {
                expect(layout.rows[from].start, ams, reason: reason);
              }
            }
          }
        }
      }
    });
  });
}
