import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/features/queue/queue_edit_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'queue_form_harness.dart';

/// The stored filament mapping across a printer switch in the edit form. A
/// mapping names slots by global tray id, which on another printer is another
/// spool or nothing at all; the web drops its picks when the printer changes
/// (`PrintModal/index.tsx`).
void main() {
  setUp(setUpQueueForm);

  const second = Printer(id: 2, name: 'P1S-Garage', model: 'P1S');

  Widget form() => queueFormScreen(
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
  );

  testWidgets('the same printer keeps the stored mapping', (tester) async {
    await tester.pumpWidget(form());
    await tester.pumpAndSettle();
    await submitQueueForm(tester, edit: true);

    expect(capturedBody?['ams_mapping'], [1]);
  });

  testWidgets('another printer does not inherit it', (tester) async {
    await tester.pumpWidget(form());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('P1S-Garage'));
    await tester.tap(find.text('P1S-Garage'));
    await tester.pumpAndSettle();
    await submitQueueForm(tester, edit: true);

    expect(capturedBody?.containsKey('ams_mapping'), isTrue);
    expect(capturedBody?['ams_mapping'], isNull);
  });
}
