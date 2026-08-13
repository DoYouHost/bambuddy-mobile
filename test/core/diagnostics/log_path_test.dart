import 'dart:io';

import 'package:bambuddy_mobile/core/diagnostics/log_path.dart';
import 'package:flutter_test/flutter_test.dart';

/// The last thing between a filename the user chose and a public GitHub issue.
///
/// `/projects/{id}/attachments/{filename}` is the one route that interpolates
/// the user's own text into a path, and a path is recorded for every request
/// the app makes. The redactor cannot help: it works on field names and value
/// shapes, and nothing separates `faktura-jan-kowalski.pdf` from a route.
void main() {
  /// Through `Uri` first, the way both call sites reach it: that is what drops
  /// the host and the query before a segment is ever looked at.
  String reduce(String url) => loggablePath(Uri.parse(url).path);

  group('what must not survive', () {
    test('an attachment filename is masked, the route around it is not', () {
      expect(
        reduce('http://s.lan:8080/api/v1/projects/3/attachments/'
            'faktura-jan-kowalski-2026.pdf'),
        '/api/v1/projects/3/attachments/<seg>',
      );
    });

    test('masking does not depend on the extension being a known one', () {
      for (final name in ['cv.pdf', 'Zdjęcia.zip', 'plan B.3mf', 'ŻÓŁW.stl']) {
        expect(
          reduce('http://s.lan/api/v1/projects/3/attachments/$name'),
          endsWith('/<seg>'),
          reason: name,
        );
      }
    });

    test('the host and the query go with it', () {
      // Camera and thumbnail tokens live in the query, the user's network in
      // the host.
      expect(
        reduce('http://192.168.1.50:8080/api/v1/printers/1/camera?token=abc'),
        '/api/v1/printers/1/camera',
      );
    });
  });

  group('what must survive, or the log stops being readable', () {
    test('the routes the app actually calls are untouched', () {
      const routes = [
        '/api/v1/printers/',
        '/api/v1/printers/1/print/pause',
        '/api/v1/queue/12/start',
        '/api/v1/smart-plugs/4/control',
        '/api/v1/printers/camera/stream-token',
        '/api/v1/api-keys/7',
        '/api/v1/projects/3/add-archives',
        '/api/v1/maintenance/overview',
        '/api/v1/users/slim',
      ];
      for (final route in routes) {
        expect(reduce('http://s.lan:8080$route'), route, reason: route);
      }
    });

    test('a segment starting with a digit is a route, not a name', () {
      // `/auth/2fa/verify` would be masked by a letters-only rule, and the 2FA
      // lane is one of the harder things to diagnose from a report.
      expect(reduce('http://s.lan/api/v1/auth/2fa/verify'),
          '/api/v1/auth/2fa/verify');
    });

    test('every route in Endpoints survives the rule', () {
      // The guard on the rule itself: this is what makes it safe to apply to
      // the whole app rather than to one known-bad route. If a future endpoint
      // is written in a style the rule masks, this fails before a report does.
      final source = File('lib/core/api/endpoints.dart').readAsStringSync();
      final code = source
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('///'))
          .join('\n');
      final literals = RegExp(r"'((?:/|\$apiPrefix)[^']*)'").allMatches(code);
      expect(literals, isNotEmpty, reason: 'the scan found no routes');

      for (final match in literals) {
        // Interpolated ids stand in as a number, which is what they always are:
        // every route builder but one takes ints.
        final route = match
            .group(1)!
            .replaceAll(r'$apiPrefix', '/api/v1')
            .replaceAll(RegExp(r'\$\{?[\w.]+\}?'), '7');
        expect(
          reduce('http://s.lan:8080$route'),
          route,
          reason: 'masked a real route: $route',
        );
      }
    });
  });

  test('an empty or odd path does not throw', () {
    // A recorder must not be able to cause the failure it exists to describe.
    expect(reduce('http://s.lan'), '');
    expect(reduce('http://s.lan/'), '/');
  });
}
