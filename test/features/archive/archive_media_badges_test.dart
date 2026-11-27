import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/features/archive/archive_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// The archive screen reads one stored flag (the no-3MF nudge's one-shot
/// dismissal), so every test that builds it needs prefs in the scope.
late SharedPreferences _prefs;

Widget _screen(List<Archive> items) => ProviderScope(
  retry: neverRetry,
  overrides: [
    archiveListOverride(items),
    sharedPreferencesProvider.overrideWithValue(_prefs),
    noServerProfileOverride,
  ],
  child: plApp(const ArchiveScreen()),
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  final cases = <(String, Archive, {bool movie, bool photo})>[
    (
      'a print with no recording and no photos has no badges',
      testArchive(),
      movie: false,
      photo: false,
    ),
    (
      'timelapse_path → recording badge on the card',
      testArchive(timelapsePath: 'archive/1/video.mp4'),
      movie: true,
      photo: false,
    ),
    (
      'photos → photo badge on the card',
      testArchive(photos: const ['finish.jpg']),
      movie: false,
      photo: true,
    ),
    (
      'both badges at once',
      testArchive(
        timelapsePath: 'archive/1/video.mp4',
        photos: const ['finish.jpg', 'hand.jpg'],
      ),
      movie: true,
      photo: true,
    ),
  ];

  for (final (name, archive, :movie, :photo) in cases) {
    testWidgets(name, (tester) async {
      await tester.pumpWidget(_screen([archive]));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.movie), movie ? findsOneWidget : findsNothing);
      expect(
        find.byIcon(Icons.photo_camera),
        photo ? findsOneWidget : findsNothing,
      );
    });
  }
}
