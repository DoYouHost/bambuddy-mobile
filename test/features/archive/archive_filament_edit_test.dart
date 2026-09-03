import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/models/no_3mf_warning.dart';
import 'package:bambuddy_mobile/data/archive_repository.dart';
import 'package:bambuddy_mobile/features/archive/archive_filament_edit.dart';
import 'package:bambuddy_mobile/features/archive/archive_providers.dart';
import 'package:bambuddy_mobile/features/archive/archive_screen.dart';
import 'package:bambuddy_mobile/features/slicer/slice_providers.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// The weight a print is recorded with — the one archive field the app types
/// into. Written for the print that archived without its 3MF and therefore has
/// no figure at all, which is also why the "an older server dropped it" answer
/// matters: there the user would be looking at an empty row they were just told
/// was saved.
void main() {
  group('reading the field', () {
    test('a plain number is the weight', () {
      expect(parseFilamentGrams('42'), (grams: 42.0, error: null));
      expect(parseFilamentGrams('  42  '), (grams: 42.0, error: null));
      expect(parseFilamentGrams('12.5'), (grams: 12.5, error: null));
    });

    // The decimal key of a Polish keyboard, which `double.tryParse` refuses —
    // without this the field silently rejects what the phone itself produces.
    test('a comma is a decimal point', () {
      expect(parseFilamentGrams('12,5'), (grams: 12.5, error: null));
    });

    // Including the non-breaking one, which is how a locale-formatted number
    // pasted from elsewhere groups its thousands.
    test('grouped thousands are still one number', () {
      expect(parseFilamentGrams('1 234,5'), (grams: 1234.5, error: null));
    });

    // Not a mistake: it is how a wrong correction is taken back.
    test('an empty field clears the weight', () {
      expect(parseFilamentGrams(''), (grams: null, error: null));
      expect(parseFilamentGrams('   '), (grams: null, error: null));
    });

    test('what is not a number says so', () {
      for (final text in ['abc', '.', '-', '1,2,3', '4 5 6.7.8']) {
        expect(parseFilamentGrams(text).error, FilamentGramsError.notANumber,
            reason: '"$text" is not a weight');
      }
    });

    // The server's own bounds (`ge=0, le=100_000`), checked here so a typo
    // answers in the field instead of as a 422 from the other end.
    test('the server bounds are the field bounds', () {
      expect(parseFilamentGrams('0'), (grams: 0.0, error: null));
      expect(parseFilamentGrams('100000'), (grams: 100000.0, error: null));
      expect(parseFilamentGrams('-1').error, FilamentGramsError.outOfRange);
      expect(parseFilamentGrams('100000.1').error,
          FilamentGramsError.outOfRange);
    });
  });

  group('writing the field back out', () {
    test('a whole number carries no decimal point', () {
      expect(filamentGramsText(42), '42');
      expect(filamentGramsText(0), '0');
      expect(filamentGramsText(1200), '1200');
    });

    test('typed precision survives being offered back', () {
      expect(filamentGramsText(12.5), '12.5');
      expect(filamentGramsText(10.1), '10.1');
    });

    // Reopening the dialog must not hand back a figure that differs from the
    // stored one — saving again would then write the difference in.
    test('float noise does not reach the field', () {
      expect(filamentGramsText(12.30000000000001), '12.3');
    });

    test('no weight is an empty field, not a zero', () {
      expect(filamentGramsText(null), '');
    });
  });

  group('the row', () {
    late _FakeArchives repository;

    Widget row(Archive archive) => ProviderScope(
          overrides: [
            archiveListOverride([archive]),
            archiveRepositoryProvider.overrideWithValue(repository),
          ],
          child: plApp(Scaffold(body: ArchiveFilamentRow(archive: archive))),
        );

    Archive archive({double? grams}) => Archive(
          id: 1,
          filename: 'benchy.gcode.3mf',
          status: 'completed',
          filamentUsedGrams: grams,
        );

    AppLocalizations l10n(WidgetTester tester) =>
        AppLocalizations.of(tester.element(find.byType(ArchiveFilamentRow)));

    /// Opens the dialog, types [text] and saves.
    Future<void> edit(WidgetTester tester, String text) async {
      await tester.tap(find.byType(ArchiveFilamentRow));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), text);
      await tester.tap(find.widgetWithText(FilledButton, l10n(tester).fmSave));
      await tester.pumpAndSettle();
    }

    setUp(() => repository = _FakeArchives());

    testWidgets('a print with no weight says so rather than showing a zero',
        (tester) async {
      await tester.pumpWidget(row(archive()));
      await tester.pumpAndSettle();

      expect(find.text(l10n(tester).archiveFilamentNone), findsOneWidget);
    });

    testWidgets('a saved weight is sent and shown without a reload',
        (tester) async {
      await tester.pumpWidget(row(archive(grams: 17.1)));
      await tester.pumpAndSettle();
      expect(find.text(l10n(tester).archiveFilamentGrams('17.1')),
          findsOneWidget);

      await edit(tester, '42');

      expect(repository.sent, [42.0]);
      expect(find.text(l10n(tester).archiveFilamentSaved), findsOneWidget);
      expect(find.text(l10n(tester).archiveFilamentGrams('42')), findsOneWidget,
          reason: 'the row follows the stored value the PATCH answered with');
    });

    testWidgets('an emptied field clears the weight', (tester) async {
      await tester.pumpWidget(row(archive(grams: 17.1)));
      await tester.pumpAndSettle();

      await edit(tester, '');

      expect(repository.sent, [null]);
      expect(find.text(l10n(tester).archiveFilamentNone), findsOneWidget);
    });

    // The case a 200 cannot be trusted for: an older server answers the same
    // way and stores nothing, so "saved" would be a lie about a row the user
    // can see is unchanged.
    testWidgets('a server that dropped the weight is not reported as saved',
        (tester) async {
      repository.applied = false;
      await tester.pumpWidget(row(archive(grams: 17.1)));
      await tester.pumpAndSettle();

      await edit(tester, '42');

      expect(find.text(l10n(tester).archiveFilamentUnsupported), findsOneWidget);
      expect(find.text(l10n(tester).archiveFilamentSaved), findsNothing);
      expect(find.text(l10n(tester).archiveFilamentGrams('17.1')),
          findsOneWidget);
    });

    // Letters never get this far — the field's formatter drops them as they are
    // typed — so what has to be refused is a number shape: two separators, a
    // lone dot, the half-finished value of someone still editing.
    testWidgets('a weight that is not a number never leaves the dialog',
        (tester) async {
      await tester.pumpWidget(row(archive(grams: 17.1)));
      await tester.pumpAndSettle();

      await edit(tester, '1.2.3');

      expect(repository.sent, isEmpty);
      expect(find.text(l10n(tester).archiveFilamentNotANumber), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget, reason: 'still open');
    });

    testWidgets('a refusal is worded, and the row keeps the stored weight',
        (tester) async {
      repository.error = const ApiException(
        AppErrorCode.badResponse,
        statusCode: 403,
        detail: 'You can only update your own archives',
      );
      await tester.pumpWidget(row(archive(grams: 17.1)));
      await tester.pumpAndSettle();

      await edit(tester, '42');

      expect(tester.takeException(), isNull);
      expect(find.text(l10n(tester).archiveFilamentGrams('17.1')),
          findsOneWidget);
      expect(find.text(l10n(tester).archiveFilamentSaved), findsNothing);
    });
  });

  // The row is only worth anything where the user can reach it, and nothing
  // else opens this sheet in the test suite.
  testWidgets('the print\'s sheet carries the weight', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final archive = Archive(
      id: 1,
      filename: 'benchy.gcode.3mf',
      status: 'completed',
      printName: 'Benchy',
      filamentUsedGrams: 17.1,
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        archiveListOverride([archive]),
        no3mfWarningProvider.overrideWith((ref) async => No3mfWarning.none),
        sharedPreferencesProvider.overrideWithValue(prefs),
        slicerEnabledProvider.overrideWith((ref) async => false),
        noServerProfileOverride,
      ],
      child: plApp(const ArchiveScreen()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Benchy'));
    await tester.pumpAndSettle();

    expect(find.byType(ArchiveFilamentRow), findsOneWidget);
  });
}

/// The list the screen holds, with nothing behind it.

/// Records the weights it was asked to store and answers like the server that
/// stored them — or, with [applied] false, like one that dropped the key.
class _FakeArchives implements ArchiveRepository {
  final List<double?> sent = [];
  bool applied = true;
  AppApiException? error;

  @override
  Future<({Archive archive, bool applied})> setFilamentGrams(
    int archiveId,
    double? grams,
  ) async {
    if (error != null) throw error!;
    sent.add(grams);
    final stored = Archive(
      id: archiveId,
      filename: 'benchy.gcode.3mf',
      status: 'completed',
      filamentUsedGrams: applied ? grams : 17.1,
    );
    return (archive: stored, applied: applied);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not this test\'s');
}
