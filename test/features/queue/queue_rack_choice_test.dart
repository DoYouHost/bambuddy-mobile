import 'package:bambuddy_mobile/core/models/filament_requirement.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/features/queue/queue_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

import 'dart:ui' show Tristate;

import 'queue_form_harness.dart';

/// The H2C rack pick (server #1784) as the web's `FilamentMapping.tsx` offers
/// it: a picker on each rack-bound filament's row of the mapping, showing the
/// position the server would assign until one is chosen.
///
/// Nothing here is version-checked: the picker appears only when the plate
/// declares filament groups AND the printer reports a rack, and an older server
/// does neither.

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

Map<String, dynamic> _filament(int slot, {bool onRack = true}) => {
  'slot_id': slot,
  'type': 'PLA',
  'color': '#FF0000',
  'group_id': slot,
  'group': {
    'on_rack': onRack,
    'nozzle_diameter': '0.40',
    'volume_type': 'Standard',
  },
};

/// One filament, one rack-bound group wanting a 0.4 standard nozzle.
List<FilamentRequirement> _oneRackGroup() => FilamentRequirement.parseList({
  'filaments': [_filament(1)],
});

/// Two filaments in two rack groups, both wanting the same 0.4 standard nozzle
/// — so both compete for the same two positions.
List<FilamentRequirement> _twoRackGroups() => FilamentRequirement.parseList({
  'filaments': [_filament(1), _filament(2)],
});

QueueItem _stored(Map<String, int> choice) => QueueItem.fromJson({
  'id': 5,
  'position': 1,
  'status': 'pending',
  'printer_id': 1,
  'archive_id': 77,
  'archive_name': 'cube.3mf',
  'nozzle_rack_choice': choice,
});

/// How a row's picker reads with position [n] chosen.
String _button(int n, [String diameter = '0.4']) =>
    '${formL10n.mappingRackSlot(n)} · $diameter';

Future<void> _openMapping(WidgetTester tester) async {
  final section = byLogId('queue_edit.mapping');
  await tester.ensureVisible(section);
  await tester.pumpAndSettle();
  await tester.tap(section);
  await tester.pumpAndSettle();
}

/// Opens the rack picker on the [index]th rack-bound row.
Future<void> _openRack(WidgetTester tester, [int index = 0]) async {
  await tester.tap(byLogId('queue_mapping.rack').at(index));
  await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester, int position) async {
  await tester.tap(byLogId('queue_mapping.rack_position_$position'));
  await tester.pumpAndSettle();
}

Future<void> _saveMapping(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, formL10n.fmSave).last);
  await tester.pumpAndSettle();
}

ListTile _option(WidgetTester tester, int position) => tester.widget<ListTile>(
  find.descendant(
    of: byLogId('queue_mapping.rack_position_$position'),
    matching: find.byType(ListTile),
  ),
);

Widget _form({
  QueueItem? item,
  List<FilamentRequirement>? requirements,
  List<NozzleRackSlot>? rack,
}) => queueFormScreen(
  item ?? archiveDraft(model: 'H2C'),
  mode: item == null ? QueueEditMode.create : QueueEditMode.edit,
  printers: const [printerH2C],
  nozzleRack: rack ?? _rack(),
  requirements: requirements ?? _oneRackGroup(),
);

void main() {
  setUp(setUpQueueForm);

  testWidgets('a plate with no rack groups is offered no pick', (tester) async {
    // What every non-H2C job looks like, and what every plate looks like on a
    // server that does not annotate the group table.
    await tester.pumpWidget(
      _form(
        requirements: const [
          FilamentRequirement(slotId: 1, type: 'PLA', color: '#FF0000'),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await _openMapping(tester);

    expect(byLogId('queue_mapping.rack'), findsNothing);
  });

  testWidgets('a printer that reports no rack is offered no pick', (
    tester,
  ) async {
    await tester.pumpWidget(_form(rack: const []));
    await tester.pumpAndSettle();
    await _openMapping(tester);

    expect(byLogId('queue_mapping.rack'), findsNothing);
  });

  testWidgets('a group on the fixed hotend reads L, not a picker', (
    tester,
  ) async {
    await tester.pumpWidget(
      _form(
        requirements: FilamentRequirement.parseList({
          'filaments': [_filament(1), _filament(2, onRack: false)],
        }),
      ),
    );
    await tester.pumpAndSettle();
    await _openMapping(tester);

    expect(byLogId('queue_mapping.rack'), findsOneWidget);
    expect(find.text(formL10n.extruderLeftShort), findsOneWidget);
  });

  testWidgets('untouched, the row shows what the server will assign and '
      'nothing is sent', (tester) async {
    await tester.pumpWidget(_form());
    await tester.pumpAndSettle();
    await _openMapping(tester);

    // The lowest fitting position, as `autoAssignRackPositions` takes it.
    expect(find.text(_button(1)), findsOneWidget);

    await _saveMapping(tester);
    await submitQueueForm(tester);

    expect(capturedBody?.containsKey('nozzle_rack_choice'), isFalse);
  });

  testWidgets('picking a position sends it keyed by the filament group', (
    tester,
  ) async {
    await tester.pumpWidget(_form());
    await tester.pumpAndSettle();
    await _openMapping(tester);
    await _openRack(tester);
    await _pick(tester, 3);

    expect(find.text(_button(3)), findsOneWidget);

    await _saveMapping(tester);
    // The form keeps the pick: the mapping opens on it again.
    await _openMapping(tester);
    expect(find.text(_button(3)), findsOneWidget);
    await _saveMapping(tester);
    await submitQueueForm(tester);

    // Group ids are object keys on the wire, so they arrive stringified — the
    // server parses them back to ints.
    expect(capturedBody?['nozzle_rack_choice'], {'1': 3});
  });

  testWidgets('all six positions are listed, and one that does not fit says '
      'why and cannot be picked', (tester) async {
    await tester.pumpWidget(_form());
    await tester.pumpAndSettle();
    await _openMapping(tester);
    await _openRack(tester);

    expect(
      [
        for (var p = 1; p <= 6; p++)
          if (_option(tester, p).enabled) p,
      ],
      [1, 3],
    );
    final standard = formL10n.nozzleFlowStandard;
    expect(
      find.text(
        formL10n.mappingRackWrongNozzle('0.6 $standard', '0.4 $standard'),
      ),
      findsOneWidget,
    );
    expect(find.text(formL10n.mappingRackEmptyPosition), findsNWidgets(3));
  });

  testWidgets('a position another group holds is not refused, as on the web', (
    tester,
  ) async {
    // The server refuses the pair at dispatch and says why on the item; the
    // picker leaves it to that, as `rackOptionsForGroup` does.
    await tester.pumpWidget(_form(requirements: _twoRackGroups()));
    await tester.pumpAndSettle();
    await _openMapping(tester);

    expect(find.text(_button(1)), findsOneWidget);
    expect(find.text(_button(3)), findsOneWidget);

    await _openRack(tester);
    expect(_option(tester, 3).enabled, isTrue);
    await _pick(tester, 3);
    await _saveMapping(tester);
    await submitQueueForm(tester);

    // Every group is written back once one is picked, not just the edited one.
    expect(capturedBody?['nozzle_rack_choice'], {'1': 3, '2': 3});
  });

  testWidgets('the chosen position is announced as the chosen one', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_form());
    await tester.pumpAndSettle();
    await _openMapping(tester);
    await _openRack(tester);

    SemanticsNode node(int p) =>
        tester.getSemantics(byLogId('queue_mapping.rack_position_$p'));
    expect(node(1).flagsCollection.isSelected, Tristate.isTrue);
    expect(node(3).flagsCollection.isSelected, Tristate.isFalse);
    handle.dispose();
  });

  testWidgets('a stored pick the rack no longer holds is called out loudly', (
    tester,
  ) async {
    // The server uploads the job and *then* refuses it, so it is not advisory.
    await tester.pumpWidget(_form(item: _stored({'1': 2})));
    await tester.pumpAndSettle();
    await _openMapping(tester);

    final warning = find.text(formL10n.queueEditRackPickStale);
    expect(warning, findsOneWidget);
    final tokens = DashTokens.of(tester.element(warning));
    expect(tester.widget<Text>(warning).style?.color, tokens.dangerInk);
  });

  testWidgets('a group no position fits says so', (tester) async {
    await tester.pumpWidget(
      _form(
        rack: const [
          NozzleRackSlot(id: 16, nozzleDiameter: '0.6', nozzleType: 'HS01'),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await _openMapping(tester);

    expect(
      find.text(
        formL10n.queueEditRackNoFit('0.4 ${formL10n.nozzleFlowStandard}'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('editing starts from the stored pick and keeps it', (
    tester,
  ) async {
    await tester.pumpWidget(_form(item: _stored({'1': 3})));
    await tester.pumpAndSettle();
    await _openMapping(tester);

    expect(find.text(_button(3)), findsOneWidget);

    await _saveMapping(tester);
    await submitQueueForm(tester, edit: true);

    expect(capturedBody?['nozzle_rack_choice'], {'1': 3});
  });
}
