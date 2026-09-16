import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/features/common/dash_icon_tile.dart';
import 'package:bambuddy_mobile/features/common/dash_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two pieces seven screens each used to spell out by hand. What is shared
/// is the paint, not the geometry, so these hold the paint: a tile whose fill
/// drifts off the accent, or a bar that loses the gauge track, looks like a
/// rendering fault and nothing else in the suite renders either colour.
void main() {
  late DashTokens tokens;

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDashThemeData(Brightness.dark, brand: bambuddyBrand),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              tokens = DashTokens.of(context);
              return Center(child: child);
            },
          ),
        ),
      ),
    );
  }

  group('DashIconTile', () {
    testWidgets('paints the accent fill under an accent glyph', (tester) async {
      await pump(
        tester,
        const DashIconTile(icon: Icons.print_outlined, size: 36, radius: 11),
      );

      final box = tester.widget<Container>(find.byType(Container));
      final decoration = box.decoration! as BoxDecoration;
      expect(decoration.color, tokens.accentGreen.withValues(alpha: 0.14));
      expect(decoration.borderRadius, BorderRadius.circular(11));
      expect(tester.getSize(find.byType(Container)), const Size(36, 36));
      expect(
        tester.widget<Icon>(find.byType(Icon)).color,
        tokens.accentGreenInk,
      );
    });

    testWidgets('takes the pair a flagged tile needs', (tester) async {
      await pump(
        tester,
        DashIconTile(
          icon: Icons.warning_amber_rounded,
          size: 36,
          radius: 11,
          ink: const Color(0xFFAA0000),
          fill: const Color(0x11AA0000),
        ),
      );

      final decoration =
          tester.widget<Container>(find.byType(Container)).decoration!
              as BoxDecoration;
      expect(decoration.color, const Color(0x11AA0000));
      expect(
        tester.widget<Icon>(find.byType(Icon)).color,
        const Color(0xFFAA0000),
      );
    });
  });

  group('DashProgressBar', () {
    testWidgets('runs the accent over the gauge track', (tester) async {
      await pump(tester, const DashProgressBar(value: 0.4, height: 8));

      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 0.4);
      expect(bar.minHeight, 8);
      expect(bar.backgroundColor, tokens.gaugeTrack);
      expect(bar.color, tokens.accentGreen);
      expect(
        tester.widget<ClipRRect>(find.byType(ClipRRect)).borderRadius,
        BorderRadius.circular(4),
      );
    });

    testWidgets('a bar that means something else keeps its colour', (
      tester,
    ) async {
      await pump(
        tester,
        const DashProgressBar(
          value: null,
          height: 5,
          radius: 3,
          color: Color(0xFFFF8800),
        ),
      );

      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, isNull, reason: 'indeterminate');
      expect(bar.color, const Color(0xFFFF8800));
      expect(bar.backgroundColor, tokens.gaugeTrack);
    });
  });
}
