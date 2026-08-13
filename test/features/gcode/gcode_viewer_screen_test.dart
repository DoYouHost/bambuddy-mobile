import 'package:bambuddy_mobile/features/gcode/gcode_viewer_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('raport gotowości i braku adaptera', () {
    expect(parseGcodeViewerReport('ready'), GcodeViewerReport.ready);
    expect(parseGcodeViewerReport('no-adapter'), GcodeViewerReport.noAdapter);
    expect(parseGcodeViewerReport('error'), GcodeViewerReport.scriptError);
  });

  test('białe znaki wokół wiadomości nie zmieniają werdyktu', () {
    // The channel carries whatever the page posted; a stray newline must not
    // turn a verdict into silence.
    expect(parseGcodeViewerReport(' ready\n'), GcodeViewerReport.ready);
  });

  test('nieznana wiadomość nie daje werdyktu', () {
    // Anything else is ignored on purpose: the report decides between showing
    // the viewer and showing an error, and guessing either way is worse than
    // waiting for the timeout that simply reveals the page.
    for (final message in ['', 'ok', 'READY', 'no_adapter', '{"evt":"ready"}']) {
      expect(parseGcodeViewerReport(message), isNull, reason: message);
    }
  });
}
