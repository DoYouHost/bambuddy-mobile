import 'package:bambuddy_mobile/core/models/available_filament.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/features/queue/queue_edit_screen.dart';
import 'package:flutter/material.dart';
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
    List<AvailableFilament> availableFilaments = const [],
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
        availableFilaments: availableFilaments,
      ),
    );
    await settle(tester);
  }

  setUp(setUpQueueForm);

  testWidgets(
    'single-material multi-color print gives all slots the deduplicated material',
    (tester) async {
      // The server-side archive extractor (services/archive.py) deduplicates
      // the type list independently from colors. If a multi-color print uses
      // one material across all slots, types collapses to 1 while colors has
      // every slot. Every slot must share that deduplicated type.
      await pumpItem(tester, type: 'PLA', color: '#FF0000,#00FF00');

      expect(find.text(slot(1, 'PLA')), findsOneWidget);
      expect(find.text(slot(2, 'PLA')), findsOneWidget);
    },
  );

  testWidgets(
    'saving a force color match on deduplicated slot carries the correct type',
    (tester) async {
      await pumpItem(tester, type: 'PLA', color: '#FF0000,#00FF00');

      // Scroll down to make slot 2 visible
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();

      // Checkboxes: slot 1, slot 2. Tap slot 2 force color match.
      final checkboxes = find.byType(Checkbox);
      await tester.tap(checkboxes.at(1));
      await tester.pumpAndSettle();

      await submitQueueForm(tester, edit: true);

      final overrides = capturedBody?['filament_overrides'] as List<dynamic>?;
      expect(overrides, isNotNull);
      expect(overrides!.length, 1);
      expect(overrides.first, {
        'slot_id': 2,
        'type': 'PLA',
        'color': '#00FF00',
        'color_name': '#00FF00',
        'force_color_match': true,
      });
    },
  );

  testWidgets(
    'multi-material print with more colours than types shows em dash for unknown slot',
    (tester) async {
      await pumpItem(
        tester,
        type: 'PLA,PETG',
        color: '#FF0000,#00FF00,#0000FF',
      );

      expect(find.text(slot(1, 'PLA')), findsOneWidget);
      expect(find.text(slot(2, 'PETG')), findsOneWidget);
      expect(find.text(slot(3, '—')), findsOneWidget);
    },
  );

  testWidgets(
    'slot with unknown material disables force color match until a spool is chosen',
    (tester) async {
      await pumpItem(
        tester,
        type: 'PLA,PETG',
        color: '#FF0000,#00FF00,#0000FF',
      );

      // Checkboxes are ordered by slot
      final checkboxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
      expect(checkboxes.length, 3);
      // Slots 1 and 2 have known types: active checkboxes
      expect(checkboxes.elementAt(0).onChanged, isNotNull);
      expect(checkboxes.elementAt(1).onChanged, isNotNull);
      // Slot 3 has unknown type and no override selected yet: disabled checkbox
      expect(checkboxes.elementAt(2).onChanged, isNull);
    },
  );

  testWidgets(
    'slot with unknown material offers all available filaments and enables force checkbox once selected',
    (tester) async {
      await pumpItem(
        tester,
        type: 'PLA,PETG',
        color: '#FF0000,#00FF00,#0000FF',
        availableFilaments: const [
          AvailableFilament(type: 'ABS', color: '#112233'),
        ],
      );

      // Initially slot 3 has disabled checkbox
      var checkboxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
      expect(checkboxes.elementAt(2).onChanged, isNull);

      // Scroll slot 3 into view and tap dropdown field
      final slot3Dropdown = find.text('${formL10n.queueEditOriginal}: —');
      await tester.ensureVisible(slot3Dropdown);
      await tester.pumpAndSettle();
      await tester.tap(slot3Dropdown);
      await tester.pumpAndSettle();

      // Should show ABS option in the dropdown list
      expect(find.text('ABS'), findsOneWidget);
      await tester.tap(find.text('ABS'));
      await tester.pumpAndSettle();

      // Now slot 3 has an override selected, checkbox must be enabled
      checkboxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
      expect(checkboxes.elementAt(2).onChanged, isNotNull);
    },
  );

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
