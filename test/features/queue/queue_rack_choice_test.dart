import 'package:bambuddy_mobile/core/models/filament_requirement.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/core/printers/nozzle_rack.dart';
import 'package:bambuddy_mobile/features/queue/queue_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'queue_form_harness.dart';

/// The H2C rack pick as the print form offers it (server #1784).
///
/// The compatibility gate under test is that nothing here is version-checked:
/// the section appears only when the plate declares filament groups AND the
/// printer reports a rack, and an older server does neither — so the same build
/// talks to both generations and only sends the field where it means something.

/// Two 0.4 nozzles the plate can print from, one 0.6 it cannot, and three empty
/// docks — the rack of a machine in ordinary use.
List<NozzleRackSlot> _rack() => const [
      NozzleRackSlot(id: 16, nozzleDiameter: '0.4', nozzleType: 'HS01'),
      NozzleRackSlot(id: 17, nozzleDiameter: '0.6', nozzleType: 'HS01'),
      NozzleRackSlot(id: 18, nozzleDiameter: '0.4', nozzleType: 'HS01'),
      NozzleRackSlot(id: 19, nozzleDiameter: '', nozzleType: ''),
      NozzleRackSlot(id: 20, nozzleDiameter: '', nozzleType: ''),
      NozzleRackSlot(id: 21, nozzleDiameter: '', nozzleType: ''),
    ];

/// One filament, one rack-bound group wanting a 0.4 standard nozzle.
List<FilamentRequirement> _oneRackGroup() => FilamentRequirement.parseList({
      'filaments': [
        {
          'slot_id': 1,
          'type': 'PLA',
          'color': '#FF0000',
          'group_id': 1,
          'group': {
            'on_rack': true,
            'nozzle_diameter': '0.40',
            'volume_type': 'Standard',
            'filament_color': '#FF0000',
          },
        },
      ],
    });

/// How the row spells one of the two 0.4 standard positions.
String _position(int position) =>
    formL10n.queueEditRackPosition(position, '0.4 ${formL10n.nozzleFlowStandard}');

/// Opens the group's picker. The field shows the nozzle the group needs, which
/// is what makes it findable before anything has been chosen.
Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(find.textContaining(formL10n.nozzleFlowStandard).first);
  await tester.pumpAndSettle();
}

/// The menu as it stands open: every label, and the subset that can be tapped.
({List<String> offered, Set<String> enabled}) _entries(WidgetTester tester) {
  final buttons =
      tester.widgetList<MenuItemButton>(find.byType(MenuItemButton)).toList();
  final labels = [
    for (final button in buttons) ((button.child as Text?)?.data) ?? '',
  ];
  return (
    offered: labels,
    enabled: {
      for (var i = 0; i < buttons.length; i++)
        if (buttons[i].onPressed != null) labels[i],
    },
  );
}

void main() {
  setUp(setUpQueueForm);

  testWidgets('a plate with no rack groups is offered no pick', (tester) async {
    // What every non-H2C job looks like, and what every plate looks like on a
    // server that does not annotate the group table.
    await tester.pumpWidget(queueFormScreen(
      archiveDraft(model: 'H2C'),
      printers: const [printerH2C],
      nozzleRack: _rack(),
    ));
    await tester.pumpAndSettle();

    expect(find.text(formL10n.queueEditNozzleRack), findsNothing);

    await submitQueueForm(tester);

    expect(capturedBody?.containsKey('nozzle_rack_choice'), isFalse);
  });

  testWidgets('a printer that reports no rack is offered no pick',
      (tester) async {
    await tester.pumpWidget(queueFormScreen(
      archiveDraft(model: 'H2C'),
      printers: const [printerH2C],
      requirements: _oneRackGroup(),
    ));
    await tester.pumpAndSettle();

    expect(find.text(formL10n.queueEditNozzleRack), findsNothing);
  });

  testWidgets('picking a position sends it keyed by the filament group',
      (tester) async {
    await tester.pumpWidget(queueFormScreen(
      archiveDraft(model: 'H2C'),
      printers: const [printerH2C],
      nozzleRack: _rack(),
      requirements: _oneRackGroup(),
    ));
    await tester.pumpAndSettle();

    expect(find.text(formL10n.queueEditNozzleRack), findsOneWidget);

    await _openPicker(tester);
    await tester.tap(find.text(_position(3)));
    await tester.pumpAndSettle();

    await submitQueueForm(tester);

    // Group ids are object keys on the wire, so they arrive stringified — the
    // server parses them back to ints.
    expect(capturedBody?['nozzle_rack_choice'], {'1': 3});
  });

  testWidgets('a position the nozzle does not fit cannot be picked',
      (tester) async {
    await tester.pumpWidget(queueFormScreen(
      archiveDraft(model: 'H2C'),
      printers: const [printerH2C],
      nozzleRack: _rack(),
      requirements: _oneRackGroup(),
    ));
    await tester.pumpAndSettle();

    await _openPicker(tester);
    final menu = _entries(tester);

    // The 0.6 in position 2 and the three empty docks are shown — a choice the
    // form cannot honour says why it is unavailable — but none can be taken.
    expect(menu.offered, hasLength(rackPositions.length + 1));
    expect(menu.enabled, {
      formL10n.queueEditRackAuto,
      _position(1),
      _position(3),
    });
  });

  testWidgets('editing starts from the stored pick and can clear it',
      (tester) async {
    final item = QueueItem.fromJson({
      'id': 5,
      'position': 1,
      'status': 'pending',
      'printer_id': 1,
      'archive_id': 77,
      'archive_name': 'cube.3mf',
      'nozzle_rack_choice': {'1': 3},
    });

    await tester.pumpWidget(queueFormScreen(
      item,
      mode: QueueEditMode.edit,
      printers: const [printerH2C],
      nozzleRack: _rack(),
      requirements: _oneRackGroup(),
    ));
    await tester.pumpAndSettle();

    expect(find.text(_position(3)), findsOneWidget);

    await _openPicker(tester);
    await tester.tap(find.text(formL10n.queueEditRackAuto).last);
    await tester.pumpAndSettle();

    await submitQueueForm(tester, edit: true);

    // Explicitly null, not absent: the item still carries a pick, and only a
    // null clears it.
    expect(capturedBody?.containsKey('nozzle_rack_choice'), isTrue);
    expect(capturedBody?['nozzle_rack_choice'], isNull);
  });
}
