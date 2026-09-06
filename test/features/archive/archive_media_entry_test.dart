import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/models/no_3mf_warning.dart';
import 'package:bambuddy_mobile/features/archive/archive_media_sheet.dart';
import 'package:bambuddy_mobile/features/archive/archive_providers.dart';
import 'package:bambuddy_mobile/features/archive/archive_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// The one media entry on the archive detail sheet — it replaced the separate
/// timelapse and photos buttons. It stands for three things at once, so it is
/// present whenever any of them is, and only absent when none is: no attached
/// video, no photos, and no printer this server can be asked about.

late SharedPreferences _prefs;

Widget _screen(Archive archive, {required bool supported}) => ProviderScope(
  overrides: [
    archiveListOverride([archive]),
    no3mfWarningProvider.overrideWith((ref) async => No3mfWarning.none),
    sharedPreferencesProvider.overrideWithValue(_prefs),
    noServerProfileOverride,
    archiveMediaSupportedProvider.overrideWith((ref) async => supported),
  ],
  child: plApp(const ArchiveScreen()),
);

Archive _archive({
  int? printerId,
  String? timelapsePath,
  List<String> photos = const [],
}) => Archive(
  id: 1,
  filename: 'benchy.gcode.3mf',
  status: 'completed',
  printName: 'Benchy',
  printerId: printerId,
  timelapsePath: timelapsePath,
  photos: photos,
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(ArchiveScreen)));

  Future<void> openSheet(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(screen);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Benchy').first);
    await tester.pumpAndSettle();
  }

  testWidgets('one entry in place of the two viewers it now holds', (
    tester,
  ) async {
    await openSheet(
      tester,
      _screen(
        _archive(
          printerId: 2,
          timelapsePath: 'archive/1/v.mp4',
          photos: const ['a.jpg'],
        ),
        supported: true,
      ),
    );

    final t = l10n(tester);
    expect(find.text(t.archiveMediaAction), findsOneWidget);
    // The buttons this one replaced are gone from the archive sheet — both now
    // live inside it, under "on the server".
    expect(find.text(t.archiveTimelapse), findsNothing);
    expect(find.text(t.archivePhotos(1)), findsNothing);
  });

  testWidgets('offered for a print whose only media is still on the printer', (
    tester,
  ) async {
    await openSheet(tester, _screen(_archive(printerId: 2), supported: true));

    expect(find.text(l10n(tester).archiveMediaAction), findsOneWidget);
  });

  testWidgets('absent when the printer is all there was and cannot be asked', (
    tester,
  ) async {
    // An older server has no search route, so a print with no attached video
    // and no photos has nothing the sheet could show.
    await openSheet(tester, _screen(_archive(printerId: 2), supported: false));

    expect(find.text(l10n(tester).archiveMediaAction), findsNothing);
  });

  testWidgets('still offered on an older server when the archive has media', (
    tester,
  ) async {
    // The timelapse and the photos are the archive's own — the sheet is the way
    // to them whatever the server version.
    await openSheet(
      tester,
      _screen(_archive(timelapsePath: 'archive/1/v.mp4'), supported: false),
    );

    expect(find.text(l10n(tester).archiveMediaAction), findsOneWidget);
  });

  testWidgets('absent for a print with nothing anywhere', (tester) async {
    await openSheet(tester, _screen(_archive(), supported: true));

    expect(find.text(l10n(tester).archiveMediaAction), findsNothing);
  });
}
