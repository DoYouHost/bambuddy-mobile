import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/features/archive/archive_photos_screen.dart';
import 'package:bambuddy_mobile/features/archive/archive_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

Archive _archive(List<String> photos) => Archive(
  id: 7,
  filename: 'benchy.gcode.3mf',
  status: 'completed',
  printName: 'Benchy',
  photos: photos,
);

Widget _screen(List<String> photos) => ProviderScope(
  overrides: [
    archiveDetailProvider(7).overrideWith((ref) async => _archive(photos)),
    noServerProfileOverride,
  ],
  child: plApp(const ArchivePhotosScreen(archiveId: 7, title: 'Benchy')),
);

void main() {
  testWidgets('a page counter only when there is more than one photo', (
    tester,
  ) async {
    await tester.pumpWidget(_screen(const ['finish.jpg', 'second.jpg']));
    await tester.pumpAndSettle();

    expect(find.byType(PageView), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
  });

  testWidgets('a single photo → no counter', (tester) async {
    await tester.pumpWidget(_screen(const ['finish.jpg']));
    await tester.pumpAndSettle();

    expect(find.byType(PageView), findsOneWidget);
    expect(find.textContaining(' / '), findsNothing);
  });

  testWidgets('no photos → a message instead of an empty viewer', (
    tester,
  ) async {
    await tester.pumpWidget(_screen(const []));
    await tester.pumpAndSettle();

    expect(find.byType(PageView), findsNothing);
    expect(find.text('Ten wydruk nie ma zdjęć'), findsOneWidget);
  });
}
