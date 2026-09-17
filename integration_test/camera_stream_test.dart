import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bambuddy_mobile/features/camera/mjpeg_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/fixtures/tiny_jpeg.dart';

/// An MJPEG server on the device's own loopback. The point of running these on
/// a device at all: the frames are read off a real socket by the real Dio
/// adapter and decoded by the real codec, none of which a mocked adapter or the
/// widget-test binding exercises.
class _CameraServer {
  late final HttpServer _server;

  /// The app's request arrives a few event-loop turns after the widget mounts,
  /// so a frame pushed straight away would be written to nothing.
  final _connected = Completer<HttpResponse>();

  /// Completes when writing to the client fails, which is how the server learns
  /// the app hung up.
  final _hungUp = Completer<void>();

  String get url => 'http://127.0.0.1:${_server.port}/stream';

  Future<void> start({int status = 200}) async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      final response = request.response;
      if (status != 200) {
        response.statusCode = status;
        await response.close();
        return;
      }
      response.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/x-mixed-replace; boundary=frame',
      );
      if (!_connected.isCompleted) _connected.complete(response);
    });
  }

  Future<void> push(Uint8List frame) async {
    final response = await _connected.future.timeout(
      const Duration(seconds: 10),
    );
    try {
      response.add('--frame\r\nContent-Type: image/jpeg\r\n\r\n'.codeUnits);
      response.add(frame);
      response.add('\r\n'.codeUnits);
      // Bounded: once the app is gone the flush does not always throw — it can
      // simply never complete, and an unbounded await there is a test that
      // hangs until the runner kills it four minutes later.
      await response.flush().timeout(const Duration(milliseconds: 500));
    } on Object {
      if (!_hungUp.isCompleted) _hungUp.complete();
    }
  }

  Timer? _pusher;

  /// What a camera does: a frame every so often, until the socket goes away.
  /// A single write is not the same test — it can sit in a buffer.
  void pushEvery(Uint8List frame) {
    _pusher = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => push(frame),
    );
  }

  Future<void> endStream() async {
    _pusher?.cancel();
    await (await _connected.future).close();
  }

  Future<bool> clientHungUp() async {
    // Nothing tells the server about a closed socket until it writes to it, and
    // each write is bounded, so this answers in a few seconds either way.
    for (var i = 0; i < 20 && !_hungUp.isCompleted; i++) {
      await push(tinyJpeg());
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return _hungUp.isCompleted;
  }

  Future<void> dispose() {
    _pusher?.cancel();
    return _server.close(force: true);
  }
}

/// `pumpAndSettle` never returns on a live stream — there is always another
/// frame — so the wait is bounded by hand.
Object? lastError;

Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
    // A real delay as well as a pump: the socket reads arrive on the event
    // loop, and a loop of pumps alone does not give it a turn.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('timed out waiting for $finder (last error: $lastError)');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late _CameraServer server;
  Object? reportedError;

  tearDown(() async {
    await server.dispose();
    reportedError = null;
  });

  Future<void> show(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: MjpegView(
        url: server.url,
        loading: (_) => const CircularProgressIndicator(),
        error: (_, error) {
          reportedError = error;
          lastError = error;
          return const Text('failed', textDirection: TextDirection.ltr);
        },
      ),
    ),
  );

  testWidgets('paints a frame read off a real socket', (tester) async {
    server = _CameraServer();
    await server.start();
    await show(tester);
    await pumpUntil(tester, find.byType(CircularProgressIndicator));

    server.pushEvery(tinyJpeg());

    await pumpUntil(tester, find.byType(Image));
    expect(reportedError, isNull);
  });

  testWidgets('hands the caller the 401 that a stale token gets', (
    tester,
  ) async {
    server = _CameraServer();
    await server.start(status: 401);
    await show(tester);

    await pumpUntil(tester, find.text('failed'));
    expect(reportedError, isA<MjpegHttpStatus>());
    expect((reportedError! as MjpegHttpStatus).status, 401);
  });

  testWidgets('reports a server that closes the stream', (tester) async {
    server = _CameraServer();
    await server.start();
    await show(tester);
    await pumpUntil(tester, find.byType(CircularProgressIndicator));

    server.pushEvery(tinyJpeg());
    await pumpUntil(tester, find.byType(Image));
    await server.endStream();

    await pumpUntil(tester, find.text('failed'));
    expect(reportedError, isA<MjpegStreamEnded>());
  });

  testWidgets(
    'closes the socket when the view goes away',
    timeout: const Timeout(Duration(seconds: 60)),
    (tester) async {
      server = _CameraServer();
      await server.start();
      await show(tester);
      await pumpUntil(tester, find.byType(CircularProgressIndicator));
      server.pushEvery(tinyJpeg());
      await pumpUntil(tester, find.byType(Image));

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(milliseconds: 100));

      // A view that keeps its connection after being disposed is a camera stream
      // running behind whatever screen the user opened next.
      expect(await server.clientHungUp(), isTrue);
    },
  );
}
