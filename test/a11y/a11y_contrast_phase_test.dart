import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'a11y_harness.dart';

/// 13 px ink on a chip ground, [dx] dp from a whole pixel.
Future<void> _pump(
  WidgetTester tester, {
  required double dx,
  Color ink = const Color(0xFF10130E),
}) => a11yPump(
  tester,
  Scaffold(
    backgroundColor: const Color(0xFFF1F3EF),
    body: Padding(
      padding: EdgeInsets.only(left: 100 + dx, top: 100),
      child: Align(
        alignment: Alignment.topLeft,
        child: Text(
          '65°',
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
      ),
    ),
  ),
  a11yAccents.first,
  Brightness.light,
  window: const Size(411, 400),
  settleFor: const Duration(milliseconds: 100),
);

void main() {
  testWidgets(
    'a pixel phase that fools the framework guideline is measured again',
    (tester) async {
      final handle = tester.ensureSemantics();
      // Near-black on near-white, 16:1; at this x the commonest "dark" pixel is an
      // anti-aliased tint and the stock guideline reads 1.37:1.
      await _pump(tester, dx: 0.70);
      final stock = await const MinimumTextContrastGuideline().evaluate(tester);
      expect(stock.passed, isFalse, reason: 'the artifact this test stands on');

      await a11yMeetsAll(tester);
      handle.dispose();
    },
  );

  testWidgets('a real shortfall fails at every phase', (tester) async {
    final handle = tester.ensureSemantics();
    for (final dx in [0.0, 0.70]) {
      await _pump(tester, dx: dx, ink: const Color(0xFFC8CCC6));
      await expectLater(a11yMeetsAll(tester), throwsA(isA<TestFailure>()));
    }
    handle.dispose();
  });
}
