import 'dart:async';
import 'dart:io';

import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/camera/camera_view.dart';
import 'package:bambuddy_mobile/features/wall/wall_tile.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

const _printer = Printer(id: 1, name: 'X1C-01');

/// A server that answers every camera request with 404: the stream is refused,
/// which is a failure the backoff does not retry, and so is every snapshot.
class _RefusingHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _RefusingClient();
}

class _RefusingClient implements HttpClient {
  @override
  set connectionTimeout(Duration? value) {}

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _RefusedRequest();

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RefusedRequest implements HttpClientRequest {
  @override
  Future<HttpClientResponse> close() async => _RefusedResponse();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RefusedResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  int get statusCode => 404;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => const Stream<List<int>>.empty().listen(onData, onDone: onDone);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
  Printer printer = _printer,
  bool camera = false,
}) => pumpPhone(
  tester,
  Center(
    child: SizedBox.fromSize(
      size: size,
      child: WallTile(
        item: PrinterWithStatus(printer: printer, status: status),
        camera: camera,
      ),
    ),
  ),
  overrides: [
    fakeServerProfileOverride(),
    cameraTokenProvider.overrideWith((ref) async => 'tok'),
  ],
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

  testWidgets(
    'a connected printer with no state reads online, as on the card',
    (tester) async {
      await pumpTile(tester, const PrinterStatus(id: 1, connected: true));

      expect(find.text('ONLINE'), findsOneWidget);
    },
  );

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
      printer: const Printer(id: 1, name: 'Bambu Lab X1-Carbon Combo, shelf 3'),
    );

    expect(tester.takeException(), isNull);
  });

  group('with a camera', () {
    testWidgets('keeps the status on the picture, without the big percent', (
      tester,
    ) async {
      await pumpTile(tester, _printing, camera: true);
      await tester.pump();

      expect(byLogId('wall.tile'), findsOneWidget);
      expect(find.text('X1C-01'), findsOneWidget);
      expect(find.text('RUNNING'), findsOneWidget);
      expect(find.text('L 142/220'), findsOneWidget);
      expect(find.text('64%'), findsNothing);
    });

    testWidgets(
      'falls back to snapshots under a marker when the stream fails',
      (tester) async {
        final previous = HttpOverrides.current;
        HttpOverrides.global = _RefusingHttp();
        addTearDown(() => HttpOverrides.global = previous);

        await pumpTile(tester, _printing, camera: true);
        for (var i = 0; i < 5; i++) {
          await tester.pump();
        }

        expect(find.text('Podgląd wstrzymany'), findsOneWidget);
      },
    );

    testWidgets('opens the full-screen camera on a tap', (tester) async {
      await pumpTile(tester, _printing, camera: true);
      await tester.pump();

      await tester.tap(byLogId('wall.tile'));
      await tester.pumpAndSettle();

      expect(find.byType(CameraView), findsOneWidget);
    });

    testWidgets('an offline printer gets the status card, not a dead stream', (
      tester,
    ) async {
      await pumpTile(
        tester,
        const PrinterStatus(id: 1, connected: false),
        camera: true,
      );

      expect(byLogId('wall.tile'), findsNothing);
      expect(find.text('OFFLINE'), findsOneWidget);
    });
  });
}
