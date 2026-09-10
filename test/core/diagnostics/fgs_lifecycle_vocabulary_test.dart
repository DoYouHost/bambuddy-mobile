import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The foreground service's lifecycle is one story written from two isolates,
/// and the log has to read as one: `LogSource` names the subsystem rather than
/// the writer, so the UI's half files under `fgs` too, with `ui_` verbs that
/// stay distinct from the service's own (`docs/logging-guide.md`).
///
/// A source scan rather than a widget test: what this guards is the spelling
/// that reaches a bug report, and the failure it catches — a fourth lifecycle
/// record added on the UI side and filed in the generic lane again — never
/// shows up as a broken behaviour, only as a report nobody can search.
void main() {
  final dashboard = File(
    'lib/features/dashboard/dashboard_screen.dart',
  ).readAsStringSync();

  test('the UI files its half of the lifecycle in the service lane', () {
    final start = dashboard.indexOf('void _logBgService(');
    expect(start, isNot(-1), reason: 'the one UI-side writer is gone');

    // A window rather than "up to the first semicolon": an arrow body and a
    // block body end differently, and the first `;` inside a block would cut
    // the search short of the `add(...)` that matters.
    final window = dashboard.substring(
      start,
      (start + 600).clamp(0, dashboard.length),
    );
    final lane = RegExp(r'LogSource\.(\w+)').firstMatch(window);

    expect(lane, isNotNull, reason: '_logBgService writes to no lane at all');
    expect(lane!.group(1), 'fgs');
  });

  test('every UI-side lifecycle verb says the UI acted', () {
    final events = RegExp(
      _logCall,
    ).allMatches(dashboard).map((m) => m.group(1)!).toList();

    expect(events, isNotEmpty);
    for (final event in events) {
      expect(
        event,
        startsWith('ui_'),
        reason:
            '"$event" would collide with the service\'s own verbs — the '
            'service writes `start` for its start-up actually running, which '
            'is a different moment from the UI asking for it',
      );
    }
  });

  test('the retired spelling is gone from the sources', () {
    // Renamed 2026-09-10. Reports filed before that date still carry
    // `bg_service`; nothing written from here may spell it again, or the lane
    // splits back in two. The literal in either quote Dart accepts — the
    // rename is explained in prose where it happened, and that prose has to
    // stay readable.
    final literal = RegExp(_quoted('bg_service'));
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => literal.hasMatch(f.readAsStringSync()))
        .map((f) => f.path)
        .toList();

    expect(offenders, isEmpty);
  });
}

/// A single-quoted or double-quoted Dart string holding exactly [value].
String _quoted(String value) => "'$value'|\"$value\"";

/// A `_logBgService('verb')` call, in either quote.
const _logCall = '_logBgService\\(\\s*[\'"]([^\'"]+)[\'"]';
