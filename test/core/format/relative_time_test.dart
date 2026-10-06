import 'package:bambuddy_mobile/core/format/datetime_format.dart';
import 'package:bambuddy_mobile/core/format/relative_time.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// The steps of the web's `formatRelativeTime`: under a minute, minutes,
/// hours, days, and the date itself from a week on.
void main() {
  final now = DateTime(2026, 10, 6, 12);
  final l10n = lookupAppLocalizations(const Locale('en'));

  String at(Duration offset, DateTimeFormats formats) =>
      relativeTime(l10n, formats, now.add(offset), now: now);

  testWidgets('each step names the largest whole unit', (tester) async {
    late DateTimeFormats formats;
    await tester.pumpWidget(
      plApp(
        Builder(
          builder: (context) {
            formats = DateTimeFormats.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(at(const Duration(seconds: -59), formats), l10n.timeJustNow);
    expect(at(const Duration(seconds: 30), formats), l10n.timeNow);
    expect(at(const Duration(minutes: -59), formats), l10n.timeMinutesAgo(59));
    expect(at(const Duration(minutes: 5), formats), l10n.timeInMinutes(5));
    expect(at(const Duration(hours: -23), formats), l10n.timeHoursAgo(23));
    expect(at(const Duration(days: -6), formats), l10n.timeDaysAgo(6));
    expect(at(const Duration(days: 2), formats), l10n.timeInDays(2));
    final weekAgo = now.subtract(const Duration(days: 7));
    expect(at(const Duration(days: -7), formats), formats.dateTime(weekAgo));
    expect(relativeTime(l10n, formats, null, now: now), '-');
  });
}
