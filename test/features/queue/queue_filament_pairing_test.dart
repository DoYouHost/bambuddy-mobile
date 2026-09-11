import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/features/queue/queue_edit_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';
import 'queue_form_harness.dart';

/// Pairing `filament_type` against `filament_color` when the item has no plate
/// requirements to read instead — the reprint-of-an-archive case, where the two
/// comma-separated strings are all there is.
///
/// The shapes here are measured, not invented. On a server in daily use the two
/// fields disagree in both directions: `filament_type` arrives deduplicated
/// (over 35 populated values, not one repeated a material), so two slots of one
/// material in two colours give one type and two colours — while the MQTT
/// fallback path drops a filament whose colour is empty and produces the
/// opposite. Iterating either list alone loses a slot from the other end.
void main() {
  /// The label `_overrideRow` builds, with an em dash where no type is known.
  String slot(int id, String type) => formL10n.queueEditSlotLabel('$id', type);

  Future<void> pumpItem(
    WidgetTester tester, {
    required String? type,
    required String? color,
  }) async {
    await tester.pumpWidget(
      queueFormScreen(
        // targetModel, not a printer id: the override list is what a MODEL
        // target offers, where the scheduler picks the machine and the
        // filaments are all the user can steer. A specific printer gets the
        // AMS mapping section instead, and none of these rows.
        QueueItem(
          id: 1,
          position: 1,
          status: 'pending',
          archiveId: 77,
          archiveName: 'cube.3mf',
          targetModel: 'X2D',
          slicedForModel: 'X2D',
          filamentType: type,
          filamentColor: color,
        ),
        mode: QueueEditMode.edit,
      ),
    );
    await settle(tester);
  }

  setUp(setUpQueueForm);

  testWidgets('a colour with no matching type still gets its slot', (
    tester,
  ) async {
    // The regression: bounding the loop by the type list rendered a two-colour
    // print as one filament, and the second colour was not shown anywhere.
    await pumpItem(tester, type: 'PLA', color: '#FF0000,#00FF00');

    expect(find.text(slot(1, 'PLA')), findsOneWidget);
    expect(
      find.text(slot(2, '—')),
      findsOneWidget,
      reason:
          'the second colour lost its row; a slot the print uses is missing '
          'from the override list entirely',
    );
  });

  testWidgets('a type with no matching colour still gets its slot', (
    tester,
  ) async {
    // The other direction, which already worked and must keep working: the
    // colour list is the shorter one when a slot carried no RFID tag.
    await pumpItem(tester, type: 'PLA,PETG', color: '#FF0000');

    expect(find.text(slot(1, 'PLA')), findsOneWidget);
    expect(find.text(slot(2, 'PETG')), findsOneWidget);
  });

  testWidgets('matched lists pair one to one', (tester) async {
    await pumpItem(tester, type: 'PLA,PETG', color: '#FF0000,#00FF00');

    expect(find.text(slot(1, 'PLA')), findsOneWidget);
    expect(find.text(slot(2, 'PETG')), findsOneWidget);
    expect(find.text(slot(3, '—')), findsNothing);
  });

  testWidgets('neither field leaves nothing to override', (tester) async {
    await pumpItem(tester, type: null, color: null);

    expect(find.text(formL10n.queueEditNoFilamentReqs), findsOneWidget);
  });
}
