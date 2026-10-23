import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/features/controller/controller_files.dart';
import 'package:bambuddy_mobile/features/controller/controller_prints.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';
import '../archive/archive_fakes.dart';
import '../queue/queue_fakes.dart';
import 'controller_harness.dart';

/// The Prints tab's rail: which view it shows, and that the choice outlives a
/// visit to another tab, as the library's folder does.
void main() {
  Future<void> pump(WidgetTester tester) async {
    await pumpControllerScreen(tester);
    await tester.tap(byLogId('controller.tab_prints'));
    await settle(tester);
  }

  testWidgets('the tab opens on Files, and the rail switches the view', (
    tester,
  ) async {
    await pump(tester);

    expect(find.byType(ControllerFiles), findsOneWidget);
    for (final view in ControllerPrintsView.values) {
      expect(byLogId(view.logId), findsOneWidget);
    }

    await tester.tap(byLogId(ControllerPrintsView.queue.logId));
    await settle(tester);

    expect(find.byType(ControllerFiles), findsNothing);
  });

  testWidgets('another tab and back keeps the chosen view', (tester) async {
    await pump(tester);
    await tester.tap(byLogId(ControllerPrintsView.archive.logId));
    await settle(tester);

    await tester.tap(byLogId('controller.tab_heat'));
    await settle(tester);
    await tester.tap(byLogId('controller.tab_prints'));
    await settle(tester);

    expect(find.byType(ControllerFiles), findsNothing);
    final archive = tester.widget<ControllerPrints>(
      find.byType(ControllerPrints),
    );
    expect(archive.view, ControllerPrintsView.archive);
  });

  group('fits', () {
    const long = 'Wspornik półki z długą nazwą pliku, wersja ostateczna v7';
    final queue = [
      QueueItem.fromJson({
        ...readFixture('queue_item.json') as Map<String, dynamic>,
        'id': 11,
        'archive_name': long,
        'status': 'pending',
        'printer_id': null,
        'target_model': 'P1S',
        'manual_start': true,
        'created_by_username': 'operator-zmiany-nocnej',
        'waiting_reason': 'Waiting for filament: PETG-CF Black',
      }),
    ];
    final archive = [
      for (var id = 1; id <= 8; id++)
        Archive(
          id: id,
          filename: 'part.gcode.3mf',
          status: id.isEven ? 'failed' : 'completed',
          printName: '$long $id',
          slicedForModel: 'X1C',
          plateId: 3,
          printTimeSeconds: 40000,
          filamentUsedGrams: 1234.5,
        ),
    ];

    for (final size in const [
      landscapeRedmi,
      landscapePixel,
      Size(740, 320),
      Size(1280, 800),
    ]) {
      for (final textScale in const [1.0, 1.3]) {
        testWidgets('at ${size.width.round()}x${size.height.round()}, '
            'text x$textScale, the Queue and the Archive and their dialogs', (
          tester,
        ) async {
          tester.platformDispatcher.textScaleFactorTestValue = textScale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await pumpControllerScreen(
            tester,
            size: size,
            overrides: [
              queueProvider.overrideWith(() => FakeQueue(queue)),
              archiveRepositoryProvider.overrideWithValue(
                FakeArchives(rows: archive),
              ),
            ],
          );

          await openPrintsView(tester, ControllerPrintsView.queue);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text(long).first);
          await settle(tester);
          expect(tester.takeException(), isNull);
          await tester.tap(byLogId('controller.queue.dialog.close'));
          await settle(tester);

          await tester.tap(byLogId(ControllerPrintsView.archive.logId));
          await settle(tester);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('$long 2'));
          await settle(tester);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
