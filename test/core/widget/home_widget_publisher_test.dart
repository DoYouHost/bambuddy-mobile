import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/widget/home_widget_publisher.dart';
import 'package:flutter_test/flutter_test.dart';

/// Catalog resolver that gives every HMS code a description → makes it
/// "displayable", so the publisher would treat it as an active error.
String? _describeAll(HmsError e) => 'desc';

void main() {
  group('HomeWidgetPublisher.keyFor', () {
    test('offline z zaległym błędem HMS → status OFFLINE, nie ERROR', () {
      // mergedWith niesie stary hms_errors dalej po rozłączeniu — widget nie może
      // przez to pokazać błędu zamiast OFFLINE (fizycznie niemożliwy alarm).
      final statuses = {
        1: const PrinterStatus(
          id: 1,
          name: 'X1C',
          connected: false,
          state: 'IDLE',
          hmsErrors: [HmsError(code: 'A', severity: 2)],
        ),
      };
      final key = HomeWidgetPublisher.keyFor(statuses, describeHms: _describeAll);
      expect(key.statusKey, 'offline');
    });

    test('online z błędem HMS → status ERROR', () {
      final statuses = {
        1: const PrinterStatus(
          id: 1,
          name: 'X1C',
          connected: true,
          state: 'RUNNING',
          progress: 40,
          hmsErrors: [HmsError(code: 'A', severity: 2)],
        ),
      };
      final key = HomeWidgetPublisher.keyFor(statuses, describeHms: _describeAll);
      expect(key.statusKey, 'error');
    });
  });
}
