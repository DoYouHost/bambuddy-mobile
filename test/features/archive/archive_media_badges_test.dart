import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/features/archive/archive_providers.dart';
import 'package:bambuddy_mobile/features/archive/archive_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

class _FakeArchiveNotifier extends ArchiveNotifier {
  _FakeArchiveNotifier(this._items);

  final List<Archive> _items;

  @override
  Future<List<Archive>> build() async => _items;
}

/// The archive screen reads one stored flag (the no-3MF nudge's one-shot
/// dismissal), so every test that builds it needs prefs in the scope.
late SharedPreferences _prefs;

Widget _screen(List<Archive> items) => ProviderScope(
  overrides: [
    archiveProvider.overrideWith(() => _FakeArchiveNotifier(items)),
    sharedPreferencesProvider.overrideWithValue(_prefs),
    noServerProfileOverride,
  ],
  child: plApp(const ArchiveScreen()),
);

Archive _archive({
  int id = 1,
  String? timelapsePath,
  List<String> photos = const [],
}) => Archive(
  id: id,
  filename: 'benchy.gcode.3mf',
  status: 'completed',
  printName: 'Benchy',
  timelapsePath: timelapsePath,
  photos: photos,
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  testWidgets('wydruk bez nagrania i zdjęć nie ma znaczników', (tester) async {
    await tester.pumpWidget(_screen([_archive()]));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.movie), findsNothing);
    expect(find.byIcon(Icons.photo_camera), findsNothing);
  });

  testWidgets('timelapse_path → znacznik nagrania na karcie', (tester) async {
    await tester.pumpWidget(
      _screen([_archive(timelapsePath: 'archive/1/video.mp4')]),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.movie), findsOneWidget);
    expect(find.byIcon(Icons.photo_camera), findsNothing);
  });

  testWidgets('photos → znacznik zdjęcia na karcie', (tester) async {
    await tester.pumpWidget(_screen([_archive(photos: const ['finish.jpg'])]));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.photo_camera), findsOneWidget);
    expect(find.byIcon(Icons.movie), findsNothing);
  });

  testWidgets('oba znaczniki jednocześnie', (tester) async {
    await tester.pumpWidget(
      _screen([
        _archive(
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
