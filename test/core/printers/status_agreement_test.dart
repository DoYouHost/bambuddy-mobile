import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/notifications/hms_catalog.dart';
import 'package:bambuddy_mobile/core/printers/printer_bucket.dart';
import 'package:bambuddy_mobile/core/widget/widget_status.dart';
import 'package:bambuddy_mobile/wear/wear_status.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// A code the catalogue names ("Filament ran out"), so it counts as a fault.
const _fault = HmsError(
  code: '0x8004',
  attr: 0x03008004,
  module: 3,
  severity: 3,
  fullCode: '03008004',
);

PrinterStatus _status({
  String? state,
  bool? connected = true,
  double? progress,
  List<HmsError>? hms,
}) => PrinterStatus(
  id: 1,
  connected: connected,
  state: state,
  progress: progress,
  hmsErrors: hms,
);

/// Every surface that names a printer's state reads one classification, the
/// web's `classifyPrinterStatus`. The cases are the ones the three copies used to
/// answer differently.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await HmsCatalog.instance.load(const Locale('en'));
    expect(
      HmsCatalog.instance.describe(_fault),
      isNotNull,
      reason: 'catalog asset did not load — the rest is vacuous',
    );
  });

  final cases = <String, PrinterStatus?>{
    'no frame at all': null,
    'connectivity not reported': _status(state: 'RUNNING', connected: null),
    'disconnected': _status(state: 'RUNNING', connected: false),
    'running': _status(state: 'RUNNING'),
    'paused': _status(state: 'PAUSE'),
    'finished': _status(state: 'FINISH'),
    'failed without a fault': _status(state: 'FAILED'),
    'preparing': _status(state: 'PREPARE'),
    'idle': _status(state: 'IDLE'),
    'running with a fault': _status(state: 'RUNNING', hms: const [_fault]),
    'idle with a fault': _status(state: 'IDLE', hms: const [_fault]),
  };

  for (final entry in cases.entries) {
    test('the widget and the watch word "${entry.key}" as the filter does', () {
      final bucket = classifyPrinter(
        entry.value,
        describe: HmsCatalog.instance.describe,
      );
      if (entry.value != null) {
        expect(
          WidgetStatus.keyFor(
            entry.value!,
            describe: HmsCatalog.instance.describe,
          ),
          bucket.name,
        );
      }
      expect(wearStateOf(entry.value).name, bucket.name);
    });
  }

  test('connectivity not reported is offline, on the watch too', () {
    expect(
      wearStateOf(_status(state: 'RUNNING', connected: null)),
      WearState.offline,
    );
  });

  test('a failed job is finished, never a state of its own', () {
    expect(
      WidgetStatus.keyFor(
        _status(state: 'FAILED'),
        describe: HmsCatalog.instance.describe,
      ),
      'finished',
    );
    expect(wearStateOf(_status(state: 'FAILED')), WearState.finished);
  });

  test('a fault is the error bucket and still leaves a job to act on', () {
    final s = _status(state: 'RUNNING', hms: const [_fault]);
    expect(
      WidgetStatus.keyFor(s, describe: HmsCatalog.instance.describe),
      'error',
    );
    expect(wearStateOf(s), WearState.error);
    expect(s.isJobActive, isTrue);
    expect(WidgetStatus.isActive(s), isTrue);
  });

  test('the catalogue handed in decides, never the one of this isolate', () {
    // `_fault` has no sentence of its own: only a catalogue can name it. The
    // test isolate has one loaded, and a background isolate may not.
    final s = _status(state: 'RUNNING', hms: const [_fault]);
    expect(WidgetStatus.keyFor(s, describe: null), 'printing');
    expect(
      WidgetStatus.keyFor(s, describe: HmsCatalog.instance.describe),
      'error',
    );
  });

  test('a preparing printer is idle by bucket and active by job', () {
    final s = _status(state: 'PREPARE');
    expect(wearStateOf(s), WearState.idle);
    expect(s.isJobActive, isTrue);
  });

  test('an unreachable printer has no job whatever it last said', () {
    expect(_status(state: 'RUNNING', connected: false).isJobActive, isFalse);
    expect(_status(state: 'RUNNING', connected: null).isJobActive, isFalse);
  });

  group('progressPercent', () {
    test('is a percentage, never a fraction', () {
      expect(_status(progress: 0.5).progressPercent, 1);
      expect(_status(progress: 1).progressPercent, 1);
      expect(_status(progress: 42.4).progressPercent, 42);
      expect(_status(progress: 42.5).progressPercent, 43);
    });

    test('stays inside 0 to 100', () {
      expect(_status(progress: null).progressPercent, 0);
      expect(_status(progress: -3).progressPercent, 0);
      expect(_status(progress: 100).progressPercent, 100);
      expect(_status(progress: 140).progressPercent, 100);
    });
  });
}
