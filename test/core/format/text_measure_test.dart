import 'package:bambuddy_mobile/core/format/text_measure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _style = TextStyle(fontSize: 12);
const _label = 'ETA 11:09 PM';

/// Renders the same label and hands back both numbers: what the paragraph took
/// and what the measurement promised it would take.
Future<(double painted, double measured)> _both(
  WidgetTester tester, {
  TextScaler scaler = TextScaler.noScaling,
}) async {
  late double measured;
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: scaler),
        child: Align(
          alignment: Alignment.topLeft,
          child: Builder(
            builder: (context) {
              measured = textWidth(context, _label, _style);
              return const Text(_label, style: _style, maxLines: 1);
            },
          ),
        ),
      ),
    ),
  );
  return (tester.getSize(find.text(_label)).width, measured);
}

void main() {
  testWidgets('promises exactly what the paragraph takes', (tester) async {
    final (painted, measured) = await _both(tester);

    expect(measured, painted);
  });

  testWidgets('follows the system font size, which is the whole point', (
    tester,
  ) async {
    // A label measured at 1.0 and painted at 2.0 decides a layout wrongly at
    // exactly the setting where the room runs out.
    final (painted, measured) = await _both(
      tester,
      scaler: const TextScaler.linear(2),
    );

    expect(measured, painted);
    expect(measured, greaterThan((await _both(tester)).$2));
  });
}
