import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/features/common/plate_clear.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isOfflinePlateClearRefusal', () {
    test('the pre-#2864 server insisting on reaching the printer', () {
      expect(isOfflinePlateClearRefusal('Printer not connected'), isTrue);
    });

    test('the current server saying no gate is up is a different answer', () {
      // Same status, opposite meaning: nothing to acknowledge on this printer.
      expect(
        isOfflinePlateClearRefusal(
          'Printer is not awaiting plate-clear acknowledgment (state=IDLE)',
        ),
        isFalse,
      );
    });

    test('a failure the server put no words on is not read as the refusal', () {
      // What the mapper produces when the body carries no `detail` — and what
      // the watch's relay hands over from a phone too old to forward one.
      expect(isOfflinePlateClearRefusal(null), isFalse);
    });

    test('a missing permission is not the refusal', () {
      expect(
        isOfflinePlateClearRefusal(
          "API key does not have 'printers:clear_plate' permission",
        ),
        isFalse,
      );
    });
  });

  group('plateClearPending', () {
    const dirty = PrinterStatus(
      id: 1,
      connected: true,
      awaitingPlateClear: true,
    );

    test('both halves have to agree', () {
      expect(plateClearPending(dirty, gateEnabled: () => true), isTrue);
      // The scheduler does not gate on the plate → nothing to acknowledge.
      expect(plateClearPending(dirty, gateEnabled: () => false), isFalse);
    });

    test('a plate nobody flagged, and a printer with no status at all', () {
      expect(
        plateClearPending(
          const PrinterStatus(id: 1, connected: true),
          gateEnabled: () => true,
        ),
        isFalse,
      );
      // An older server omits the field entirely; unknown is not "waiting".
      expect(plateClearPending(null, gateEnabled: () => true), isFalse);
    });

    test('the server setting is not reached for a plate nobody flagged', () {
      // Why it is a callback: on the phone card it is a `ref.watch` of the
      // server settings, and a card whose plate is clean must not subscribe
      // every printer on the dashboard to that fetch.
      var reads = 0;
      plateClearPending(
        const PrinterStatus(id: 1, connected: true),
        gateEnabled: () {
          reads++;
          return true;
        },
      );
      expect(reads, 0);
    });
  });
}
