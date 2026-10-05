import 'package:bambuddy_mobile/core/models/filament_requirement.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/features/queue/queue_edit_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'queue_form_harness.dart';

/// The filament mapping the edit form sends: matched again on save against
/// the printer as it is, as the web's `getMappingForPrinter`, from the form's
/// own picks — which a printer switch drops, as the web drops its picks
/// (`PrintModal/index.tsx`): a slot id names another spool on another printer.
void main() {
  setUp(setUpQueueForm);

  const second = Printer(id: 2, name: 'P1S-Garage', model: 'P1S');

  // Two red PLA spools on each printer: a match takes the first, a stored
  // pick the second.
  const twoReds = [
    AmsUnit(
      id: 0,
      trays: [
        AmsTray(id: 0, trayType: 'PLA', trayColor: 'FF0000FF'),
        AmsTray(id: 1, trayType: 'PLA', trayColor: 'FF0000FF'),
      ],
    ),
  ];

  Widget form({Map<int, PrinterStatus>? live}) => queueFormScreen(
    QueueItem.fromJson({
      'id': 5,
      'position': 1,
      'status': 'pending',
      'archive_id': 77,
      'printer_id': 1,
      'ams_mapping': [1],
    }),
    schedule: QueueScheduleType.queue,
    mode: QueueEditMode.edit,
    printers: const [printerX2D, second],
    requirements: const [
      FilamentRequirement(slotId: 1, type: 'PLA', color: '#FF0000'),
    ],
    live:
        live ??
        const {
          1: PrinterStatus(id: 1, ams: twoReds),
          2: PrinterStatus(id: 2, ams: twoReds),
        },
  );

  testWidgets('the same printer keeps the stored pick', (tester) async {
    await tester.pumpWidget(form());
    await tester.pumpAndSettle();
    await submitQueueForm(tester, edit: true);

    expect(capturedBody?['ams_mapping'], [1]);
  });

  testWidgets('another printer is matched on its own', (tester) async {
    await tester.pumpWidget(form());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('P1S-Garage'));
    await tester.tap(find.text('P1S-Garage'));
    await tester.pumpAndSettle();
    await submitQueueForm(tester, edit: true);

    expect(capturedBody?['ams_mapping'], [0]);
  });

  testWidgets('a printer reporting nothing leaves the mapping unsent', (
    tester,
  ) async {
    await tester.pumpWidget(form(live: const {}));
    await tester.pumpAndSettle();
    await submitQueueForm(tester, edit: true);

    expect(capturedBody?.containsKey('ams_mapping'), isFalse);
  });
}
