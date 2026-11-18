import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/features/common/filament_dot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers.dart';

BoxDecoration _decoration(WidgetTester tester) =>
    tester
            .widget<Container>(
              find.descendant(
                of: find.byType(FilamentDot),
                matching: find.byType(Container),
              ),
            )
            .decoration!
        as BoxDecoration;

/// The dot of the archive's rows and calendar and of the nozzle sheet: a
/// filament colour, outlined so black and white show on both themes.
void main() {
  testWidgets('a colour is a circle of that colour at the dot size', (
    tester,
  ) async {
    await tester.pumpWidget(
      plApp(const Center(child: FilamentDot(color: Color(0xFF2E9F55)))),
    );

    expect(
      tester.getSize(find.byType(FilamentDot)),
      const Size(FilamentDot.size, FilamentDot.size),
    );
    final d = _decoration(tester);
    expect(d.shape, BoxShape.circle);
    expect(d.color, const Color(0xFF2E9F55));
  });

  testWidgets('a server hex string is the same colour', (tester) async {
    await tester.pumpWidget(plApp(Center(child: FilamentDot.hex('DE4343FF'))));

    expect(_decoration(tester).color, const Color(0xFFDE4343));
  });

  testWidgets('the outline is the tertiary ink, not the hairline', (
    tester,
  ) async {
    await tester.pumpWidget(
      plApp(const Center(child: FilamentDot(color: Color(0xFF000000)))),
    );

    final context = tester.element(find.byType(FilamentDot));
    final border = _decoration(tester).border! as Border;
    expect(border.top.color, DashTokens.of(context).textTertiary);
  });

  testWidgets('a null colour leaves the outline only', (tester) async {
    await tester.pumpWidget(
      plApp(const Center(child: FilamentDot(color: null))),
    );

    expect(_decoration(tester).color, isNull);
    expect(_decoration(tester).border, isNotNull);
  });
}
