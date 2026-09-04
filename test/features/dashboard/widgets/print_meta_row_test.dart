import 'package:bambuddy_mobile/features/dashboard/widgets/print_meta_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The real trio, with the ETA on a 12-hour clock — the one that made the line
/// too wide in the first place.
const _items = [
  PrintMetaItem(icon: Icons.schedule, text: 'remaining 52min'),
  PrintMetaItem(icon: Icons.flag_outlined, text: 'ETA 11:09 PM'),
  PrintMetaItem(icon: Icons.layers_outlined, text: '113/264'),
];

/// The row's own constants, which it does not export.
const _gap = 14.0;

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  TextScaler scaler = TextScaler.noScaling,
  TextStyle? ambient,
}) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: scaler),
          child: DefaultTextStyle.merge(
            style: ambient,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: const PrintMetaRow(items: _items),
              ),
            ),
          ),
        ),
      ),
    ));

List<Offset> _corners(WidgetTester tester) => [
      for (var i = 0; i < _items.length; i++)
        tester.getTopLeft(find.byType(PrintMetaItem).at(i)),
    ];

List<double> _widths(WidgetTester tester) => [
      for (var i = 0; i < _items.length; i++)
        tester.getSize(find.byType(PrintMetaItem).at(i)).width,
    ];

void main() {
  testWidgets('one line while one line fits', (tester) async {
    await _pump(tester, width: 1000);
    final at = _corners(tester);

    expect({for (final corner in at) corner.dy}, hasLength(1));
    // Packed by their own widths, not spread into columns: there is room.
    expect(at[1].dx - at[0].dx, _widths(tester).first + _gap);
  });

  testWidgets('too wide for one line: two columns that line up',
      (tester) async {
    // Measured, not assumed: the font a test renders with is not the font a
    // phone renders with, and the whole layout is a decision about width.
    await _pump(tester, width: 1000);
    final widths = _widths(tester);
    final widest = widths.reduce((a, b) => a > b ? a : b);
    // Wide enough that every item fits a column with room to spare, narrow
    // enough that the three of them do not fit one line.
    final width = 2 * widest + _gap + 40;
    expect(widths.reduce((a, b) => a + b) + 2 * _gap, greaterThan(width));

    await _pump(tester, width: width);
    final at = _corners(tester);
    final columnWidth = (width - _gap) / 2;

    expect(at[2].dy, greaterThan(at[0].dy), reason: 'it broke into two lines');
    expect(at[2].dx, at[0].dx, reason: 'the second line starts a column, not a run');
    expect(at[1].dx - at[0].dx, columnWidth + _gap,
        reason: 'the ETA sits in the second column — a Wrap would butt it '
            'against the end of the first item instead');
    expect(at[0].dx, 0);
  });

  testWidgets('too narrow even for two columns: one column', (tester) async {
    await _pump(tester, width: 1000);
    final widest = _widths(tester).reduce((a, b) => a > b ? a : b);

    await _pump(tester, width: widest + 10);
    final at = _corners(tester);

    expect({for (final corner in at) corner.dx}, {0.0},
        reason: 'three half-cut columns read worse than three lines');
    expect(at[0].dy, lessThan(at[1].dy));
    expect(at[1].dy, lessThan(at[2].dy));
  });

  testWidgets('measures the label the way it is painted, spacing and all',
      (tester) async {
    // The app's `bodyMedium` carries letter spacing, and every label inherits
    // it: measuring the item's own style alone read the row narrower than it
    // paints, kept three items on one line that holds two, and put the striped
    // bar on a real printer card.
    const ambient = TextStyle(letterSpacing: 2);
    await _pump(tester, width: 1000, ambient: ambient);
    // The right edge of the last item, not the row's own size: the row is given
    // the width it is given, and only the content says what one line needs.
    final last = find.byType(PrintMetaItem).at(_items.length - 1);
    final onOneLine =
        tester.getTopLeft(last).dx + tester.getSize(last).width;

    await _pump(tester, width: onOneLine - 1, ambient: ambient);

    expect(tester.takeException(), isNull);
    expect(_corners(tester)[2].dy, greaterThan(_corners(tester)[0].dy),
        reason: 'a line that does not fit has to break, not overflow');
  });

  testWidgets('a system font size nothing fits ellipsizes instead of spilling',
      (tester) async {
    // No column can hold the label here, and an overflowing Row would paint the
    // stripes over the card. The test fails on its own if that happens.
    await _pump(tester, width: 200, scaler: const TextScaler.linear(2));

    expect(tester.takeException(), isNull);
    expect(find.byType(PrintMetaItem), findsNWidgets(3));
  });
}
