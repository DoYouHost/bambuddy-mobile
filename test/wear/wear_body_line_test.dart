import 'package:bambuddy_mobile/wear/wear_theme.dart';
import 'package:bambuddy_mobile/wear/widgets/wear_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<Text> pumpLine(
    WidgetTester tester,
    String text, {
    Color? color,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: wearBodyLine(text, color: color)),
      ),
    );
    return tester.widget<Text>(find.byType(Text));
  }

  testWidgets('centres the text in the body style', (tester) async {
    final line = await pumpLine(tester, 'hello');
    expect(line.data, 'hello');
    expect(line.textAlign, TextAlign.center);
    expect(line.style, WearText.body);
  });

  testWidgets('a colour replaces only the colour of the body style', (
    tester,
  ) async {
    final line = await pumpLine(tester, 'dim', color: wearMuted);
    expect(line.style, WearText.body.copyWith(color: wearMuted));
    expect(line.style?.fontSize, WearText.body.fontSize);
  });

  testWidgets('an empty string still builds', (tester) async {
    final line = await pumpLine(tester, '');
    expect(line.data, '');
    expect(line.textAlign, TextAlign.center);
  });
}
