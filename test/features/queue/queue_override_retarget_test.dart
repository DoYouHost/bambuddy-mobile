import 'package:bambuddy_mobile/core/models/filament_requirement.dart';
import 'package:bambuddy_mobile/core/models/plate_list.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'queue_form_harness.dart';

/// The filament overrides of a new model job across a plate switch — only a
/// new job can change plate. The web drops them when the plate changes
/// (`PrintModal/index.tsx`): they were picked for the slots of the plate on
/// screen then.
void main() {
  setUp(setUpQueueForm);

  final plates = PlateList.fromJson({
    'plates': [
      for (var i = 1; i <= 2; i++)
        {'index': i, 'name': 'Plate $i', 'object_count': 1},
    ],
    'is_multi_plate': true,
    'has_gcode': true,
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      queueFormScreen(
        QueueItem.fromJson({
          'id': 0,
          'position': 0,
          'status': 'pending',
          'archive_id': 77,
          'target_model': 'X2D',
          'plate_id': 1,
          'filament_overrides': [
            {
              'slot_id': 1,
              'type': 'PETG',
              'color': '#00FF00',
              'force_color_match': true,
            },
          ],
        }),
        plates: plates,
        requirements: const [
          FilamentRequirement(slotId: 1, type: 'PLA', color: '#FF0000'),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the plate it was picked for keeps them', (tester) async {
    await pump(tester);
    await submitQueueForm(tester);

    expect(capturedBody?['filament_overrides'], isNotEmpty);
  });

  testWidgets('another plate drops them', (tester) async {
    await pump(tester);
    await tester.scrollUntilVisible(
      find.text(formL10n.queueEditPlateNamed(1, 'Plate 1')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text(formL10n.queueEditPlateNamed(1, 'Plate 1')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(formL10n.queueEditPlateNamed(2, 'Plate 2')).last,
    );
    await tester.pumpAndSettle();
    await submitQueueForm(tester);

    expect(capturedBody?['filament_overrides'], isNull);
  });
}
