import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/features/archive/archive_screen.dart';
import 'package:bambuddy_mobile/features/archive/timelapse_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// Serves the archive list without touching the repository or the network.

Archive _archive({String? timelapsePath}) => Archive(
  id: 42,
  filename: 'print.gcode.3mf',
  status: 'completed',
  printName: 'Wydruk testowy',
  timelapsePath: timelapsePath,
);

Widget _archiveScreen(Archive archive) => ProviderScope(
  overrides: [
    archiveListOverride([archive]),
    sharedPreferencesProvider.overrideWithValue(_prefs),
    noServerProfileOverride,
  ],
  child: plApp(const ArchiveScreen()),
);

/// The archive screen reads one stored flag (the no-3MF nudge's one-shot
/// dismissal), so every test that builds it needs prefs in the scope.
late SharedPreferences _prefs;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  group('Archive.hasTimelapse', () {
    test('null and an empty path both mean there is no recording', () {
      expect(_archive().hasTimelapse, isFalse);
      expect(_archive(timelapsePath: '').hasTimelapse, isFalse);
    });

    test('a path from the server means there is one', () {
      expect(
        _archive(timelapsePath: 'timelapses/42.mp4').hasTimelapse,
        isTrue,
      );
    });

    test('withFavorite does not drop the recording path', () {
      final a = _archive(timelapsePath: 'timelapses/42.mp4');
      expect(a.withFavorite(true).timelapsePath, 'timelapses/42.mp4');
    });
  });

  group('archive detail sheet', () {
    // The timelapse is reached through the media sheet now, so the archive
    // sheet's own evidence of a recording is that entry — see
    // archive_media_sheet_test.dart for the row behind it.
    testWidgets('a recorded print offers the media entry', (tester) async {
      await tester.pumpWidget(
        _archiveScreen(_archive(timelapsePath: 'timelapses/42.mp4')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Wydruk testowy'));
      await tester.pumpAndSettle();

      expect(find.text('Nagrania i zdjęcia'), findsOneWidget);
    });

    testWidgets('a print with no media at all does not', (tester) async {
      await tester.pumpWidget(_archiveScreen(_archive()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Wydruk testowy'));
      await tester.pumpAndSettle();

      expect(find.text('Nagrania i zdjęcia'), findsNothing);
      // The rest of the sheet stands: a missing entry is missing media, not a
      // broken sheet.
      expect(find.text('Drukuj ponownie'), findsOneWidget);
    });
  });

  testWidgets('the player with no server profile shows an error, not a spinner',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [noServerProfileOverride],
        child: plApp(const TimelapseScreen(archiveId: 42)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nie udało się odtworzyć tego timelapse.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
