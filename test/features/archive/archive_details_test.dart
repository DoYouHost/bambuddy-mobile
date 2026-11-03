import 'dart:async';

import 'dart:ui' show Tristate;
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/models/print_log_entry.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/features/archive/archive_details.dart';
import 'package:bambuddy_mobile/features/archive/archive_providers.dart';
import 'package:bambuddy_mobile/features/archive/print_outcome.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';
import 'archive_fakes.dart';

/// The archive #237 from the web card the feature was copied from.
const _part = Archive(
  id: 237,
  filename: 'part.gcode.3mf',
  status: 'completed',
  printName: 'Part Studio 1 (7)',
  printerId: 4,
  printTimeSeconds: 1400,
  actualTimeSeconds: 1260,
  timeAccuracy: 90,
  filamentUsedGrams: 6.7,
  filamentType: 'PETG',
  filamentColor: '#000000',
  totalLayers: 66,
  layerHeight: 0.18,
  objectCount: 3,
  slicedForModel: 'X2D',
  cost: 0.17,
  energyCost: 0.07,
  wearCost: 0.18,
  tags: 'jig,workshop',
  notes: 'No supports.',
  createdByUsername: 'morgan',
  fileSize: 599859,
);

Future<void> _pump(WidgetTester tester, Widget child) => pumpPhone(
  tester,
  Scaffold(body: SingleChildScrollView(child: child)),
  overrides: [
    noServerProfileOverride,
    printersForPickerProvider.overrideWith(
      (ref) async => const [Printer(id: 4, name: 'Workshop X2D')],
    ),
  ],
);

void main() {
  group('list row', () {
    testWidgets('where and when on one line, what with on the next', (
      tester,
    ) async {
      await _pump(tester, const ArchiveRowMeta(archive: _part));
      await tester.pumpAndSettle();

      expect(find.textContaining('Workshop\u00A0X2D'), findsOneWidget);
      expect(find.textContaining(' · 21'), findsOneWidget);
      expect(find.text('PETG'), findsOneWidget);
      expect(find.text(' · 6.7 g'), findsOneWidget);
      expect(find.byType(FilamentDot), findsOneWidget);
    });

    testWidgets('a printer that is gone gives way to the sliced-for model', (
      tester,
    ) async {
      await _pump(
        tester,
        ArchiveRowMeta(archive: _part.copyWith(printerId: 99)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('X2D ·'), findsOneWidget);
      expect(find.textContaining('Workshop'), findsNothing);
    });

    testWidgets('an empty material and zero grams leave no stray dot', (
      tester,
    ) async {
      await _pump(
        tester,
        ArchiveRowMeta(
          archive: _part.copyWith(
            filamentType: '',
            filamentColor: '',
            filamentUsedGrams: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('g'), findsNothing);
      expect(find.text(''), findsNothing);
    });

    testWidgets('a narrow row wraps between the facts and loses none', (
      tester,
    ) async {
      final archive = _part.copyWith(
        printTimeSeconds: 5700,
        actualTimeSeconds: 5700,
        createdAt: DateTime(2026, 10, 13),
      );
      final facts = find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').contains('Workshop'),
      );
      Future<RenderParagraph> factsAt(double width) async {
        await _pump(
          tester,
          SizedBox(
            width: width,
            child: ArchiveRowMeta(archive: archive),
          ),
        );
        await tester.pumpAndSettle();
        return tester.renderObject<RenderParagraph>(facts);
      }

      final wide = await factsAt(1000);
      final oneLine = wide.size.height;
      // Two thirds of what the facts take on one line: the row has to wrap,
      // whatever font measures them, and two lines (its limit) hold them.
      final narrow = await factsAt(
        wide.getMaxIntrinsicWidth(double.infinity) * 2 / 3,
      );

      expect(narrow.size.height, greaterThan(oneLine * 1.5));
      expect(narrow.didExceedMaxLines, isFalse);
      final text = tester.widget<Text>(facts).data!;
      expect(text, contains('Workshop\u00A0X2D'));
      expect(text, contains('1h\u00A035min'));
    });

    testWidgets('a long material list does not wrap the row', (tester) async {
      await _pump(
        tester,
        SizedBox(
          width: 220,
          child: ArchiveRowMeta(
            archive: _part.copyWith(
              filamentType: 'PLA, PETG, TPU, PLA Silk Dual Color, ASA',
              filamentColor: '#FF0000,#FFFFFF,#0000FF,#000000,#00FF00',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Four dots at most; the grams stay whole.
      expect(find.byType(FilamentDot), findsNWidgets(4));
      expect(find.text(' · 6.7 g'), findsOneWidget);
    });
  });

  group('stats panel', () {
    testWidgets('shows what the web card shows', (tester) async {
      await _pump(tester, const ArchiveStatsPanel(archive: _part));
      await tester.pumpAndSettle();

      expect(find.text('-10%'), findsOneWidget);
      expect(find.text(pl.archiveLayerCount(66)), findsNothing);
      expect(find.text('${pl.archiveLayerCount(66)} · 0.18 mm'), findsOne);
      expect(find.text(pl.archiveObjectCount(3)), findsOneWidget);
      expect(find.bySemanticsLabel(pl.archiveSlicedFor('X2D')), findsOne);
      expect(find.text(pl.archivePrintCost), findsOneWidget);
      expect(find.text('0.42'), findsOneWidget);
      expect(find.text('0.17'), findsOneWidget);
      expect(find.text('0.07'), findsOneWidget);
      expect(find.text('0.18'), findsOneWidget);
      expect(find.text('PETG'), findsOneWidget);
    });

    testWidgets('a single cost is the sum alone, without a breakdown', (
      tester,
    ) async {
      await _pump(
        tester,
        const ArchiveStatsPanel(
          archive: Archive(
            id: 1,
            filename: 'a',
            status: 'completed',
            cost: 1.5,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1.50'), findsOneWidget);
    });

    testWidgets('one line per slot when the slicer listed them', (
      tester,
    ) async {
      await _pump(
        tester,
        ArchiveStatsPanel(
          archive: _part.copyWith(
            filamentType: 'PLA, PETG',
            filamentSlots: const [
              (slot: 1, type: 'PLA', color: '#E23B3B', grams: 18.2),
              (slot: 3, type: 'PETG', color: '#2C6BE0', grams: 4.1),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(pl.archiveSlot(1)), findsOneWidget);
      expect(find.text('18.2 g'), findsOneWidget);
      expect(find.text('4.1 g'), findsOneWidget);
      // The joined field would say the same twice, unpaired.
      expect(find.text('PLA, PETG'), findsNothing);
    });

    testWidgets('nothing sent, no panel', (tester) async {
      await _pump(
        tester,
        const ArchiveStatsPanel(
          archive: Archive(id: 1, filename: 'a', status: 'completed'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Container), findsNothing);
    });
  });

  test('the time badge keeps the web card\'s thresholds', () {
    const t = DashTokens.dark(bambuddyBrand);
    expect(timeAccuracyBadge(t, 100).text, '0%');
    expect(timeAccuracyBadge(t, 105).ink, t.accentGreenInk);
    expect(timeAccuracyBadge(t, 112).text, '+12%');
    expect(timeAccuracyBadge(t, 112).ink, t.accentBlue);
    expect(timeAccuracyBadge(t, 90).text, '-10%');
    expect(timeAccuracyBadge(t, 94.9).ink, t.accentOrangeInk);
  });

  testWidgets('tags, note and footer', (tester) async {
    await _pump(
      tester,
      const Column(
        children: [
          ArchiveTagsAndNote(archive: _part),
          ArchiveFooter(archive: _part),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('jig'), findsOneWidget);
    expect(find.text('workshop'), findsOneWidget);
    expect(find.text('No supports.'), findsOneWidget);
    expect(find.textContaining('morgan'), findsOneWidget);
    expect(find.text('586 KB'), findsOneWidget);
  });

  testWidgets('the link button needs a link', (tester) async {
    await _pump(tester, const ArchiveLinkButton(archive: _part));
    expect(find.text(pl.archiveOpenLink), findsNothing);

    await _pump(
      tester,
      ArchiveLinkButton(
        archive: _part.copyWith(makerworldUrl: 'https://makerworld.com/m/1'),
      ),
    );
    expect(find.text(pl.archiveOpenLink), findsOneWidget);
  });

  group('header chips', () {
    testWidgets('a single good print is counted, as the web counts it', (
      tester,
    ) async {
      await _pump(
        tester,
        ArchiveHeaderChips(
          archive: _part.copyWith(runCount: 1, successfulRunCount: 1),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(pl.archiveGoodCount(1)), findsOneWidget);
      expect(find.text(pl.archiveFailedCount(0)), findsNothing);
      expect(find.text(pl.archiveRunCount(1)), findsNothing);
    });

    testWidgets('a file never printed has neither count', (tester) async {
      await _pump(tester, ArchiveHeaderChips(archive: _part));
      await tester.pumpAndSettle();

      expect(find.text(pl.archiveGoodCount(0)), findsNothing);
    });
  });

  group('verdict thumbs', () {
    late FakeArchives repo;
    var rejected = 0;

    Future<void> open(
      WidgetTester tester,
      Archive archive, {
      bool perPrint = false,
      Future<List<PrintLogEntry>> Function()? runs,
    }) async {
      repo = FakeArchives(archive: archive);
      rejected = 0;
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await pumpPhone(
        tester,
        Scaffold(
          body: ArchiveOutcomeRow(archive: archive, onReject: () => rejected++),
        ),
        overrides: [
          noServerProfileOverride,
          archiveRepositoryProvider.overrideWithValue(repo),
          sharedPreferencesProvider.overrideWithValue(prefs),
          printOutcomeSupportedProvider.overrideWithValue(
            const AsyncData(true),
          ),
          archiveRunsSupportedProvider.overrideWithValue(AsyncData(perPrint)),
          if (runs != null)
            archiveRunsProvider.overrideWith((ref, id) => runs()),
        ],
      );
      await tester.pumpAndSettle();
    }

    Finder thumb(String label) => find.byTooltip(label);

    final judged = testArchive(
      userVerdict: PrintVerdict.good,
    ).copyWith(runCount: 2);
    final row = PrintLogEntry(
      id: 1,
      status: 'completed',
      createdAt: DateTime(2026, 11),
    );

    // There the latest print's verdict is on its own row in the print history.
    testWidgets('a print history with rows takes the line\'s place', (
      tester,
    ) async {
      await open(tester, judged, perPrint: true, runs: () async => [row]);

      expect(thumb(pl.outcomeGood), findsNothing);
    });

    // `runCount` says rows are coming, so the line does not flash up and away
    // (and take a tap meant for no print in particular) while they load.
    testWidgets('while the history loads, the line waits on runCount', (
      tester,
    ) async {
      final never = Completer<List<PrintLogEntry>>();
      await open(tester, judged, perPrint: true, runs: () => never.future);
      expect(thumb(pl.outcomeGood), findsNothing);

      await open(
        tester,
        judged.copyWith(runCount: 0),
        perPrint: true,
        runs: () => Completer<List<PrintLogEntry>>().future,
      );
      expect(thumb(pl.outcomeGood), findsOneWidget);
    });

    testWidgets('an empty print history keeps the line', (tester) async {
      await open(tester, judged, perPrint: true, runs: () async => const []);

      expect(thumb(pl.outcomeGood), findsOneWidget);
    });

    testWidgets('a print history that failed to load keeps the line', (
      tester,
    ) async {
      await open(
        tester,
        judged,
        perPrint: true,
        runs: () async =>
            throw const ApiException(AppErrorCode.badResponse, statusCode: 500),
      );

      expect(thumb(pl.outcomeGood), findsOneWidget);
    });

    testWidgets('an older server keeps the line, rows or not', (tester) async {
      await open(tester, judged, runs: () async => [row]);

      expect(thumb(pl.outcomeGood), findsOneWidget);
    });

    testWidgets('a thumb up records a good part', (tester) async {
      await open(tester, testArchive(confirmRequested: true));

      await tester.tap(thumb(pl.outcomeGood));
      await tester.pumpAndSettle();

      expect(repo.sent.single.verdict, PrintVerdict.good);
      expect(rejected, 0);
    });

    testWidgets('the chosen thumb is filled, and a tap on it clears', (
      tester,
    ) async {
      await open(tester, testArchive(userVerdict: PrintVerdict.good));

      expect(find.byIcon(Icons.thumb_up_alt), findsOneWidget);
      expect(find.byIcon(Icons.thumb_down_alt_outlined), findsOneWidget);
      await tester.tap(thumb(pl.outcomeGood));
      await tester.pumpAndSettle();

      expect(repo.sent.single.verdict, isNull);
    });

    testWidgets('the chosen thumb says it is selected, to a screen reader', (
      tester,
    ) async {
      // A `Semantics` around an `IconButton` never reaches its node, so the state
      // went unannounced until it moved inside the button.
      final handle = tester.ensureSemantics();
      await open(tester, testArchive(userVerdict: PrintVerdict.good));

      Tristate selected(String label) => tester
          .getSemantics(thumb(label))
          .getSemanticsData()
          .flagsCollection
          .isSelected;

      expect(selected(pl.outcomeGood), Tristate.isTrue);
      expect(selected(pl.outcomeReject), Tristate.isFalse);
      handle.dispose();
    });

    testWidgets('a thumb down records the reject and asks why', (tester) async {
      await open(tester, testArchive(confirmRequested: true));

      await tester.tap(thumb(pl.outcomeReject));
      await tester.pumpAndSettle();

      expect(repo.sent.single.verdict, PrintVerdict.reject);
      expect(rejected, 1);
    });

    // A cause typed on the web for a completed print must survive the thumb;
    // the reason step that opens next is where it can be taken off.
    testWidgets('a thumb down keeps the cause the print carries', (
      tester,
    ) async {
      await open(
        tester,
        testArchive(confirmRequested: true).copyWith(failureReason: 'warping'),
      );

      await tester.tap(thumb(pl.outcomeReject));
      await tester.pumpAndSettle();

      expect(repo.sent.single, (
        verdict: PrintVerdict.reject,
        reason: 'warping',
        clearReason: false,
      ));
    });

    testWidgets('a reject the server dropped does not ask why', (tester) async {
      await open(tester, testArchive(confirmRequested: true));
      repo.applied = false;

      await tester.tap(thumb(pl.outcomeReject));
      await tester.pumpAndSettle();

      expect(rejected, 0);
      expect(find.text(pl.outcomeUnsupported), findsOneWidget);
    });
  });
}
