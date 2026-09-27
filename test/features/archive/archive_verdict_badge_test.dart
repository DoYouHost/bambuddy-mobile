import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/features/archive/archive_screen.dart';
import 'package:bambuddy_mobile/features/archive/print_outcome.dart';
import 'package:bambuddy_mobile/l10n/app_localizations_pl.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

late SharedPreferences _prefs;
final _l10n = AppLocalizationsPl();

Widget _screen(List<Archive> items, {bool supported = true}) => ProviderScope(
  overrides: [
    archiveListOverride(items),
    sharedPreferencesProvider.overrideWithValue(_prefs),
    noServerProfileOverride,
    printOutcomeSupportedProvider.overrideWithValue(AsyncData(supported)),
  ],
  child: plApp(const ArchiveScreen()),
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  testWidgets('each card says where its print stands', (tester) async {
    await tester.pumpWidget(
      _screen([
        testArchive(id: 1, printName: 'Asked', confirmRequested: true),
        testArchive(
          id: 2,
          printName: 'Kept',
          confirmRequested: true,
          userVerdict: PrintVerdict.good,
        ),
        testArchive(
          id: 3,
          printName: 'Binned',
          userVerdict: PrintVerdict.reject,
        ),
        testArchive(id: 4, printName: 'Never asked'),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text(_l10n.outcomeAwaiting), findsOneWidget);
    expect(find.text(_l10n.outcomeGoodPart), findsOneWidget);
    expect(find.text(_l10n.outcomeRejected), findsOneWidget);
  });

  testWidgets('the sheet names the verdict and how it was recorded', (
    tester,
  ) async {
    await tester.pumpWidget(
      _screen([
        testArchive(
          confirmRequested: true,
          userVerdict: PrintVerdict.good,
          userVerdictSource: 'plate_clear',
        ),
      ]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Benchy'));
    await tester.pumpAndSettle();

    expect(find.text(_l10n.outcomeSourcePlateClear), findsOneWidget);
  });

  testWidgets('a server without verdicts has no line for one', (tester) async {
    await tester.pumpWidget(_screen([testArchive()], supported: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Benchy'));
    await tester.pumpAndSettle();

    expect(find.text(_l10n.outcomeNotRecorded), findsNothing);
  });

  testWidgets('the filter is only offered where verdicts exist', (
    tester,
  ) async {
    await tester.pumpWidget(_screen([testArchive()], supported: false));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(_l10n.archiveFilters));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(FilterChip, _l10n.outcomeAwaiting),
      findsNothing,
    );
  });
}
