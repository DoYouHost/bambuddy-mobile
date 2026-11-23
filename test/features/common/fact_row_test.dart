import 'package:bambuddy_mobile/features/common/fact_row.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers.dart';

/// The one row every list of facts uses (a spool's details, a user's, a
/// nozzle's figures). Its layout rules are what the screens relied on one by one,
/// so each is pinned here once.
void main() {
  Future<void> pump(WidgetTester tester, Widget row, {double scale = 1}) =>
      tester.pumpWidget(
        plApp(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 328, child: row),
          ),
          builder: textScaled(scale),
        ),
      );

  Rect rowRect(WidgetTester tester) => tester.getRect(find.byType(FactRow));

  group('layout', () {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('a short value sits at the row\'s end, at text scale $scale', (
        tester,
      ) async {
        await pump(
          tester,
          FactRow(label: 'Wear', value: '8%'),
          scale: scale,
        );

        final value = tester.getRect(find.text('8%'));
        // The padding is the row's own; the value ends where the row's content does.
        expect(value.right, closeTo(rowRect(tester).right, 0.5));
        expect(
          tester.getRect(find.text('Wear')).left,
          closeTo(rowRect(tester).left, 0.5),
        );
      });
    }

    testWidgets('a long value uses more than half the row when its label is '
        'short, instead of wrapping at half', (tester) async {
      await pump(
        tester,
        FactRow(label: 'Serial', value: '0K00A91C3X002-ABCDEF'),
        scale: 2,
      );

      expect(
        tester.getRect(find.text('0K00A91C3X002-ABCDEF')).width,
        greaterThan(rowRect(tester).width / 2),
      );
    });

    testWidgets('a long label wraps before it crowds the value out', (
      tester,
    ) async {
      await pump(
        tester,
        FactRow(
          label: 'A very long label that has to wrap somewhere sensible',
          value: '12',
        ),
        scale: 2,
      );

      expect(
        tester.getRect(find.byType(FactRow)).width,
        closeTo(328, 0.5),
        reason: 'nothing overflowed',
      );
      expect(
        tester
            .getRect(
              find.text(
                'A very long label that has to wrap somewhere sensible',
              ),
            )
            .width,
        lessThanOrEqualTo(328 * 0.45 + 0.5),
      );
      expect(tester.getRect(find.text('12')).right, closeTo(328, 0.5));
    });

    testWidgets('stacked puts the value under its label, from the start', (
      tester,
    ) async {
      await pump(
        tester,
        FactRow(label: 'Note', value: 'free text', stacked: true),
      );

      final label = tester.getRect(find.text('Note'));
      final value = tester.getRect(find.text('free text'));
      expect(value.top, greaterThan(label.bottom - 0.5));
      expect(value.left, closeTo(label.left, 0.5));
    });

    testWidgets('below goes under the row, lined up with the label', (
      tester,
    ) async {
      await pump(
        tester,
        FactRow(
          label: 'Location',
          value: 'Shelf 2',
          below: const Text('Dry: 31 %'),
        ),
      );

      final label = tester.getRect(find.text('Location'));
      final below = tester.getRect(find.text('Dry: 31 %'));
      expect(
        below.top,
        greaterThan(tester.getRect(find.text('Shelf 2')).bottom),
      );
      expect(below.left, closeTo(label.left, 0.5));
    });

    testWidgets('an icon leads the row and the label starts after it', (
      tester,
    ) async {
      await pump(
        tester,
        FactRow(icon: Icons.place_outlined, label: 'Place', value: 'Shelf'),
      );

      final icon = tester.getRect(find.byIcon(Icons.place_outlined));
      expect(tester.getRect(find.text('Place')).left, greaterThan(icon.right));
    });

    testWidgets('a custom value takes the row\'s alignment and text style', (
      tester,
    ) async {
      await pump(
        tester,
        FactRow.custom(label: 'Colour', value: const Text('PLA')),
      );

      expect(
        tester.getRect(find.text('PLA')).right,
        closeTo(rowRect(tester).right, 0.5),
      );
      final style = tester
          .renderObject<RenderParagraph>(find.text('PLA'))
          .text
          .style;
      expect(style, isNotNull);
    });
  });
}
