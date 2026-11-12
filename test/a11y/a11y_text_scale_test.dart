import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'a11y_harness.dart';

Future<Size> _textSize(WidgetTester tester, double scale) async {
  await a11yPump(
    tester,
    const Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: Text('Measuring stick', style: TextStyle(fontSize: 10)),
      ),
    ),
    a11yAccents.first,
    Brightness.light,
    window: const Size(411, 400),
    settleFor: const Duration(milliseconds: 100),
    textScale: scale,
  );
  return tester.getSize(find.text('Measuring stick'));
}

void main() {
  testWidgets('the surface is laid out at the text scale it is given', (
    tester,
  ) async {
    final normal = await _textSize(tester, 1);
    final large = await _textSize(tester, 2);
    expect(large.height, closeTo(normal.height * 2, 1));
    expect(large.width, closeTo(normal.width * 2, normal.width * 0.05));
  });

  test('the extra scales are the two the rule names, beside 100 %', () {
    expect(a11yTextScales, [1.5, 2.0]);
  });
}
