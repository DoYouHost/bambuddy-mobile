import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  SpoolAssignment external(int tray, {String? model}) =>
      SpoolAssignment.fromNative({
        'spool_id': 1,
        'printer_id': 7,
        'ams_id': 255,
        'tray_id': tray,
        'printer_model': ?model,
      });

  test('a rack printer names its inputs by hotend, as the web does', () {
    // `formatAssignmentSlotLabel`: input 255 (tray 1) feeds hotend 0.
    expect(assignmentSlotLabel(pl, external(1, model: 'H3C')), 'Ext-1');
    expect(assignmentSlotLabel(pl, external(0, model: 'H3C')), 'Ext-2');
    expect(assignmentSlotLabel(pl, external(5, model: 'H3C')), 'Ext-6');
    expect(external(1, model: 'H3C').extruder, isNull);
  });

  test('an older server without the model still has trays 2-8 only on a '
      'rack', () {
    // Tray 8 is input 253 (`external_slot_index`), which feeds hotend 2.
    expect(assignmentSlotLabel(pl, external(8)), 'Ext-3');
    // Trays 0 and 1 cannot be told apart from a dual holder without it.
    expect(assignmentSlotLabel(pl, external(0)), pl.extruderLeft);
  });

  test('a missing tray is no rack input', () {
    final missing = SpoolAssignment.fromNative({
      'spool_id': 1,
      'printer_id': 7,
      'ams_id': 255,
      'printer_model': 'H3C',
    });
    expect(missing.isRackExternal, isFalse);
    expect(assignmentSlotLabel(pl, missing), pl.externalSpool);
  });

  test('a dual holder keeps its sides', () {
    expect(assignmentSlotLabel(pl, external(0, model: 'X2D')), pl.extruderLeft);
    expect(
      assignmentSlotLabel(pl, external(1, model: 'X2D')),
      pl.extruderRight,
    );
  });
}
