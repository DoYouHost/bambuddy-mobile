import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Letter spacing comes from a role, never from a screen's own `copyWith`.
///
/// Typography drifted until the same small heading was bold and wide on one
/// screen, light and tight on the next, and in the accent colour on a third.
/// Each look now has one owner: `SectionLabel` for a heading, the theme's
/// `caption` and `pillText` for the rest. A screen that wants another look
/// changes the owner, so every screen follows.
///
/// A match is any use of the `label` or `caps` tracking, so the rule holds
/// however the line is wrapped.
void main() {
  // What may spell the tracking out, and why.
  const owners = {
    'lib/core/theme/dash_theme.dart': 'the roles of the small tracked texts',
    'lib/features/common/section_label.dart': 'the heading role',
    'lib/features/dashboard/dashboard_screen.dart': 'the Bambuddy wordmark',
    'lib/features/dashboard/skip_objects_screen.dart': 'the "ID" badge',
  };

  test('only a role, the wordmark and a badge spell the tracking out', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (owners.containsKey(file.path)) continue;
      if (RegExp(
        r'DashTracking\.(label|caps)',
      ).hasMatch(file.readAsStringSync())) {
        offenders.add(file.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Use SectionLabel for a heading, or t.caption / t.pillText(tone) '
          'for the small text of a tile or a pill. A new role goes into '
          'dash_theme.dart and into this list with a reason.',
    );
  });

  test('every owner still exists, so the list cannot rot', () {
    for (final path in owners.keys) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  });
}
