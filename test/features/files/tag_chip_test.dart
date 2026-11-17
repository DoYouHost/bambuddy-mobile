import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/features/files/tag_sheets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers.dart';

void main() {
  testWidgets('a tag chip is a washed box with the chip radius', (
    tester,
  ) async {
    await tester.pumpWidget(plApp(const Scaffold(body: TagChip('PLA'))));

    final box =
        tester
                .widget<Container>(
                  find.descendant(
                    of: find.byType(TagChip),
                    matching: find.byType(Container),
                  ),
                )
                .decoration!
            as BoxDecoration;
    final t = DashTokens.of(tester.element(find.byType(TagChip)));
    expect(box.borderRadius, BorderRadius.circular(DashRadius.sm));
    expect(box.color, t.accentGreen.withValues(alpha: DashAlpha.faint));
    expect(find.text('PLA'), findsOneWidget);
  });
}
