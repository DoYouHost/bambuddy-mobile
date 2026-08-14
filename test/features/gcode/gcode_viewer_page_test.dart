import 'dart:convert';

import 'package:bambuddy_mobile/features/gcode/gcode_viewer_page.dart';
import 'package:flutter_test/flutter_test.dart';

GcodeViewerConfig _config({
  String url = '/api/v1/library/files/7/gcode',
  Map<String, String> headers = const {'X-API-Key': 'bb_secret'},
  Map<String, String> labels = const {'loading': 'Loading'},
}) =>
    GcodeViewerConfig(
      gcodeUrl: url,
      headers: headers,
      dark: true,
      labels: labels,
      featureLabels: const {1: 'Walls', 2: 'Sparse infill'},
    );

/// The `window.__BB = {...};` object the shell was given, decoded back.
Map<String, Object?> _configFrom(String document) {
  final match =
      RegExp(r'window\.__BB = (\{.*?\});', dotAll: true).firstMatch(document);
  expect(match, isNotNull, reason: 'config was not injected');
  return jsonDecode(match!.group(1)!) as Map<String, Object?>;
}

void main() {
  group('document', () {
    test('both placeholders are replaced', () {
      final document = buildViewerDocument(
        shell: '<html><script>__BB_CONFIG__</script>'
            '<script>__BB_BUNDLE__</script></html>',
        bundle: 'console.log(1);',
        config: _config(),
      );

      expect(document, isNot(contains('__BB_CONFIG__')));
      expect(document, isNot(contains('__BB_BUNDLE__')));
      expect(document, contains('console.log(1);'));
    });

    test('the font faces land in their own block', () {
      final document = buildViewerDocument(
        shell: '<style>__BB_FONTS__</style><script>__BB_CONFIG__</script>'
            '<script>__BB_BUNDLE__</script>',
        bundle: '',
        fonts: '@font-face { font-family: Manrope; src: url(data:font/woff2;'
            'base64,AAAA) format("woff2"); }',
        config: _config(),
      );

      expect(document, isNot(contains('__BB_FONTS__')));
      expect(document, contains('font-family: Manrope'));
      // Inside <style>, not <script>: a face in the wrong block is silently
      // dead, and the page then renders in the system face with no error.
      expect(
        RegExp(r'<style>@font-face').hasMatch(document),
        isTrue,
        reason: 'faces must open the style block',
      );
    });

    test('a document without fonts keeps no placeholder', () {
      // The faces are optional to compose with — a test or a tool may leave
      // them out — but the marker must never survive into the page.
      final document = buildViewerDocument(
        shell: '<style>__BB_FONTS__</style>__BB_CONFIG__ __BB_BUNDLE__',
        bundle: '',
        config: _config(),
      );

      expect(document, isNot(contains('__BB_FONTS__')));
    });

    test('a bundle full of dollars and backslashes survives verbatim', () {
      // Minified three.js is full of both, and a replacement that treated them
      // as syntax would corrupt the renderer in ways nothing here would catch.
      const bundle = r'var a=`$x`,b="A$1";';
      final document = buildViewerDocument(
        shell: '<script>__BB_CONFIG__</script><script>__BB_BUNDLE__</script>',
        bundle: bundle,
        config: _config(),
      );

      expect(document, contains(bundle));
    });

    test('the config carries the url, the headers and the labels', () {
      final document = buildViewerDocument(
        shell: '<script>__BB_CONFIG__</script>__BB_BUNDLE__',
        bundle: '',
        config: _config(),
      );
      final config = _configFrom(document);

      expect(config['gcodeUrl'], '/api/v1/library/files/7/gcode');
      expect(config['headers'], {'X-API-Key': 'bb_secret'});
      expect(config['dark'], isTrue);
      final labels = config['labels']! as Map<String, Object?>;
      expect(labels['loading'], 'Loading');
      // Legend labels are keyed by toolpath type, and JSON has no int keys.
      expect(labels['features'], {'1': 'Walls', '2': 'Sparse infill'});
    });

    test('filament colours and slot names ride along', () {
      final document = buildViewerDocument(
        shell: '<script>__BB_CONFIG__</script>__BB_BUNDLE__',
        bundle: '',
        config: GcodeViewerConfig(
          gcodeUrl: '/api/v1/archives/3/gcode',
          headers: const {},
          dark: true,
          labels: const {},
          featureLabels: const {},
          filamentLabels: const {0: 'Filament 1', 1: 'Filament 2'},
          filamentColors: const ['#FF0000', null],
        ),
      );
      final config = _configFrom(document);

      // A slot the file records no colour for stays null rather than
      // collapsing the list: the page indexes it by tool number.
      expect(config['filamentColors'], ['#FF0000', null]);
      expect((config['labels']! as Map<String, Object?>)['filaments'],
          {'0': 'Filament 1', '1': 'Filament 2'});
    });

    test('a label cannot close the script element', () {
      // The config is inlined into <script>, so a "</script>" anywhere in a
      // translated string would end it early and spill the rest as page text.
      final document = buildViewerDocument(
        shell: '<script>__BB_CONFIG__</script>__BB_BUNDLE__',
        bundle: '',
        config: _config(labels: const {'loading': '</script><b>x'}),
      );

      expect(document, isNot(contains('</script><b>x')));
      expect(_configFrom(document), isNotNull);
    });
  });

  group('report', () {
    test('ready', () {
      expect(parseGcodeViewerReport('ready'), const GcodeViewerReport.ready());
      expect(parseGcodeViewerReport(' ready\n'),
          const GcodeViewerReport.ready());
    });

    test('loading is alive but not ready', () {
      // What takes the app's spinner down without claiming a preview exists —
      // and, unlike the other two, must leave the watchdog running.
      const report = GcodeViewerReport.alive();
      expect(parseGcodeViewerReport('loading'), report);
      expect(report.alive, isTrue);
      expect(report.ready, isFalse);
      expect(report.error, isNull);
    });

    test('each failure the page can name', () {
      expect(
        parseGcodeViewerReport('error:network'),
        const GcodeViewerReport.failed(GcodeViewerError.network),
      );
      expect(
        parseGcodeViewerReport('error:empty'),
        const GcodeViewerReport.failed(GcodeViewerError.empty),
      );
      expect(
        parseGcodeViewerReport('error:script'),
        const GcodeViewerReport.failed(GcodeViewerError.script),
      );
    });

    test('an http failure carries its status', () {
      expect(
        parseGcodeViewerReport('error:http:401'),
        const GcodeViewerReport.failed(GcodeViewerError.http, status: 401),
      );
      // A status that is not a number still says the server refused; losing the
      // whole verdict over it would put the screen back on a blank page.
      expect(
        parseGcodeViewerReport('error:http:nope'),
        const GcodeViewerReport.failed(GcodeViewerError.http),
      );
    });

    test('anything outside the protocol yields no verdict', () {
      // Ignored on purpose: the report decides between the preview and an
      // error, and guessing either way is worse than waiting for the timeout.
      for (final message in [
        '',
        'ok',
        'READY',
        'ready:1',
        'error',
        'error:teapot',
        'error:network:extra',
        '{"evt":"ready"}',
      ]) {
        expect(parseGcodeViewerReport(message), isNull, reason: message);
      }
    });
  });
}
