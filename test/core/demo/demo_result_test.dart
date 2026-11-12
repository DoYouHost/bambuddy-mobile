import 'package:bambuddy_mobile/core/demo/demo_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('demoOk', () {
    test('answers 200 with the body unchanged', () {
      final body = {'a': 1};
      final result = demoOk(body);
      expect(result.status, 200);
      expect(result.body, same(body));
    });

    test('accepts a null body', () {
      final result = demoOk(null);
      expect(result.status, 200);
      expect(result.body, isNull);
    });
  });

  group('demoNotFound', () {
    test('answers 404 with the FastAPI detail body', () {
      final result = demoNotFound();
      expect(result.status, 404);
      expect(result.body, {'detail': 'Not Found'});
    });
  });

  group('demoRefuse', () {
    test('answers the given status with the detail string', () {
      final result = demoRefuse(422, 'unknown dpi');
      expect(result.status, 422);
      expect(result.body, {'detail': 'unknown dpi'});
    });

    test('keeps an empty detail as an empty string', () {
      final result = demoRefuse(400, '');
      expect(result.status, 400);
      expect(result.body, {'detail': ''});
    });
  });

  group('rowById', () {
    final rows = <Map<String, dynamic>>[
      {'id': 1, 'name': 'first'},
      {'id': 2, 'name': 'second'},
    ];

    test('returns the row with the matching id', () {
      expect(rowById(rows, 2)?['name'], 'second');
    });

    test('returns null when no row has the id', () {
      expect(rowById(rows, 9), isNull);
    });

    test('returns null for an empty list', () {
      expect(rowById(const [], 1), isNull);
    });

    test('does not match an id of another type', () {
      expect(rowById(rows, '2'), isNull);
    });

    test('compares a null id with == like the expression it replaced', () {
      expect(
        rowById([
          {'id': null, 'name': 'orphan'},
        ], null),
        isNotNull,
      );
      expect(rowById(rows, null), isNull);
    });
  });

  group('isoUtc', () {
    test('writes a UTC instant with a Z suffix', () {
      expect(
        isoUtc(DateTime.utc(2026, 3, 4, 5, 6, 7)),
        '2026-03-04T05:06:07.000Z',
      );
    });

    test('converts a local time to the same UTC instant', () {
      final utc = DateTime.utc(2026, 3, 4, 5, 6, 7);
      expect(isoUtc(utc.toLocal()), '2026-03-04T05:06:07.000Z');
    });
  });

  group('intQuery', () {
    test('returns the fallback when the key is missing', () {
      expect(intQuery({}, 'limit', 50), 50);
    });

    test('returns the fallback for an empty or non-numeric value', () {
      expect(intQuery({'limit': ''}, 'limit', 50), 50);
      expect(intQuery({'limit': 'abc'}, 'limit', 50), 50);
    });

    test('returns a negative value as parsed', () {
      expect(intQuery({'offset': '-5'}, 'offset', 0), -5);
    });

    test('returns the parsed value when present', () {
      expect(intQuery({'limit': '7'}, 'limit', 50), 7);
    });
  });
}
