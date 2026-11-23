import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/features/archive/archive_photos_screen.dart';
import 'package:bambuddy_mobile/features/archive/archive_providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bambuddy_mobile/providers.dart';

import '../../helpers.dart';

Archive _archive(List<String> photos) => Archive(
  id: 7,
  filename: 'benchy.gcode.3mf',
  status: 'completed',
  printName: 'Benchy',
  photos: photos,
);

Widget _screen(List<String> photos, {List<String>? only}) => ProviderScope(
  retry: neverRetry,
  overrides: [
    archiveDetailProvider(7).overrideWith((ref) async => _archive(photos)),
    noServerProfileOverride,
  ],
  child: plApp(ArchivePhotosScreen(archiveId: 7, only: only, title: 'Benchy')),
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
    expect(find.text(pl.archivePhotosEmpty), findsOneWidget);
  });

  testWidgets('one print\'s photos: only those the archive still lists', (
    tester,
  ) async {
    await tester.pumpWidget(
      _screen(
        const ['finish_1.jpg', 'finish_2.jpg', 'upload.jpg'],
        only: const ['finish_2.jpg', 'removed.jpg'],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PageView), findsOneWidget);
    expect(find.textContaining(' / '), findsNothing);
  });

  testWidgets('a print whose photos are all gone gets the message', (
    tester,
  ) async {
    await tester.pumpWidget(
      _screen(const ['finish_1.jpg'], only: const ['removed.jpg']),
    );
    await tester.pumpAndSettle();

    expect(find.text(pl.archivePhotosEmpty), findsOneWidget);
  });
}
