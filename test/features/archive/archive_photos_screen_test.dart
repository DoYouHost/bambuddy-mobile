import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/features/archive/archive_photos_screen.dart';
import 'package:bambuddy_mobile/features/archive/archive_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Profil null → ekran nie buduje URL-i i nie sięga po token kamery.
class _NullProfileNotifier extends ServerProfileNotifier {
  @override
  ServerProfile? build() => null;
}

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
    serverProfileProvider.overrideWith(_NullProfileNotifier.new),
  ],
  child: plApp(const ArchivePhotosScreen(archiveId: 7, title: 'Benchy')),
);

void main() {
  testWidgets('licznik stron tylko przy więcej niż jednym zdjęciu', (
    tester,
  ) async {
    await tester.pumpWidget(_screen(const ['finish.jpg', 'druga.jpg']));
    await tester.pumpAndSettle();

    expect(find.byType(PageView), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
  });

  testWidgets('jedno zdjęcie → bez licznika', (tester) async {
    await tester.pumpWidget(_screen(const ['finish.jpg']));
    await tester.pumpAndSettle();

    expect(find.byType(PageView), findsOneWidget);
    expect(find.textContaining(' / '), findsNothing);
  });

  testWidgets('brak zdjęć → komunikat zamiast pustej przeglądarki', (
    tester,
  ) async {
    await tester.pumpWidget(_screen(const []));
    await tester.pumpAndSettle();

    expect(find.byType(PageView), findsNothing);
    expect(find.text('Ten wydruk nie ma zdjęć'), findsOneWidget);
  });
}
