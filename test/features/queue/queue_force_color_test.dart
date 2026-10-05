import 'package:bambuddy_mobile/core/models/filament_requirement.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/features/queue/queue_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'queue_form_harness.dart';

/// `filament_overrides` on a job for one printer, as the web's
/// `printerOverridesForPlate` sends it: only the slots whose filament was
/// changed, each with its force-colour flag. A flag on a slot with no change
/// stays behind (#3133), and an edit with none left clears the field.
void main() {
  setUp(setUpQueueForm);

  Widget form({List<Map<String, dynamic>>? overrides}) => queueFormScreen(
    QueueItem.fromJson({
      'id': 5,
      'position': 1,
      'status': 'pending',
      'archive_id': 77,
      'printer_id': 1,
      'filament_overrides': ?overrides,
    }),
    schedule: QueueScheduleType.queue,
    mode: QueueEditMode.edit,
    requirements: const [
      FilamentRequirement(slotId: 1, type: 'PLA', color: '#FF0000'),
    ],
    live: const {
      1: PrinterStatus(
        id: 1,
        ams: [
          AmsUnit(
            id: 0,
            trays: [
              AmsTray(id: 0, trayType: 'PLA', trayColor: 'FF0000FF'),
              AmsTray(id: 1, trayType: 'PETG', trayColor: '00FF00FF'),
            ],
          ),
        ],
      ),
    },
  );

  const changed = {
    'slot_id': 1,
    'type': 'PETG',
    'color': '#00FF00',
    'force_color_match': true,
  };

  Future<void> toggleForce(WidgetTester tester) async {
    await tester.ensureVisible(find.text(formL10n.queueEditMappingAuto));
    await tester.tap(find.text(formL10n.queueEditMappingAuto));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, formL10n.fmSave).last);
    await tester.pumpAndSettle();
  }

  testWidgets('a changed slot rides along with its flag', (tester) async {
    await tester.pumpWidget(form(overrides: [changed]));
    await tester.pumpAndSettle();
    await submitQueueForm(tester, edit: true);

    final sent = capturedBody?['filament_overrides'] as List<dynamic>;
    expect(sent.single, containsPair('force_color_match', true));
    expect(sent.single, containsPair('type', 'PETG'));
  });

  testWidgets('a flag on an unchanged slot stays behind', (tester) async {
    await tester.pumpWidget(form());
    await tester.pumpAndSettle();
    await toggleForce(tester);
    await submitQueueForm(tester, edit: true);

    expect(capturedBody?.containsKey('filament_overrides'), isTrue);
    expect(capturedBody?['filament_overrides'], isNull);
  });

  testWidgets('the box in the mapping sets the changed slot\'s flag', (
    tester,
  ) async {
    await tester.pumpWidget(form(overrides: [changed]));
    await tester.pumpAndSettle();
    await toggleForce(tester);
    await submitQueueForm(tester, edit: true);

    final sent = capturedBody?['filament_overrides'] as List<dynamic>;
    expect(sent.single, containsPair('force_color_match', false));
  });
}
