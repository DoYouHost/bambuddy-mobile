import 'package:bambuddy_mobile/features/controller/controller_files.dart';
import 'package:bambuddy_mobile/features/controller/controller_prints.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';
import 'controller_harness.dart';

/// The Prints tab's rail: which view it shows, and that the choice outlives a
/// visit to another tab, as the library's folder does.
void main() {
  Future<void> pump(WidgetTester tester) async {
    await pumpControllerScreen(tester);
    await tester.tap(byLogId('controller.tab_prints'));
    await settle(tester);
  }

  testWidgets('the tab opens on Files, and the rail switches the view', (
    tester,
  ) async {
    await pump(tester);

    expect(find.byType(ControllerFiles), findsOneWidget);
    for (final view in ControllerPrintsView.values) {
      expect(byLogId(view.logId), findsOneWidget);
    }

    await tester.tap(byLogId(ControllerPrintsView.queue.logId));
    await settle(tester);

    expect(find.byType(ControllerFiles), findsNothing);
  });

  testWidgets('another tab and back keeps the chosen view', (tester) async {
    await pump(tester);
    await tester.tap(byLogId(ControllerPrintsView.archive.logId));
    await settle(tester);

    await tester.tap(byLogId('controller.tab_heat'));
    await settle(tester);
    await tester.tap(byLogId('controller.tab_prints'));
    await settle(tester);

    expect(find.byType(ControllerFiles), findsNothing);
    final archive = tester.widget<ControllerPrints>(
      find.byType(ControllerPrints),
    );
    expect(archive.view, ControllerPrintsView.archive);
  });
}
