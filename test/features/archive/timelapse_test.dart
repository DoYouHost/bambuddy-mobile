import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/features/archive/archive_providers.dart';
import 'package:bambuddy_mobile/features/archive/archive_screen.dart';
import 'package:bambuddy_mobile/features/archive/timelapse_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Podaje listę archiwów bez dotykania repozytorium/sieci.
class _FakeArchiveNotifier extends ArchiveNotifier {
  _FakeArchiveNotifier(this._items);

  final List<Archive> _items;

  @override
  Future<List<Archive>> build() async => _items;
}

/// Profil null → miniatury rysują placeholder, a ekran timelapse nie ma dokąd
/// pójść po wideo (to jest właśnie ścieżka błędu, którą testujemy).
class _NullProfileNotifier extends ServerProfileNotifier {
  @override
  ServerProfile? build() => null;
}

Archive _archive({String? timelapsePath}) => Archive(
  id: 42,
  filename: 'print.gcode.3mf',
  status: 'completed',
  printName: 'Wydruk testowy',
  timelapsePath: timelapsePath,
);

Widget _archiveScreen(Archive archive) => ProviderScope(
  overrides: [
    archiveProvider.overrideWith(() => _FakeArchiveNotifier([archive])),
    serverProfileProvider.overrideWith(_NullProfileNotifier.new),
  ],
  child: plApp(const ArchiveScreen()),
);

void main() {
  group('Archive.hasTimelapse', () {
    test('null i pusta ścieżka znaczą brak nagrania', () {
      expect(_archive().hasTimelapse, isFalse);
      expect(_archive(timelapsePath: '').hasTimelapse, isFalse);
    });

    test('ścieżka z serwera znaczy, że nagranie jest', () {
      expect(
        _archive(timelapsePath: 'timelapses/42.mp4').hasTimelapse,
        isTrue,
      );
    });

    test('withFavorite nie gubi ścieżki nagrania', () {
      final a = _archive(timelapsePath: 'timelapses/42.mp4');
      expect(a.withFavorite(true).timelapsePath, 'timelapses/42.mp4');
    });
  });

  group('arkusz archiwum', () {
    testWidgets('pokazuje przycisk timelapse tylko gdy nagranie istnieje',
        (tester) async {
      await tester.pumpWidget(
        _archiveScreen(_archive(timelapsePath: 'timelapses/42.mp4')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Wydruk testowy'));
      await tester.pumpAndSettle();

      expect(find.text('Obejrzyj timelapse'), findsOneWidget);
    });

    testWidgets('bez nagrania przycisku nie ma', (tester) async {
      await tester.pumpWidget(_archiveScreen(_archive()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Wydruk testowy'));
      await tester.pumpAndSettle();

      expect(find.text('Obejrzyj timelapse'), findsNothing);
      // Reszta arkusza stoi — brak przycisku to brak nagrania, nie awaria.
      expect(find.text('Drukuj ponownie'), findsOneWidget);
    });
  });

  testWidgets('odtwarzacz bez profilu serwera pokazuje błąd, nie spinner',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [serverProfileProvider.overrideWith(_NullProfileNotifier.new)],
        child: plApp(const TimelapseScreen(archiveId: 42)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nie udało się odtworzyć tego timelapse.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
