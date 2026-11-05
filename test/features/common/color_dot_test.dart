import 'package:bambuddy_mobile/features/common/color_dot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers.dart';

BoxDecoration _decoration(WidgetTester tester) =>
    tester
            .widget<Container>(
              find.descendant(
                of: find.byType(ColorDot),
                matching: find.byType(Container),
              ),
            )
            .decoration!
        as BoxDecoration;

void main() {
  testWidgets('a dot is a circle of its colour at its size', (tester) async {
    await tester.pumpWidget(
      plApp(const Center(child: ColorDot(color: Color(0xFF2E9F55), size: 20))),
    );

    expect(tester.getSize(find.byType(ColorDot)), const Size(20, 20));
    final d = _decoration(tester);
    expect(d.shape, BoxShape.circle);
    expect(d.color, const Color(0xFF2E9F55));
  });

  testWidgets('a null colour leaves the outline only', (tester) async {
    await tester.pumpWidget(plApp(const ColorDot(color: null)));

    expect(_decoration(tester).color, isNull);
    expect(_decoration(tester).border, isNotNull);
  });

  testWidgets('a ring is a heavier outline than the hairline', (tester) async {
    await tester.pumpWidget(plApp(const ColorDot(color: Color(0xFF000000))));
    final plain = (_decoration(tester).border! as Border).top.width;

    await tester.pumpWidget(
      plApp(const ColorDot(color: Color(0xFF000000), ring: Color(0xFFFF0000))),
    );
    final ringed = (_decoration(tester).border! as Border).top;
    expect(ringed.width, greaterThan(plain));
    expect(ringed.color, const Color(0xFFFF0000));
  });
}
