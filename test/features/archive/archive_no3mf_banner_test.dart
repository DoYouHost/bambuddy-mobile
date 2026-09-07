import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/models/no_3mf_warning.dart';
import 'package:bambuddy_mobile/features/archive/archive_providers.dart';
import 'package:bambuddy_mobile/features/archive/archive_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

const _archive = Archive(
  id: 1,
  filename: 'benchy.gcode.3mf',
  status: 'completed',
  printName: 'Benchy',
);

late SharedPreferences _prefs;

Widget _screen(No3mfWarning warning) => ProviderScope(
  overrides: [
    archiveListOverride(const [_archive]),
    no3mfWarningProvider.overrideWith((ref) async => warning),
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

  testWidgets('nothing to report, nothing on screen', (tester) async {
    await tester.pumpWidget(_screen(No3mfWarning.none));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  // The original wording, which is also what an older server's reasonless
  // answer has to keep showing.
  testWidgets('no reason blames the slicer setting and links install step 4', (
    tester,
  ) async {
    await tester.pumpWidget(
      _screen(
        const No3mfWarning(
          hasFallback: true,
          reason: No3mfReason.slicerSetting,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('bez miniatur'), findsOneWidget);
    expect(find.text('Zobacz krok 4 instalacji'), findsOneWidget);
  });

  // #2780: the same advice was actively wrong here — the setting is already on.
  testWidgets('internal storage gets its own text and its own link', (
    tester,
  ) async {
    await tester.pumpWidget(
      _screen(
        const No3mfWarning(
          hasFallback: true,
          reason: No3mfReason.internalStorage,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('została w pamięci wewnętrznej'),
      findsOneWidget,
    );
    expect(find.text('Dlaczego tak się dzieje'), findsOneWidget);
    expect(find.text('Zobacz krok 4 instalacji'), findsNothing);
  });

  testWidgets('an empty card slot has nothing to link — the fix is the fix', (
    tester,
  ) async {
    await tester.pumpWidget(
      _screen(
        const No3mfWarning(
          hasFallback: true,
          reason: No3mfReason.noExternalStorage,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('brak nośnika w drukarce'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsNothing);
  });

  testWidgets('dismissing hides it and remembers', (tester) async {
    await tester.pumpWidget(
      _screen(
        const No3mfWarning(
          hasFallback: true,
          reason: No3mfReason.noExternalStorage,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    expect(_prefs.getBool('archive_no3mf_dismissed'), isTrue);
  });

  testWidgets('an install that already dismissed it is not asked again', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'archive_no3mf_dismissed': true});
    _prefs = await SharedPreferences.getInstance();

    await pumpPhone(
      tester,
      const ArchiveScreen(),
      overrides: [
        archiveListOverride(const [_archive]),
        sharedPreferencesProvider.overrideWithValue(_prefs),
        noServerProfileOverride,
      ],
    );
    await tester.pumpAndSettle();

    // The real provider is in play here: dismissed means it never asks the
    // server, so there is nothing to render even if the server would have
    // said yes.
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });
}
