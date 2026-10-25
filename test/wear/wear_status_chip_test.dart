import 'package:bambuddy_mobile/core/settings/appearance_prefs.dart';
import 'package:bambuddy_mobile/core/theme/app_brand.dart';
import 'package:bambuddy_mobile/wear/wear_status.dart';
import 'package:bambuddy_mobile/wear/wear_theme.dart';
import 'package:bambuddy_mobile/wear/widgets/wear_status_chip.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  Future<Color?> labelColour(
    WidgetTester tester,
    WearState state,
    String label, {
    ColorScheme? scheme,
  }) async {
    await tester.pumpWidget(
      plApp(
        Theme(
          data: wearTheme(scheme),
          child: Scaffold(body: WearStatusChip(state: state)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.widget<Text>(find.text(label)).style?.color;
  }

  // The phone's status chip is the accent, so the watch's is too.
  testWidgets('printing wears the accent', (tester) async {
    final orange = wearSeedScheme(accentPresets[AccentSource.orange]!);
    expect(
      await labelColour(
        tester,
        WearState.printing,
        pl.widgetStatusPrinting,
        scheme: orange,
      ),
      orange.primary,
    );
  });

  testWidgets('a fault keeps its red whatever the accent', (tester) async {
    final orange = wearSeedScheme(accentPresets[AccentSource.orange]!);
    expect(
      await labelColour(
        tester,
        WearState.failed,
        pl.widgetStatusFailed,
        scheme: orange,
      ),
      const Color(0xFFEF5350),
    );
  });
}
