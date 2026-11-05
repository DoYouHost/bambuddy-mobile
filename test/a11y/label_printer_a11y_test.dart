import 'package:bambuddy_mobile/core/demo/demo_label_printer.dart';
import 'package:bambuddy_mobile/core/models/label_printer.dart';
import 'package:bambuddy_mobile/core/network/label_printer_discovery.dart';
import 'package:bambuddy_mobile/features/label_printer/label_printer_providers.dart';
import 'package:bambuddy_mobile/features/label_printer/label_printer_screen.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'a11y_harness.dart';

/// Rendered contrast and touch targets of the label printer screen: nothing
/// chosen, a chosen server in each state it can answer in (ready, printer off,
/// stock it cannot print, unreachable), the search with its three outcomes and
/// an address that is not a label print server. Deliberately not covered: the
/// "checking" spinner, which lasts one request, and the same widget inside the
/// app settings, which `rendered_guidelines_test.dart` already measures.
void main() {
  a11ySurface(
    'label printer, none chosen',
    demo: false,
    home: () => const LabelPrinterScreen(),
    shows: find.text(pl.labelPrinterNotSet),
  );

  for (final (name, info, line) in [
    (
      'ready',
      _info(connected: true, labelId: '62x29'),
      pl.labelPrinterReady('QL-600', '62x29'),
    ),
    (
      'printer off',
      _info(connected: false, labelId: '62x29'),
      pl.labelPrinterPrinterOff,
    ),
    (
      'wrong stock',
      _info(connected: true, labelId: '54x29'),
      pl.labelPrinterReady('QL-600', '54x29'),
    ),
    ('offline', null, pl.labelPrinterOffline),
  ]) {
    a11ySurface(
      'label printer, chosen and $name',
      demo: false,
      overrides: [
        labelPrinterUrlProvider.overrideWith(_SavedUrl.new),
        labelPrinterInfoProvider.overrideWith((ref) async => info),
      ],
      home: () => const LabelPrinterScreen(),
      shows: find.text(line),
    );
  }

  // The demo's own search: its printer turns up a moment in.
  a11ySurface(
    'label printer, search found a server',
    overrides: [],
    home: () => const LabelPrinterScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('label_printer.search'));
      await a11ySettle(tester, const Duration(seconds: 3));
    },
    shows: find.text(demoLabelPrinter.name),
  );

  a11ySurface(
    'label printer, search found nothing',
    demo: false,
    overrides: [_discovery(() => Stream.value(const []))],
    home: () => const LabelPrinterScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('label_printer.search'));
    },
    shows: find.text(pl.labelPrinterNoneFound),
  );

  a11ySurface(
    'label printer, search failed',
    demo: false,
    overrides: [_discovery(() => Stream.error(Exception('no multicast')))],
    home: () => const LabelPrinterScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('label_printer.search'));
    },
    shows: find.text(pl.labelPrinterDiscoveryFailed),
  );

  a11ySurface(
    'label printer, address that is not a server',
    demo: false,
    home: () => const LabelPrinterScreen(),
    arrange: (tester) async {
      await tester.enterText(byLogId('label_printer.address'), '10.0.0.9');
      await tester.tap(byLogId('label_printer.save'));
      await a11ySettle(tester, const Duration(seconds: 2));
    },
    shows: find.text(pl.labelPrinterNotAServer),
  );
}

LabelPrinterInfo _info({required bool connected, required String labelId}) =>
    LabelPrinterInfo(
      model: 'QL-600',
      connected: connected,
      labelId: labelId,
      maxCopies: 50,
    );

/// A saved address, without the preferences the real notifier reads it from.
class _SavedUrl extends LabelPrinterUrlNotifier {
  @override
  String? build() => 'http://10.0.0.5:8000';
}

Override _discovery(Stream<List<DiscoveredLabelPrinter>> Function() search) =>
    labelPrinterDiscoveryProvider.overrideWithValue(search);
