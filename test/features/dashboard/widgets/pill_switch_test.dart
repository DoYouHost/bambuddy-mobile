import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/pill_switch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The knob sits on the accent track, so it is the brand's on-accent ink, not
  // a copy of the green brand's.
  testWidgets('in the dark theme the knob is the brand\'s on-accent ink', (
    tester,
  ) async {
    const brand = DashBrand(
      dark: DashAccent(fill: Color(0xFF9FC5FF), ink: Color(0xFF9FC5FF)),
      light: DashAccent(fill: Color(0xFF4A7FD0), ink: Color(0xFF2A5AA0)),
      onAccent: Color(0xFF0A1830),
    );
    await tester.pumpWidget(
      const Center(child: PillSwitch(on: true, tokens: DashTokens.dark(brand))),
    );

    final knob = tester.widget<Container>(
      find.descendant(
        of: find.byType(AnimatedAlign),
        matching: find.byType(Container),
      ),
    );
    expect((knob.decoration! as BoxDecoration).color, brand.onAccent);
  });
}
