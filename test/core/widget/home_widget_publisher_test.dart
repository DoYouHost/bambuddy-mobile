import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/widget/home_widget_publisher.dart';
import 'package:flutter_test/flutter_test.dart';

/// Catalog resolver that gives every HMS code a description → makes it
/// "displayable", so the publisher would treat it as an active error.
String? _describeAll(HmsError e) => 'desc';

/// Resolver for a code that is in no catalog — what the real one returns for the
/// undocumented codes printers emit while perfectly healthy.
String? _describeNone(HmsError e) => null;

void main() {
  group('HomeWidgetPublisher.keyFor', () {
    test('offline with a stale HMS error → status OFFLINE, not ERROR', () {
      // mergedWith carries the old hms_errors along past a disconnect — the widget
      // must not show an error instead of OFFLINE because of it (a physically
      // impossible alarm).
      final statuses = {
        1: const PrinterStatus(
          id: 1,
          name: 'X1C',
          connected: false,
          state: 'IDLE',
          hmsErrors: [HmsError(code: 'A', severity: 2)],
        ),
      };
      final key = HomeWidgetPublisher.keyFor(
        statuses,
        describeHms: _describeAll,
      );
      expect(key.statusKey, 'offline');
    });

    test('online with an HMS error → status ERROR', () {
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
      final key = HomeWidgetPublisher.keyFor(
        statuses,
        describeHms: _describeAll,
      );
      expect(key.statusKey, 'error');
    });

    test(
      'a code with no description does not turn the printer into an error on the home screen',
      () {
        // The X2D report reached the home-screen widget too: an undocumented code
        // with server severity 1 used to flip it to ERROR while the print ran.
        final statuses = {
          1: const PrinterStatus(
            id: 1,
            name: 'X2D',
            connected: true,
            state: 'RUNNING',
            progress: 40,
            hmsErrors: [
              HmsError(code: '0x20070', attr: 83887616, module: 5, severity: 1),
            ],
          ),
        };
        final key = HomeWidgetPublisher.keyFor(
          statuses,
          describeHms: _describeNone,
        );
        expect(key.statusKey, 'printing');
        expect(key.progressPct, 40);
      },
    );
  });
}
