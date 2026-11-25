import 'package:bambuddy_mobile/core/ams/compact_tile_layout.dart';
import 'package:flutter_test/flutter_test.dart';

/// Width a tile area has on a phone: the phone minus 100 dp, which is 2 × 16 of
/// card margin, card padding and group padding, and the two 1 dp borders each of
/// the card and the group card draws. Measured off the real card in
/// printer_card_test.dart ("the tile area is the phone minus 100 dp").
double _area(double phone) => phone - 100;

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

/// The slot of one visible 48 dp tile at 100 % text.
const _minSlot = compactTileMinWidth + compactTileGap;

void main() {
  group('rows', () {
    test('four AMS tiles and one external share a row on a 360 dp phone', () {
      final layout = _layout(_area(360), external: 1);
      expect(layout.rows, [CompactRow(0, 5, _area(360) / 5)]);
      expect(layout.externalFromRow, isNull);
      // 260 dp of area: five slots of exactly 52, a 48 dp tile each.
      expect(layout.rows.single.tileWidth, greaterThanOrEqualTo(48));
    });

    test('two external tiles go under their own heading on a 360 dp phone', () {
      final layout = _layout(_area(360), external: 2);
      final slot = _area(360) / 4;
      expect(layout.rows, [CompactRow(0, 4, slot), CompactRow(4, 6, slot)]);
      expect(layout.externalFromRow, 1);
    });

    test('a 393 dp phone cannot take six, a 412 dp phone can', () {
      expect(_layout(_area(393), external: 2).rows, hasLength(2));
      final layout = _layout(_area(412), external: 2);
      expect(layout.rows, [CompactRow(0, 6, _area(412) / 6)]);
      expect(layout.externalFromRow, isNull);
    });

    test('six tiles fit at exactly six slots and not a hair under', () {
      expect(_layout(6 * _minSlot, external: 2).rows, hasLength(1));
      expect(_layout(6 * _minSlot - 0.5, external: 2).rows, hasLength(2));
    });

    test('a float error at the boundary does not push a tile to a new row', () {
      // 0.1 + 0.2 style noise: the width is a hair under six slots.
      expect(_layout(6 * _minSlot - 1e-9, external: 2).rows, hasLength(1));
    });

    test(
      'a lone AMS HT with one external spool stays at the four-slot cap',
      () {
        final layout = _layout(_area(412), ams: 1, external: 1);
        expect(layout.rows, [CompactRow(0, 2, _area(412) / 4)]);
      },
    );

    test(
      'a lone AMS HT alone keeps the same cap, so tiles match between rows',
      () {
        expect(_layout(_area(412), ams: 1).rows, [
          CompactRow(0, 1, _area(412) / 4),
        ]);
      },
    );

    test('three tiles are capped too, four are not', () {
      final width = _area(412);
      expect(_layout(width, ams: 3).rows.single.slot, width / 4);
      expect(_layout(width, ams: 4).rows.single.slot, width / 4);
      expect(_layout(width, ams: 2).rows.single.slot, width / 4);
    });

    test('an AMS group of four fills its row when it is alone', () {
      expect(_layout(_area(360)).rows, [CompactRow(0, 4, _area(360) / 4)]);
    });

    test('five fit at 358 dp and no fewer', () {
      expect(_layout(5 * _minSlot, ams: 5).rows, hasLength(1));
      expect(_layout(5 * _minSlot - 1, ams: 5).rows, hasLength(2));
    });
  });

  group('text size', () {
    test('at 200 % the AMS group splits two and two and fills both rows', () {
      final width = _area(412);
      final layout = _layout(width, scale: 2, external: 2);
      expect(layout.rows, [
        CompactRow(0, 2, width / 2),
        CompactRow(2, 4, width / 2),
        CompactRow(4, 6, width / 2),
      ]);
      expect(layout.externalFromRow, 2);
    });

    test('the minimum grows with the text, the gap does not', () {
      // 150 %: 72 + 4 = 76 dp, three per row on a 262 dp area.
      final layout = _layout(_area(360), scale: 1.5);
      expect(layout.rows, [
        CompactRow(0, 2, _area(360) / 2),
        CompactRow(2, 4, _area(360) / 2),
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
        // 182 dp: the four AMS tiles wrap two and two at 91 dp, but three external
        // tiles still fit one row, and at the AMS slot they would need 273 dp.
        final layout = _layout(182, ams: 4, external: 3);
        final ams = layout.rows.first;
        final external = layout.rows.last;
        expect(layout.externalFromRow, 2);
        expect(external.count, 3);
        expect(external.slot, lessThan(ams.slot));
        expect(external.count * external.slot, lessThanOrEqualTo(182));
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
    test('a width under one slot puts every tile on its own row', () {
      final layout = _layout(40, ams: 3);
      expect(layout.rows, [
        CompactRow(0, 1, 40),
        CompactRow(1, 2, 40),
        CompactRow(2, 3, 40),
      ]);
    });

    test('a zero width does not throw', () {
      expect(_layout(0, ams: 2, external: 1).rows, isNotEmpty);
    });

    test(
      'a reused AMS slot never makes the external row wider than the area',
      () {
        // 1 AMS tile is capped at the 52 dp minimum; two external tiles need 104 dp,
        // and the area is a hair under that, inside the float tolerance.
        final layout = _layout(103.9995, ams: 1, external: 2);
        final external = layout.rows.last;
        expect(
          external.count * external.slot,
          lessThanOrEqualTo(103.9995 + 1e-9),
        );
      },
    );

    test('a tile is never negative, even in an area under the gap', () {
      for (final row in _layout(0, ams: 2, external: 1).rows) {
        expect(row.tileWidth, greaterThanOrEqualTo(0));
      }
      expect(_layout(2, ams: 1).rows.single.tileWidth, 0);
    });

    test('a text scale that is not a number is refused', () {
      expect(() => _layout(262, scale: double.nan), throwsAssertionError);
    });

    test('a narrow phone drops from five to four per row', () {
      // 320 dp phone: 222 dp, room for four 52 dp slots.
      final layout = _layout(_area(320), external: 1);
      expect(layout.rows, [
        CompactRow(0, 4, _area(320) / 4),
        CompactRow(4, 5, _area(320) / 4),
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
        103.9995,
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
                  row.count * row.slot,
                  lessThanOrEqualTo(width + 1e-9),
                  reason: reason,
                );
                // The floor holds whenever the area can honour it.
                final floor = 48 * (scale < 1 ? 1 : scale);
                if (width >= floor + compactTileGap) {
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
