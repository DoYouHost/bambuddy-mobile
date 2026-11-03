import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/models/plate_list.dart';
import 'package:bambuddy_mobile/core/models/print_log_entry.dart';
import 'package:bambuddy_mobile/features/archive/archive_plates.dart';
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
  printTimeSeconds: 5400,
  runCount: 3,
  createdById: 7,
);

PrintLogEntry _run(
  int id, {
  required int plate,
  String status = 'completed',
  int duration = 1980,
  List<String> photos = const [],
  String? timelapse,
}) => PrintLogEntry(
  id: id,
  status: status,
  createdAt: DateTime.utc(2026, 11, id),
  startedAt: DateTime.utc(2026, 11, id, 10),
  plateId: plate,
  durationSeconds: duration,
  photos: photos,
  timelapsePath: timelapse,
);

const _plates = [
  PlateInfo(
    index: 1,
    objects: ['Dispenser body'],
    printTimeSeconds: 1800,
    filamentUsedGrams: 32.1,
    filaments: [(type: 'PLA', color: '#000000')],
  ),
  PlateInfo(index: 2, objects: ['Lid', 'Lid'], printTimeSeconds: 1800),
  PlateInfo(index: 3, name: 'Wall bracket'),
];

void main() {
  Future<({List<int> printed, List<List<String>> photos, List<int?> videos})>
  pump(
    WidgetTester tester, {
    List<PrintLogEntry>? runs,
    List<PlateInfo> plates = _plates,
    Archive archive = _archive,
    CurrentUser? user,
    double textScale = 1.0,
  }) async {
    final printed = <int>[];
    final photos = <List<String>>[];
    final videos = <int?>[];
    await tester.pumpWidget(
      ProviderScope(
        retry: neverRetry,
        overrides: [
          noServerProfileOverride,
          currentUserOverride(user),
          currencySymbolProvider.overrideWithValue('€'),
          archiveRunsProvider.overrideWith(
            (ref, id) async =>
                runs ??
                [
                  _run(3, plate: 2, photos: const ['finish_3.jpg']),
                  _run(2, plate: 1, timelapse: 'v.mp4'),
                  _run(1, plate: 2, status: 'failed', duration: 600),
                ],
          ),
          plateListProvider.overrideWith(
            (ref, key) async => PlateList(plates: plates),
          ),
        ],
        child: plApp(
          Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  ArchivePlatesSection(
                    archive: archive,
                    onPhotos: photos.add,
                    onVideo: videos.add,
                    onPrintPlate: printed.add,
                  ),
                  ArchiveRunsSection(
                    archive: archive,
                    onPhotos: photos.add,
                    onVideo: videos.add,
                    onReprint: (_) {},
                  ),
                ],
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
    return (printed: printed, photos: photos, videos: videos);
  }

  Finder card(int plate) => find
      .ancestor(
        of: find.text(pl.archiveRunPlate(plate)).first,
        matching: find.byType(Container),
      )
      .first;

  testWidgets('a card per plate with its contents, estimate and filaments', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text(pl.archivePlatesTitle), findsOneWidget);
    expect(find.text('Dispenser body'), findsOneWidget);
    expect(find.text('Lid, Lid'), findsOneWidget);
    expect(find.text('Wall bracket'), findsOneWidget);
    expect(find.textContaining('32.1 g'), findsOneWidget);
    expect(find.text('PLA'), findsOneWidget);
  });

  testWidgets('how each plate\'s prints went, and the last against it', (
    tester,
  ) async {
    await pump(tester);

    final plate2 = card(2);
    expect(
      find.descendant(of: plate2, matching: find.text(pl.archiveGoodCount(1))),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: plate2,
        matching: find.text(pl.archiveFailedCount(1)),
      ),
      findsOneWidget,
    );
    // 1980 s against 1800 s is 10 % over.
    expect(
      find.descendant(
        of: plate2,
        matching: find.text(pl.archivePlateLastVsEstimate('+10%')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a single-plate file has no plate cards', (tester) async {
    await pump(tester, plates: const [PlateInfo(index: 1)]);

    expect(find.text(pl.archivePlatesTitle), findsNothing);
  });

  testWidgets('print this plate opens the form on that plate', (tester) async {
    final opened = await pump(tester);

    await tester.tap(byLogId('archive.plate.print').at(2));

    expect(opened.printed, [3]);
  });

  testWidgets('a source file is not printed from a plate card', (tester) async {
    await pump(
      tester,
      archive: _archive.copyWith(filename: 'bag.3mf', printTimeSeconds: 0),
    );

    expect(byLogId('archive.plate.print'), findsNothing);
  });

  testWidgets('a refused reprint leaves the plate buttons off', (tester) async {
    await pump(
      tester,
      user: const CurrentUser(
        id: 1,
        username: 'viewer',
        isAdmin: false,
        permissions: {Permissions.queueCreate},
      ),
    );

    final button = tester.widget<ButtonStyleButton>(
      find.descendant(
        of: byLogId('archive.plate.print').first,
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('show its prints narrows the history to that plate', (
    tester,
  ) async {
    await pump(tester);
    expect(byLogId('archive.run'), findsNWidgets(3));

    await tester.ensureVisible(byLogId('archive.plate.show_prints').at(1));
    await tester.tap(byLogId('archive.plate.show_prints').at(1));
    await tester.pumpAndSettle();

    expect(byLogId('archive.run'), findsNWidgets(2));
    final chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, pl.archiveRunPlate(2)),
    );
    expect(chip.selected, isTrue);
  });

  testWidgets('a plate without prints cannot show them', (tester) async {
    await pump(tester);

    final button = tester.widget<ButtonStyleButton>(
      find.descendant(
        of: byLogId('archive.plate.show_prints').at(2),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('a plate opens its prints\' photos and its newest video', (
    tester,
  ) async {
    final opened = await pump(tester);

    await tester.tap(byLogId('archive.plate.photos'));
    await tester.tap(byLogId('archive.plate.video'));

    expect(opened.photos, [
      ['finish_3.jpg'],
    ]);
    expect(opened.videos, [2], reason: 'plate 1\'s print holds its own video');
  });

  for (final scale in const [1.0, 1.5, 2.0]) {
    testWidgets('the plate cards fit at text $scale', (tester) async {
      tester.view.physicalSize = const Size(360, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pump(tester, textScale: scale);

      expect(tester.takeException(), isNull);
      expect(byLogId('archive.plate.print'), findsNWidgets(3));
    });
  }
}
