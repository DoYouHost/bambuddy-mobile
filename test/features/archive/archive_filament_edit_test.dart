import 'dart:async';

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
import 'package:flutter/services.dart';
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
        expect(
          parseFilamentGrams(text).error,
          FilamentGramsError.notANumber,
          reason: '"$text" is not a weight',
        );
      }
    });

    // The server's own bounds (`ge=0, le=100_000`), checked here so a typo
    // answers in the field instead of as a 422 from the other end.
    test('the server bounds are the field bounds', () {
      expect(parseFilamentGrams('0'), (grams: 0.0, error: null));
      expect(parseFilamentGrams('100000'), (grams: 100000.0, error: null));
      expect(parseFilamentGrams('-1').error, FilamentGramsError.outOfRange);
      expect(
        parseFilamentGrams('100000.1').error,
        FilamentGramsError.outOfRange,
      );
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

  // The archive's figure is the whole file's estimate; the runs' is what they
  // drew. The second line exists for where they disagree — a print stopped
  // partway, a tracked spool that measured its own delta, a file printed more
  // than once.
  group('what the runs say', () {
    Archive archive({double? grams = 15.8, double? actual, int runCount = 1}) =>
        Archive(
          id: 1,
          filename: 'benchy.gcode.3mf',
          status: 'completed',
          filamentUsedGrams: grams,
          totalFilamentActualGrams: actual,
          runCount: runCount,
        );

    late AppLocalizations l10n;

    setUpAll(
      () async =>
          l10n = await AppLocalizations.delegate.load(const Locale('pl')),
    );

    // The usual print: one run, no tracked spool, so the entry inherited the
    // estimate. A line saying the same number twice is noise.
    test('a run that used what the file estimated adds nothing', () {
      expect(filamentActualCaption(archive(actual: 15.8), l10n), isNull);
    });

    // Every server older than the run aggregate reports no runs, so the row
    // has to look exactly as it did before the field existed.
    test('a file with no logged runs adds nothing', () {
      expect(
        filamentActualCaption(archive(actual: null, runCount: 0), l10n),
        isNull,
      );
    });

    test('a run that stopped partway shows what it drew', () {
      expect(
        filamentActualCaption(archive(grams: 88.1, actual: 35.2), l10n),
        l10n.archiveFilamentActual(l10n.archiveFilamentGrams('35.2'), 1),
      );
    });

    test(
      'several runs say so, since the sum is not comparable to one print',
      () {
        final caption = filamentActualCaption(
          archive(actual: 47.4, runCount: 3),
          l10n,
        );
        expect(caption, contains('47.4'));
        expect(caption, contains('3'));
      },
    );

    // A print cancelled before its first layer. The wire cannot tell a sum of
    // zero from no sum at all — the route answers `float(total) if total else
    // None` — and it does not have to: neither is a measurement.
    test(
      'runs that recorded nothing say that, rather than claiming a zero',
      () {
        expect(
          filamentActualCaption(archive(actual: null), l10n),
          l10n.archiveFilamentNoActual,
        );
      },
    );

    // The case the manual edit exists for, seen from the other side: no
    // estimate either, and a run that measured something.
    test('a measured run counts even where the file estimated nothing', () {
      expect(
        filamentActualCaption(archive(grams: null, actual: 6.3), l10n),
        l10n.archiveFilamentActual(l10n.archiveFilamentGrams('6.3'), 1),
      );
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

    testWidgets('a print with no weight says so rather than showing a zero', (
      tester,
    ) async {
      await tester.pumpWidget(row(archive()));
      await tester.pumpAndSettle();

      expect(find.text(l10n(tester).archiveFilamentNone), findsOneWidget);
    });

    // The row is one thing to touch, so it has to be one thing to read: the
    // merge is also where the `logTag` identifier could have been lost, and
    // that identifier is what every diagnostic report names this control by.
    testWidgets('reads as a single button, still named for the log', (
      tester,
    ) async {
      await tester.pumpWidget(row(archive(grams: 17.1)));
      await tester.pumpAndSettle();
      final handle = tester.ensureSemantics();

      expect(
        find.bySemanticsIdentifier('archive.filament_edit'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.byType(ArchiveFilamentRow)),
        isSemantics(isButton: true, hasTapAction: true),
      );
      handle.dispose();
    });

    testWidgets('a saved weight is sent and shown without a reload', (
      tester,
    ) async {
      await tester.pumpWidget(row(archive(grams: 17.1)));
      await tester.pumpAndSettle();
      expect(
        find.text(l10n(tester).archiveFilamentGrams('17.1')),
        findsOneWidget,
      );

      await edit(tester, '42');

      expect(repository.sent, [42.0]);
      expect(find.text(l10n(tester).archiveFilamentSaved), findsOneWidget);
      expect(
        find.text(l10n(tester).archiveFilamentGrams('42')),
        findsOneWidget,
        reason: 'the row follows the stored value the PATCH answered with',
      );
    });

    // The sheet holding this row is a StatelessWidget built once from the list
    // as it was when the print was tapped, so the snapshot it passes down still
    // carries the pre-edit weight. Seeding the field from it would offer the
    // old figure back and write it over the new one on the next save.
    testWidgets('a second edit starts from the weight the first one stored', (
      tester,
    ) async {
      await tester.pumpWidget(row(archive(grams: 17.1)));
      await tester.pumpAndSettle();

      await edit(tester, '42');
      await tester.tap(find.byType(ArchiveFilamentRow));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        '42',
      );
    });

    // Opening the row to read the weight and closing it with Save is an
    // ordinary thing to do. It used to spend a request on writing back exactly
    // what was there, and answer "saved" for storing nothing.
    testWidgets('saving an unchanged weight asks the server nothing', (
      tester,
    ) async {
      await tester.pumpWidget(row(archive(grams: 17.1)));
      await tester.pumpAndSettle();

      await edit(tester, '17.1');

      expect(repository.sent, isEmpty);
      expect(find.text(l10n(tester).archiveFilamentSaved), findsNothing);
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
    testWidgets('a server that dropped the weight is not reported as saved', (
      tester,
    ) async {
      repository.applied = false;
      await tester.pumpWidget(row(archive(grams: 17.1)));
      await tester.pumpAndSettle();

      await edit(tester, '42');

      expect(
        find.text(l10n(tester).archiveFilamentUnsupported),
        findsOneWidget,
      );
      expect(find.text(l10n(tester).archiveFilamentSaved), findsNothing);
      expect(
        find.text(l10n(tester).archiveFilamentGrams('17.1')),
        findsOneWidget,
      );
    });

    // Letters never get this far — the field's formatter drops them as they are
    // typed — so what has to be refused is a number shape: two separators, a
    // lone dot, the half-finished value of someone still editing.
    testWidgets('a weight that is not a number never leaves the dialog', (
      tester,
    ) async {
      await tester.pumpWidget(row(archive(grams: 17.1)));
      await tester.pumpAndSettle();

      await edit(tester, '1.2.3');

      expect(repository.sent, isEmpty);
      expect(find.text(l10n(tester).archiveFilamentNotANumber), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget, reason: 'still open');
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
        isTrue,
        reason: 'the next keystroke lands in the field the message is about',
      );
    });

    // `errorText` is not a live region, and Save does not always move the
    // focus either — from the IME's Done key the field already has it, so the
    // move is a no-op. Without saying the sentence out loud, a screen reader
    // user presses Save and the dialog appears to do nothing.
    testWidgets('a refused weight is read out, not just drawn', (tester) async {
      final announced = <String>[];
      tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (
            message,
          ) async {
            final event = (message as Map<Object?, Object?>?) ?? const {};
            if (event['type'] == 'announce') {
              final data = event['data'] as Map<Object?, Object?>;
              announced.add(data['message'] as String);
            }
            return null;
          });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockDecodedMessageHandler<dynamic>(
              SystemChannels.accessibility,
              null,
            ),
      );

      await tester.pumpWidget(row(archive(grams: 17.1)));
      await tester.pumpAndSettle();

      await edit(tester, '1.2.3');

      expect(announced, [l10n(tester).archiveFilamentNotANumber]);
    });

    testWidgets('a refusal is worded, and the row keeps the stored weight', (
      tester,
    ) async {
      repository.error = const ApiException(
        AppErrorCode.badResponse,
        statusCode: 403,
        detail: 'You can only update your own archives',
      );
      await tester.pumpWidget(row(archive(grams: 17.1)));
      await tester.pumpAndSettle();

      await edit(tester, '42');

      expect(tester.takeException(), isNull);
      expect(
        find.text(l10n(tester).archiveFilamentGrams('17.1')),
        findsOneWidget,
      );
      expect(find.text(l10n(tester).archiveFilamentSaved), findsNothing);
    });
  });

  // The request outlives the sheet: a user can save and swipe the sheet away
  // before the server answers, and the weight is stored either way. Reading
  // providers through a disposed widget's `ref` would throw, leaving the list
  // showing the old figure until a manual refresh.
  testWidgets('a save the user walked away from still reaches the list', (
    tester,
  ) async {
    final repository = _FakeArchives()..held = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        archiveListOverride([
          const Archive(
            id: 1,
            filename: 'benchy.gcode.3mf',
            status: 'completed',
            filamentUsedGrams: 17.1,
          ),
        ]),
        archiveRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    // The archive screen behind the sheet, which is what keeps the list alive
    // while the sheet is dismissed — the tabs are an `IndexedStack`, so it does
    // not go away. Without a listener the auto-disposed provider is rebuilt
    // from scratch and there is no list to write into.
    container.listen(archiveProvider, (_, _) {});

    Widget app(Widget child) => UncontrolledProviderScope(
      container: container,
      child: plApp(Scaffold(body: child)),
    );

    await tester.pumpWidget(
      app(
        const ArchiveFilamentRow(
          archive: Archive(
            id: 1,
            filename: 'benchy.gcode.3mf',
            status: 'completed',
            filamentUsedGrams: 17.1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ArchiveFilamentRow));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '42');
    await tester.tap(find.byType(FilledButton));
    // Not `pumpAndSettle`: the row spins while the request is held, and an
    // indeterminate progress indicator never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(repository.sent, [42.0], reason: 'the request is on the wire');

    // The sheet goes while it is still there.
    await tester.pumpWidget(app(const SizedBox.shrink()));
    await tester.pump();
    expect(find.byType(ArchiveFilamentRow), findsNothing);

    repository.release();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      container.read(archiveProvider).value!.single.filamentUsedGrams,
      42,
      reason: 'the list holds what the server stored',
    );
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

    await pumpPhone(
      tester,
      const ArchiveScreen(),
      overrides: [
        archiveListOverride([archive]),
        no3mfWarningProvider.overrideWith((ref) async => No3mfWarning.none),
        sharedPreferencesProvider.overrideWithValue(prefs),
        slicerEnabledProvider.overrideWith((ref) async => false),
        noServerProfileOverride,
      ],
    );
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

  /// Set before the edit to leave the request in flight until [release].
  Completer<void>? held;

  void release() => held!.complete();

  @override
  Future<({Archive archive, bool applied})> setFilamentGrams(
    int archiveId,
    double? grams,
  ) async {
    if (error != null) throw error!;
    sent.add(grams);
    if (held != null) await held!.future;
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
