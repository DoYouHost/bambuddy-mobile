import 'dart:io';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

/// The guard on `loggablePath` against *this* app's route table.
///
/// The rule itself, and what it does to a filename the user chose, is tested in
/// `app_diagnostics`. What cannot move there is this: the rule is inverted — a
/// segment survives only if it looks like something the server or we named — so
/// it is only safe to apply to every request if no real route is masked by it.
/// If a future endpoint is written in a style the rule masks, this fails before
/// a report does.
void main() {
  /// Through `Uri` first, the way both call sites reach it: that is what drops
  /// the host and the query before a segment is ever looked at.
  String reduce(String url) => loggablePath(Uri.parse(url).path);

  group('what must survive, or the log stops being readable', () {
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
