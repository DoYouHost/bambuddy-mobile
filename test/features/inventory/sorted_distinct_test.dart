import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('trims, drops blanks and nulls, keeps each value once', () {
    expect(sortedDistinct([' Shelf ', 'Shelf', '', '   ', null, 'Box']), [
      'Box',
      'Shelf',
    ]);
  });

  test('plain sort order: capitals before lower case', () {
    // What the three pickers showed before they shared this; a case-blind
    // order would be a change of its own.
    expect(sortedDistinct(['eSun', 'Bambu', 'Zebra']), [
      'Bambu',
      'Zebra',
      'eSun',
    ]);
  });

  test('nothing in, nothing out', () {
    expect(sortedDistinct(const []), isEmpty);
  });
}
