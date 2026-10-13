import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/data/archive_repository.dart';
import 'package:bambuddy_mobile/features/archive/archive_details.dart';
import 'package:bambuddy_mobile/features/archive/archive_providers.dart';
import 'package:bambuddy_mobile/features/archive/print_outcome.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

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

      final oneLine = (await factsAt(1000)).size.height;
      final narrow = await factsAt(330);

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

  group('verdict thumbs', () {
    late _FakeArchives repo;
    var rejected = 0;

    Future<void> open(WidgetTester tester, Archive archive) async {
      repo = _FakeArchives(archive);
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
        ],
      );
      await tester.pumpAndSettle();
    }

    Finder thumb(String label) => find.byTooltip(label);

    testWidgets('a thumb up records a good part', (tester) async {
      await open(tester, testArchive(confirmRequested: true));

      await tester.tap(thumb(pl.outcomeGood));
      await tester.pumpAndSettle();

      expect(repo.sent.single, PrintVerdict.good);
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

      expect(repo.sent.single, isNull);
    });

    testWidgets('a thumb down records the reject and asks why', (tester) async {
      await open(tester, testArchive(confirmRequested: true));

      await tester.tap(thumb(pl.outcomeReject));
      await tester.pumpAndSettle();

      expect(repo.sent.single, PrintVerdict.reject);
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

      expect(repo.reasons.single, (reason: 'warping', clearReason: false));
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

class _FakeArchives implements ArchiveRepository {
  _FakeArchives(this.archive);

  final Archive archive;
  bool applied = true;
  final sent = <PrintVerdict?>[];
  final reasons = <({String? reason, bool clearReason})>[];

  @override
  Future<({Archive archive, bool applied})> setVerdict(
    int archiveId,
    PrintVerdict? verdict, {
    String? reason,
    bool clearReason = false,
  }) async {
    sent.add(verdict);
    reasons.add((reason: reason, clearReason: clearReason));
    return (archive: archive, applied: applied);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not this test\'s');
}
