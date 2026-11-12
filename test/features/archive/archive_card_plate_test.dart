import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/models/no_3mf_warning.dart';
import 'package:bambuddy_mobile/features/archive/archive_providers.dart';
import 'package:bambuddy_mobile/features/archive/archive_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// Which plate an archived run printed. The server stored it all along but
/// reported null until 1.2.5.4 (#2796), so the card has to read an absent
/// value as "no plate was chosen" — the common case, and the one where marking
/// a plate on every row would be noise rather than information.

late SharedPreferences _prefs;

Widget _screen(List<Archive> items) => ProviderScope(
  retry: neverRetry,
  overrides: [
    archiveListOverride(items),
    // The screen also carries the "archived without its 3MF" banner, which
    // reads preferences to know whether it was waved off. Nothing to report
    // here — this test is about the row, not the banner.
    no3mfWarningProvider.overrideWith((ref) async => No3mfWarning.none),
    sharedPreferencesProvider.overrideWithValue(_prefs),
    // Null profile → the thumbnail draws its placeholder instead of hitting
    // the network.
    noServerProfileOverride,
  ],
  child: plApp(const ArchiveScreen()),
);

Archive _archive({int? plateId}) => Archive(
  id: 1,
  filename: 'multi.gcode.3mf',
  status: 'completed',
  printName: 'Benchy',
  filamentType: 'PETG',
  plateId: plateId,
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  testWidgets('a run with a chosen plate wears its number on the thumbnail', (
    tester,
  ) async {
    await tester.pumpWidget(_screen([_archive(plateId: 3)]));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.grid_view_outlined), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(
      find.textContaining(pl.archivePlate(3)),
      findsNothing,
      reason: 'the plate is a mark on the thumbnail, not a word in the row',
    );
  });

  testWidgets('a run with no plate recorded says nothing about plates', (
    tester,
  ) async {
    await tester.pumpWidget(_screen([_archive()]));
    await tester.pumpAndSettle();

    // Not even plate 1: an app-started print never sends a plate, so claiming
    // one would be inventing it.
    expect(find.byIcon(Icons.grid_view_outlined), findsNothing);
    expect(find.textContaining('PETG'), findsOneWidget);
  });

  testWidgets('a recorded plate of 0 is read as no plate, not as plate zero', (
    tester,
  ) async {
    // Plates are numbered from 1 and the column has no lower bound, so a 0 is
    // something that went wrong upstream rather than a plate anyone printed.
    // "Plate 0" on the card would pass that on to the reader as a fact.
    await tester.pumpWidget(_screen([_archive(plateId: 0)]));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.grid_view_outlined), findsNothing);
    expect(find.textContaining('PETG'), findsOneWidget);
  });
}
