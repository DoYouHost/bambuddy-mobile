import 'package:bambuddy_mobile/core/format/duration_format.dart';
import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/models/plate_list.dart';
import 'package:bambuddy_mobile/core/models/print_log_entry.dart';
import 'package:bambuddy_mobile/features/archive/archive_providers.dart';
import 'package:bambuddy_mobile/features/archive/archive_runs.dart';
import 'package:bambuddy_mobile/features/slicer/slice_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers.dart';

const _archive = Archive(
  id: 5,
  filename: 'bag.gcode.3mf',
  status: 'completed',
  printName: 'Bag dispenser',
  runCount: 3,
);

PrintLogEntry _run(
  int id, {
  String status = 'completed',
  int? plateId,
  int? duration = 3780,
  int? estimate = 3600,
  bool unmeasured = false,
  double? grams = 48.1,
  double? estimateGrams,
  List<String>? photos,
  String? timelapse,
  PrintVerdict? verdict,
  String? notes,
  String? failureReason,
}) => PrintLogEntry(
  id: id,
  status: status,
  createdAt: DateTime.utc(2026, 11, id),
  startedAt: DateTime.utc(2026, 11, id, 10),
  printerName: 'X1 Carbon',
  plateId: plateId,
  durationSeconds: duration,
  estimateSeconds: estimate,
  durationUnmeasured: unmeasured,
  filamentUsedGrams: grams,
  estimateGrams: estimateGrams,
  filamentColor: '#000000,#FFFFFF',
  filamentType: 'PLA,PLA',
  photos: photos,
  timelapsePath: timelapse,
  userVerdict: verdict,
  notes: notes,
  failureReason: failureReason,
  createdByUsername: 'morgan',
);

void main() {
  group('runMedia', () {
    const archive = Archive(
      id: 5,
      filename: 'a',
      status: 'completed',
      photos: ['finish_1.jpg', 'finish_2.jpg', 'upload.jpg'],
      timelapsePath: 'archive/5/old.mp4',
    );

    test('a print with its own list shows those, empty or not', () {
      final own = _run(2, photos: const ['finish_2.jpg']);
      final none = _run(3, photos: const []);
      final runs = [own, none];

      expect(runMedia(archive, runs, own).photos, ['finish_2.jpg']);
      expect(runMedia(archive, runs, none).photos, isEmpty);
    });

    test('a print logged before the redesign shares what nobody holds', () {
      final own = _run(2, photos: const ['finish_2.jpg']);
      final legacy = _run(1);
      final media = runMedia(archive, [own, legacy], legacy);

      expect(media.photos, ['finish_1.jpg', 'upload.jpg']);
      expect(media.archiveVideo, isTrue, reason: 'no print holds that video');
      expect(media.ownVideo, isFalse);
    });

    test('the archive video is no legacy print\'s once a print holds it', () {
      final holder = _run(2, photos: const [], timelapse: 'archive/5/old.mp4');
      final legacy = _run(1);
      final media = runMedia(archive, [holder, legacy], legacy);

      expect(media.archiveVideo, isFalse);
      expect(runMedia(archive, [holder, legacy], holder).ownVideo, isTrue);
    });

    test('a print with its own list never borrows the archive video', () {
      final run = _run(2, photos: const []);

      expect(runMedia(archive, [run], run).archiveVideo, isFalse);
    });
  });

  group('figures against the estimate', () {
    final ran = formatSeconds(pl, 3780);
    final est = formatSeconds(pl, 3600);
    test('a finished print by how far it ran from it', () {
      expect(estimateDelta(3780, 3600), '+5%');
      expect(estimateDelta(3420, 3600), '-5%');
      expect(estimateDelta(3600, 3600), '0%');
      expect(
        runTimeText(pl, _run(1)),
        pl.archiveRunTimeVsEstimate(ran, est, '+5%'),
      );
    });

    test('one that stopped by how far it got', () {
      expect(
        runTimeText(pl, _run(1, status: 'failed', duration: 1200)),
        pl.archiveRunTimeOf(formatSeconds(pl, 1200), est),
      );
    });

    test('an unmeasured time gets a tilde and no percentage', () {
      expect(
        runTimeText(pl, _run(1, unmeasured: true)),
        pl.archiveRunWithEstimate('~$ran', est),
      );
    });

    test('no estimate, no time, a zero estimate', () {
      expect(runTimeText(pl, _run(1, estimate: null)), ran);
      expect(runTimeText(pl, _run(1, duration: null)), isNull);
      expect(runTimeText(pl, _run(1, duration: 0)), isNull);
      expect(runTimeText(pl, _run(1, estimate: 0)), ran);
    });

    test('grams with and without their estimate', () {
      expect(runGramsText(pl, _run(1)), '48.1 g');
      expect(
        runGramsText(pl, _run(1, estimateGrams: 50)),
        pl.archiveRunWithEstimate('48.1 g', '50.0 g'),
      );
      expect(runGramsText(pl, _run(1, grams: null)), isNull);
    });
  });

  group('section', () {
    Future<void> pump(
      WidgetTester tester,
      List<PrintLogEntry> runs, {
      Archive archive = _archive,
      List<int> plates = const [],
      double textScale = 1.0,
      List<List<String>>? photosOpened,
      List<int?>? videosOpened,
      List<int?>? reprinted,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          retry: neverRetry,
          overrides: [
            noServerProfileOverride,
            currencySymbolProvider.overrideWithValue('€'),
            archiveRunsProvider.overrideWith((ref, id) async => runs),
            plateListProvider.overrideWith(
              (ref, key) async => PlateList(
                plates: [for (final i in plates) PlateInfo(index: i)],
              ),
            ),
          ],
          child: plApp(
            Scaffold(
              body: SingleChildScrollView(
                child: ArchiveRunsSection(
                  archive: archive,
                  onPhotos: (p) => photosOpened?.add(p),
                  onVideo: (r) => videosOpened?.add(r),
                  onReprint: (p) => reprinted?.add(p),
                ),
              ),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lists every print with its status and verdict', (
      tester,
    ) async {
      await pump(
        tester,
        [
          _run(3, plateId: 2, verdict: PrintVerdict.reject),
          _run(2, plateId: 1, verdict: PrintVerdict.good),
          _run(1, plateId: 2, status: 'failed'),
        ],
        plates: const [1, 2],
      );

      expect(byLogId('archive.run'), findsNWidgets(3));
      expect(find.text(pl.outcomeRejected), findsOneWidget);
      expect(find.text(pl.outcomeGoodPart), findsOneWidget);
      expect(find.text(pl.printLogStatusFailed), findsOneWidget);
      expect(find.textContaining(pl.archiveRunPlate(2)), findsWidgets);
    });

    testWidgets('a plate chip narrows the list, and says when it is empty', (
      tester,
    ) async {
      await pump(
        tester,
        [_run(3, plateId: 2), _run(2, plateId: 1)],
        plates: const [1, 2, 3],
      );

      await tester.tap(find.widgetWithText(ChoiceChip, pl.archiveRunPlate(1)));
      await tester.pumpAndSettle();
      expect(byLogId('archive.run'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, pl.archiveRunPlate(3)));
      await tester.pumpAndSettle();
      expect(byLogId('archive.run'), findsNothing);
      expect(find.text(pl.archiveRunsPlateEmpty), findsOneWidget);

      await tester.tap(find.text(pl.archiveRunsAllPlates));
      await tester.pumpAndSettle();
      expect(byLogId('archive.run'), findsNWidgets(2));
    });

    testWidgets('a single-plate file has no plate chips', (tester) async {
      await pump(tester, [_run(1)], plates: const [1]);

      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('an archive printed before the log names its one outcome', (
      tester,
    ) async {
      await pump(tester, const []);

      expect(
        find.text(pl.archiveRunsBeforeLog(pl.printLogStatusCompleted)),
        findsOneWidget,
      );
    });

    testWidgets('a file never printed says so', (tester) async {
      await pump(
        tester,
        const [],
        archive: _archive.copyWith(status: 'archived'),
      );

      expect(find.text(pl.archiveRunsEmpty), findsOneWidget);
    });

    testWidgets('a tap opens the print onto its facts and media', (
      tester,
    ) async {
      final photos = <List<String>>[];
      final videos = <int?>[];
      await pump(
        tester,
        [
          _run(
            2,
            photos: const ['finish_2.jpg'],
            timelapse: 'v.mp4',
            notes: 'Lids fit',
            failureReason: 'warping',
          ),
        ],
        photosOpened: photos,
        videosOpened: videos,
      );
      expect(find.text('Lids fit'), findsNothing);

      await tester.tap(byLogId('archive.run'));
      await tester.pumpAndSettle();

      expect(find.text('Lids fit'), findsOneWidget);
      expect(find.text(pl.failureReasonWarping), findsOneWidget);
      expect(find.text('morgan'), findsOneWidget);
      await tester.tap(byLogId('archive.run.photos'));
      await tester.tap(byLogId('archive.run.video'));
      expect(photos, [
        ['finish_2.jpg'],
      ]);
      expect(videos, [2]);
    });

    testWidgets('reprint this print starts on the plate it ran', (
      tester,
    ) async {
      final reprinted = <int?>[];
      await pump(
        tester,
        [_run(2, plateId: 3), _run(1)],
        archive: _archive.copyWith(plateId: 2, printTimeSeconds: 3600),
        reprinted: reprinted,
      );

      await tester.tap(byLogId('archive.run').first);
      await tester.pumpAndSettle();
      await tester.tap(byLogId('archive.run.reprint'));
      await tester.tap(byLogId('archive.run').last);
      await tester.pumpAndSettle();
      await tester.tap(byLogId('archive.run.reprint'));

      expect(reprinted, [
        3,
        2,
      ], reason: 'a print without a plate: the archive\'s');
    });

    testWidgets('a source file offers no reprint', (tester) async {
      await pump(tester, [
        _run(1),
      ], archive: _archive.copyWith(filename: 'a.3mf'));

      await tester.tap(byLogId('archive.run'));
      await tester.pumpAndSettle();

      expect(byLogId('archive.run.reprint'), findsNothing);
    });

    testWidgets('a legacy print plays the archive video', (tester) async {
      final videos = <int?>[];
      await pump(
        tester,
        [_run(1)],
        archive: _archive.copyWith(timelapsePath: 'archive/5/old.mp4'),
        videosOpened: videos,
      );

      await tester.tap(byLogId('archive.run'));
      await tester.pumpAndSettle();
      await tester.tap(byLogId('archive.run.video'));

      expect(videos, [null]);
    });

    for (final scale in const [1.0, 1.5, 2.0]) {
      testWidgets('an open print with every fact fits at text $scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await pump(
          tester,
          [
            _run(
              2,
              plateId: 2,
              verdict: PrintVerdict.reject,
              estimateGrams: 50,
              photos: const ['a.jpg', 'b.jpg'],
              timelapse: 'v.mp4',
              notes: 'A long note about the print that wraps over lines.',
              failureReason: 'spaghettiDetached',
            ),
          ],
          plates: const [1, 2, 3],
          textScale: scale,
        );

        await tester.tap(byLogId('archive.run'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text(pl.archiveRunVideo), findsOneWidget);
      });
    }
  });
}
