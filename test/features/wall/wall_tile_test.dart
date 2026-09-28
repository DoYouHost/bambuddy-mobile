import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/wall/wall_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

const _printer = Printer(id: 1, name: 'X1C-01');

const _printing = PrinterStatus(
  id: 1,
  connected: true,
  state: 'RUNNING',
  progress: 64,
  remainingTime: 72,
  layerNum: 142,
  totalLayers: 220,
);

/// A fault the card would list: it carries a message, and a numeric code whose
/// short form is `0300_8004`.
const _fault = HmsError(
  code: '0x8004',
  attr: 0x03008004,
  severity: 2,
  message: 'Filament ran out',
);

Future<void> pumpTile(
  WidgetTester tester,
  PrinterStatus? status, {
  Size size = const Size(260, 170),
}) => pumpPhone(
  tester,
  Center(
    child: SizedBox.fromSize(
      size: size,
      child: WallTile(
        item: PrinterWithStatus(printer: _printer, status: status),
      ),
    ),
  ),
);

void main() {
  testWidgets('a print shows its state, percent, time left and layer', (
    tester,
  ) async {
    await pumpTile(tester, _printing);

    expect(find.text('X1C-01'), findsOneWidget);
    expect(find.text('RUNNING'), findsOneWidget);
    expect(find.text('64%'), findsOneWidget);
    expect(find.text('L 142/220'), findsOneWidget);
    expect(find.text('1h 12min'), findsOneWidget);
  });

  testWidgets('a paused print keeps its progress', (tester) async {
    await pumpTile(
      tester,
      const PrinterStatus(
        id: 1,
        connected: true,
        state: 'PAUSE',
        progress: 18,
        remainingTime: 220,
        layerNum: 31,
        totalLayers: 190,
      ),
    );

    expect(find.text('PAUSE'), findsOneWidget);
    expect(find.text('18%'), findsOneWidget);
  });

  testWidgets('an idle printer shows its state and no print', (tester) async {
    await pumpTile(
      tester,
      const PrinterStatus(id: 1, connected: true, state: 'IDLE'),
    );

    expect(find.text('IDLE'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(find.textContaining('L '), findsNothing);
  });

  testWidgets('a fault names its code on the tile', (tester) async {
    await pumpTile(
      tester,
      const PrinterStatus(
        id: 1,
        connected: true,
        state: 'PAUSE',
        progress: 18,
        remainingTime: 220,
        hmsErrors: [_fault],
      ),
    );

    expect(find.text('0300_8004'), findsOneWidget);
  });

  testWidgets('a printer the server cannot reach reads offline', (
    tester,
  ) async {
    await pumpTile(
      tester,
      const PrinterStatus(
        id: 1,
        connected: false,
        state: 'RUNNING',
        progress: 64,
        remainingTime: 72,
        hmsErrors: [_fault],
      ),
    );

    expect(find.text('OFFLINE'), findsOneWidget);
    expect(find.text('64%'), findsNothing, reason: 'the last frame is stale');
    expect(find.text('0300_8004'), findsNothing);
    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
  });

  testWidgets('a printer with no status yet reads offline too', (tester) async {
    await pumpTile(tester, null);

    expect(find.text('OFFLINE'), findsOneWidget);
  });

  testWidgets('a disconnect is believed only after the card\'s 15 s', (
    tester,
  ) async {
    await pumpTile(tester, _printing);
    await pumpTile(
      tester,
      const PrinterStatus(id: 1, connected: false, state: 'RUNNING'),
    );
    expect(find.text('OFFLINE'), findsNothing);

    await tester.pump(const Duration(seconds: 15));
    expect(find.text('OFFLINE'), findsOneWidget);
  });

  testWidgets('a long name and a fault fit the smallest tile', (tester) async {
    await pumpTile(
      tester,
      const PrinterStatus(
        id: 1,
        connected: true,
        state: 'RUNNING',
        progress: 64,
        remainingTime: 72,
        layerNum: 142,
        totalLayers: 220,
        hmsErrors: [_fault],
      ),
      size: const Size(200, 120),
    );

    expect(tester.takeException(), isNull);
  });
}
