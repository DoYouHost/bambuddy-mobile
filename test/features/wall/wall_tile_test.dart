import 'dart:async';
import 'dart:io';

import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/camera/camera_view.dart';
import 'package:bambuddy_mobile/features/wall/wall_camera.dart';
import 'package:bambuddy_mobile/features/wall/wall_tile.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/tiny_jpeg.dart';
import '../../helpers.dart';

const _printer = Printer(id: 1, name: 'X1C-01');

/// A camera server scripted per route: the stream and the snapshot each answer
/// with their own status, and a snapshot that succeeds carries a real JPEG.
///
/// One instance for the whole file, re-scripted per test: `NetworkImage` keeps a
/// single shared `HttpClient` for the process, so a server installed by a later
/// test would never be asked for a snapshot.
class _CameraServer extends HttpOverrides {
  int stream = 404;
  int snapshot = 404;

  /// Every URL asked for, in order.
  final asked = <Uri>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) => _Client(this);
}

class _Client implements HttpClient {
  _Client(this._server);

  final _CameraServer _server;

  @override
  set connectionTimeout(Duration? value) {}

  @override
  set autoUncompress(bool value) {}

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    _server.asked.add(url);
    final snapshot = url.path.endsWith('/snapshot');
    final status = snapshot ? _server.snapshot : _server.stream;
    return _Request(
      _Response(status, snapshot && status == 200 ? tinyJpeg() : const []),
    );
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this._response);

  final HttpClientResponse _response;

  @override
  Future<HttpClientResponse> close() async => _response;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.statusCode, this._body);

  @override
  final int statusCode;

  final List<int> _body;

  @override
  int get contentLength => _body.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      (_body.isEmpty
              ? const Stream<List<int>>.empty()
              : Stream<List<int>>.value(_body))
          .listen(onData, onError: onError, onDone: onDone);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _server = _CameraServer();

/// Scripts the camera server's answers for the rest of the test.
_CameraServer _serve({required int stream, int snapshot = 404}) {
  final previous = HttpOverrides.current;
  HttpOverrides.global = _server
    ..stream = stream
    ..snapshot = snapshot
    ..asked.clear();
  addTearDown(() => HttpOverrides.global = previous);
  return _server;
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

    testWidgets('a busy camera shows its snapshot under a marker', (
      tester,
    ) async {
      // 503 is the server's answer while the camera is busy: a status, which
      // the stream's own backoff does not retry.
      _serve(stream: 503, snapshot: 200);

      await pumpTile(tester, _printing, camera: true);
      await tester.pump();
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();

      expect(find.text('Podgląd wstrzymany'), findsOneWidget);
      final shot = tester.widget<RawImage>(find.byType(RawImage).first);
      expect(shot.image, isNotNull, reason: 'the snapshot was decoded');
    });

    testWidgets('asks for a refused stream again after a minute', (
      tester,
    ) async {
      final server = _serve(stream: 503);
      int streams() =>
          server.asked.where((u) => u.path.endsWith('/stream')).length;

      await pumpTile(tester, _printing, camera: true);
      await tester.pump();
      await tester.pump();
      expect(streams(), 1);

      await tester.pump(WallCamera.restreamAfter);
      await tester.pump();
      expect(streams(), 2);
    });

    testWidgets('a snapshot refused with 401 has the token minted again', (
      tester,
    ) async {
      _serve(stream: 404, snapshot: 401);
      var mints = 0;

      await pumpPhone(
        tester,
        Center(
          child: SizedBox(
            width: 260,
            height: 170,
            child: WallTile(
              item: PrinterWithStatus(printer: _printer, status: _printing),
              camera: true,
            ),
          ),
        ),
        overrides: [
          fakeServerProfileOverride(),
          cameraTokenProvider.overrideWith((ref) async => 'tok${++mints}'),
        ],
      );
      await tester.pump();
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }

      expect(mints, 2);
    });

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
