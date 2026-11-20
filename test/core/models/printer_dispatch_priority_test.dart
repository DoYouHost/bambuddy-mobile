import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_create.dart';
import 'package:flutter_test/flutter_test.dart';

/// `dispatch_priority` (server #2915, 1.3.2): an older server answers no key and
/// drops the field on a `PATCH`, so the key's presence is the only thing that
/// may switch the editor's field on and the write on.
void main() {
  Printer printer(Map<String, dynamic> extra) =>
      Printer.fromJson({'id': 1, 'name': 'X1C', ...extra});

  PrinterUpdate update({int? priority, bool send = true}) => PrinterUpdate(
    name: 'X1',
    ipAddress: '10.0.0.2',
    autoArchive: true,
    isActive: true,
    location: null,
    dispatchPriority: priority,
    served: send ? {PrinterKey.dispatchPriority} : const {},
  );

  group('Printer.servesDispatchPriority', () {
    test('a null priority still says the server knows the field', () {
      final p = printer({'dispatch_priority': null});

      expect(p.servesDispatchPriority, isTrue);
      expect(p.dispatchPriority, isNull);
    });

    test('a stored priority is read', () {
      final p = printer({'dispatch_priority': 3});

      expect(p.servesDispatchPriority, isTrue);
      expect(p.dispatchPriority, 3);
    });

    test('an older server sends no key at all', () {
      final p = printer(const {});

      expect(p.servesDispatchPriority, isFalse);
      expect(p.dispatchPriority, isNull);
    });
  });

  group('Printer.servedKeys', () {
    test('carries every key of the row, nulls included, and no other', () {
      final p = printer({'dispatch_priority': null, 'wear_cost_per_hour': 1.5});

      expect(p.servedKeys, {
        'id',
        'name',
        'dispatch_priority',
        'wear_cost_per_hour',
      });
      expect(p.servesWearCost, isTrue);
      expect(p.servesDispatchPriority, isTrue);
    });

    test('a printer built by hand serves nothing', () {
      const p = Printer(id: 1, name: 'X1C');

      expect(p.servesWearCost, isFalse);
      expect(p.servesDispatchPriority, isFalse);
    });
  });

  group('PrinterUpdate.dispatch_priority', () {
    test('a server that does not know it is not sent one', () {
      final json = update(priority: 3, send: false).toJson();

      expect(json.containsKey('dispatch_priority'), isFalse);
    });

    test('serving one field does not send the other', () {
      final json = update(priority: 3).toJson();

      expect(json.containsKey('wear_cost_per_hour'), isFalse);
      expect(json['dispatch_priority'], 3);
    });

    test('every served key is sent, so an omitted value clears its field', () {
      const both = {PrinterKey.wearCostPerHour, PrinterKey.dispatchPriority};
      final json = PrinterUpdate(
        name: 'X1',
        ipAddress: '10.0.0.2',
        autoArchive: true,
        isActive: true,
        location: null,
        dispatchPriority: 3,
        served: both,
      ).toJson();

      // The caller gave no wear rate, and the server is told "none".
      expect(json.containsKey('wear_cost_per_hour'), isTrue);
      expect(json['wear_cost_per_hour'], isNull);
    });

    test('a number is sent as it is, zero included', () {
      expect(update(priority: 3).toJson()['dispatch_priority'], 3);
      expect(update(priority: 0).toJson()['dispatch_priority'], 0);
    });

    test('empty is sent as null, which clears it', () {
      final json = update().toJson();

      expect(json.containsKey('dispatch_priority'), isTrue);
      expect(json['dispatch_priority'], isNull);
    });

    test('the server\'s ceiling is not exceeded, never sent to a 422', () {
      expect(
        update(priority: 100001).toJson()['dispatch_priority'],
        PrinterUpdate.maxDispatchPriority,
      );
      expect(PrinterUpdate.maxDispatchPriority, 100000);
      expect(update(priority: -5).toJson()['dispatch_priority'], 0);
    });
  });
}
