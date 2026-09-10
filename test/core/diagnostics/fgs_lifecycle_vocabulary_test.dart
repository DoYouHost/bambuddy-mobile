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
    // The helper's body, whatever `dart format` does to its line breaks.
    final start = dashboard.indexOf('void _logBgService(');
    expect(start, isNot(-1), reason: 'the one UI-side writer is gone');
    final body = dashboard.substring(start, dashboard.indexOf(';', start));

    expect(body, contains('LogSource.fgs'));
    expect(
      body,
      isNot(contains('LogSource.app')),
      reason: 'the generic lane is what split this story in two',
    );
  });

  test('every UI-side lifecycle verb says the UI acted', () {
    final events = RegExp(
      r"_logBgService\('([^']+)'",
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
    // splits back in two. The literal, not the word — the rename is explained
    // in prose where it happened, and that prose is the point.
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains("'bg_service'"))
        .map((f) => f.path)
        .toList();

    expect(offenders, isEmpty);
  });
}
