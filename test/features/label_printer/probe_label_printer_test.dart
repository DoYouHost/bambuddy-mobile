import 'package:bambuddy_mobile/core/demo/demo_label_printer.dart';
import 'package:bambuddy_mobile/features/label_printer/label_printer_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('answers with the identity of the demo label printer', () async {
    expect(await probeLabelPrinter(demoLabelPrinterUrl), isNotNull);
  });

  test('returns null when nothing listens on the address', () async {
    // Port 1 on loopback is closed here, so the connection is refused at once.
    expect(await probeLabelPrinter('http://127.0.0.1:1'), isNull);
  });
}
