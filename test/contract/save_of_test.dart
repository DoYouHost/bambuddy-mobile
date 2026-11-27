import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// `saveOf` takes its overrides as `Object?` so that a null can mean "clear",
/// which gives up the int-to-double coercion a typed parameter has.
void main() {
  final row = Printer.fromJson({
    'id': 1,
    'name': 'X1C',
    'ip_address': '10.0.0.2',
    'model': 'X1C',
    'wear_cost_per_hour': 0.25,
    'dispatch_priority': 2,
  });

  test('an int literal is a rate like any other', () {
    expect(saveOf(row, wearCostPerHour: 0).wearCostPerHour, 0.0);
    expect(saveOf(row, wearCostPerHour: 36).wearCostPerHour, 36.0);
  });

  test('left out keeps the row\'s value, null clears it', () {
    final kept = saveOf(row);
    expect(kept.wearCostPerHour, 0.25);
    expect(kept.dispatchPriority, 2);
    expect(kept.model, 'X1C');

    final cleared = saveOf(
      row,
      wearCostPerHour: null,
      dispatchPriority: null,
      model: null,
    );
    expect(cleared.wearCostPerHour, isNull);
    expect(cleared.dispatchPriority, isNull);
    expect(cleared.model, isNull);
  });

  test('served defaults to the row\'s keys and can be narrowed', () {
    expect(saveOf(row).served, row.servedKeys);
    expect(saveOf(row, served: const {}).served, isEmpty);
  });
}
