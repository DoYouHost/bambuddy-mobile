import 'package:bambuddy_mobile/core/models/printer_location.dart';
import 'package:bambuddy_mobile/features/locations/printer_locations_providers.dart';
import 'package:flutter_test/flutter_test.dart';

PrinterLocation _l(String name, int count) =>
    PrinterLocation(name: name, printerCount: count);

void main() {
  group('compareLocationNames', () {
    test('a run of digits compares as a number', () {
      expect(compareLocationNames('Rack 2', 'Rack 10'), lessThan(0));
      expect(compareLocationNames('Rack 10', 'Rack 2'), greaterThan(0));
    });

    test('case does not matter', () {
      expect(compareLocationNames('attic', 'Attic'), 0);
      expect(compareLocationNames('attic', 'Basement'), lessThan(0));
    });

    test('a name that is a prefix of another comes first', () {
      expect(compareLocationNames('Rack', 'Rack 1'), lessThan(0));
    });

    test('an empty name and odd characters do not throw', () {
      expect(compareLocationNames('', 'a'), lessThan(0));
      expect(compareLocationNames('Łódź 3', 'Łódź 20'), lessThan(0));
    });
  });

  group('arrangeLocations', () {
    final all = [_l('Rack 10', 1), _l('rack 2', 4), _l('Attic', 0)];

    test('sorts by name, naturally, by default', () {
      expect(arrangeLocations(all).map((l) => l.name), [
        'Attic',
        'rack 2',
        'Rack 10',
      ]);
    });

    test('name descending reverses it', () {
      expect(
        arrangeLocations(all, sort: LocationSort.nameDesc).map((l) => l.name),
        ['Rack 10', 'rack 2', 'Attic'],
      );
    });

    test('count orders fall back to the name on a tie', () {
      final tied = [_l('B', 2), _l('A', 2), _l('C', 0)];
      expect(
        arrangeLocations(tied, sort: LocationSort.countDesc).map((l) => l.name),
        ['A', 'B', 'C'],
      );
      expect(
        arrangeLocations(tied, sort: LocationSort.countAsc).map((l) => l.name),
        ['C', 'A', 'B'],
      );
    });

    test('the query is a case-insensitive substring and is trimmed', () {
      expect(arrangeLocations(all, query: '  RACK ').length, 2);
      expect(arrangeLocations(all, query: 'zzz'), isEmpty);
    });

    test('hide empty drops a location with no printer', () {
      expect(
        arrangeLocations(all, hideEmpty: true).map((l) => l.name),
        isNot(contains('Attic')),
      );
    });

    test('an empty list stays empty', () {
      expect(arrangeLocations(const []), isEmpty);
    });
  });
}
