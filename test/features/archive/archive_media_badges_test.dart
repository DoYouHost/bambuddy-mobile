import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/features/archive/archive_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// The archive screen reads one stored flag (the no-3MF nudge's one-shot
/// dismissal), so every test that builds it needs prefs in the scope.
late SharedPreferences _prefs;

Widget _screen(List<Archive> items) => ProviderScope(
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

  testWidgets('wydruk bez nagrania i zdjęć nie ma znaczników', (tester) async {
    await tester.pumpWidget(_screen([testArchive()]));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.movie), findsNothing);
    expect(find.byIcon(Icons.photo_camera), findsNothing);
  });

  testWidgets('timelapse_path → znacznik nagrania na karcie', (tester) async {
    await tester.pumpWidget(
      _screen([testArchive(timelapsePath: 'archive/1/video.mp4')]),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.movie), findsOneWidget);
    expect(find.byIcon(Icons.photo_camera), findsNothing);
  });

  testWidgets('photos → znacznik zdjęcia na karcie', (tester) async {
    await tester.pumpWidget(
      _screen([
        testArchive(photos: const ['finish.jpg']),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.photo_camera), findsOneWidget);
    expect(find.byIcon(Icons.movie), findsNothing);
  });

  testWidgets('oba znaczniki jednocześnie', (tester) async {
    await tester.pumpWidget(
      _screen([
        testArchive(
          timelapsePath: 'archive/1/video.mp4',
          photos: const ['finish.jpg', 'reka.jpg'],
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.movie), findsOneWidget);
    expect(find.byIcon(Icons.photo_camera), findsOneWidget);
  });
}
