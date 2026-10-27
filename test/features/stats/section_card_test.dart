import 'package:bambuddy_mobile/features/stats/stats_common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers.dart';

void main() {
  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('a section card holds its title and metric toggle at text '
        '$scale', (tester) async {
      tester.view.physicalSize = const Size(411, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        plApp(
          Scaffold(
            body: SectionCard(
              title: pl.statsFailureAnalysis,
              stackTrailing: true,
              trailing: MetricToggle(value: StatMetric.weight, onChanged: _no),
              child: SizedBox(height: 20),
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

      expect(tester.takeException(), isNull);
      final title = tester.getRect(find.text(pl.statsFailureAnalysis));
      final toggle = tester.getRect(byLogId('stats.metric'));
      expect(toggle.right, lessThanOrEqualTo(411));
      if (toggle.top >= title.bottom) {
        expect(
          toggle.width,
          greaterThan(411 - 2 * 32 - 2),
          reason: 'under the title it spans the card, not hugging the left',
        );
      } else {
        expect(title.right, lessThanOrEqualTo(toggle.left));
      }
      if (scale == 2.0) {
        expect(toggle.top, greaterThanOrEqualTo(title.bottom));
      }
    });
  }
}

void _no(StatMetric _) {}
