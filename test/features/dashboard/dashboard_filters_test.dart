import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/notifications/hms_catalog.dart';
import 'package:bambuddy_mobile/core/printers/printer_bucket.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The `error` bucket drives the dashboard filter and its count badge, so a code
/// the app cannot name must not push a printer into it — that badge was the
/// second half of the "app reports a fatal mainboard issue" report.
///
/// Codes are real. `0300_8004` is a print error the catalog names ("Filament
/// ran out") — the class of fault the card exists for. `0x20070` @ `0x05000600`
/// is an `hms[]` component-diagnostics code the catalog deliberately does not
/// carry; it was captured from a live printer that was printing perfectly.
const _uncataloged = HmsError(
  code: '0x20070',
  attr: 83887616,
  module: 5,
  severity: 1,
);
const _catalogued = HmsError(
  code: '0x8004',
  attr: 0x03008004,
  module: 3,
  severity: 3,
  fullCode: '03008004',
);

PrinterStatus _status({
  String? state,
  bool connected = true,
  List<HmsError>? hms,
}) => PrinterStatus(id: 1, connected: connected, state: state, hmsErrors: hms);

PrinterStatusBucket _classify(PrinterStatus? s) =>
    classifyPrinter(s, describe: HmsCatalog.instance.describe);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await HmsCatalog.instance.load(const Locale('en'));
    expect(
      HmsCatalog.instance.describe(_catalogued),
      isNotNull,
      reason: 'catalog asset did not load — the rest is vacuous',
    );
    expect(HmsCatalog.instance.describe(_uncataloged), isNull);
  });

  group('classifyPrinter', () {
    test('an uncataloged code leaves the print state alone', () {
      expect(
        _classify(_status(state: 'RUNNING', hms: const [_uncataloged])),
        PrinterStatusBucket.printing,
      );
      expect(
        _classify(_status(state: 'IDLE', hms: const [_uncataloged])),
        PrinterStatusBucket.idle,
      );
      expect(
        _classify(_status(state: 'PAUSE', hms: const [_uncataloged])),
        PrinterStatusBucket.paused,
      );
    });

    test('a catalogued code outranks the print state', () {
      expect(
        _classify(_status(state: 'RUNNING', hms: const [_catalogued])),
        PrinterStatusBucket.error,
      );
      expect(
        _classify(_status(state: 'IDLE', hms: const [_catalogued])),
        PrinterStatusBucket.error,
      );
    });

    test('one nameable code among noise is still an error', () {
      expect(
        _classify(
          _status(state: 'RUNNING', hms: const [_uncataloged, _catalogued]),
        ),
        PrinterStatusBucket.error,
      );
    });

    test('FAILED with no HMS is finished, as on the web — a cancelled print '
        'is not a fault', () {
      expect(_classify(_status(state: 'FAILED')), PrinterStatusBucket.finished);
    });

    test('FAILED with a displayable HMS error is an error', () {
      expect(
        _classify(_status(state: 'FAILED', hms: const [_catalogued])),
        PrinterStatusBucket.error,
      );
    });

    test('a preparing printer is idle, as on the web', () {
      expect(_classify(_status(state: 'PREPARE')), PrinterStatusBucket.idle);
    });

    test('offline outranks any carried-forward code', () {
      // mergedWith keeps hms_errors across a disconnect on purpose; the bucket
      // must still read OFFLINE rather than blame a printer that isn't there.
      expect(
        _classify(
          _status(state: 'RUNNING', connected: false, hms: const [_catalogued]),
        ),
        PrinterStatusBucket.offline,
      );
      expect(_classify(null), PrinterStatusBucket.offline);
    });

    test('an empty or absent error list is not an error', () {
      expect(
        _classify(_status(state: 'IDLE', hms: const [])),
        PrinterStatusBucket.idle,
      );
      expect(_classify(_status(state: 'IDLE')), PrinterStatusBucket.idle);
    });
  });
}
