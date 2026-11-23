import 'package:bambuddy_mobile/features/common/spool_colour_wheel.dart';
import 'package:flutter/rendering.dart' show RenderEditable;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers.dart';

/// The hex code under the wheel: it was cut to "0xFF00000" because the package
/// shows `0xAARRGGBB` and a copy button in a field sized from the unscaled
/// font. `DDDDDD` is the widest code the package sizes the field for.
void main() {
  RenderEditable code(WidgetTester tester) =>
      tester.state<EditableTextState>(find.byType(EditableText)).renderEditable;

  for (final scale in const [1.0, 1.5, 2.0]) {
    testWidgets('the code reads in full at ${scale * 100}% text', (
      tester,
    ) async {
      useLogicalWindow(tester, const Size(360, 800));
      await tester.pumpWidget(
        plApp(
          Scaffold(
            body: Center(
              child: SpoolColourWheel(
                color: const Color(0xFFDDDDDD),
                onChanged: (_) {},
              ),
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final field = code(tester);
      expect(field.text?.toPlainText(), 'DDDDDD');
      // Wider content than box is what scrolled the digits out of sight.
      expect(
        field.getMaxIntrinsicWidth(double.infinity),
        lessThanOrEqualTo(field.size.width + 0.5),
      );
      expect(
        field.text?.style?.fontSize,
        closeTo(14 * scale, 0.01),
        reason: 'scaled once, through the font size',
      );
      expect(tester.takeException(), isNull);
    });
  }
}
