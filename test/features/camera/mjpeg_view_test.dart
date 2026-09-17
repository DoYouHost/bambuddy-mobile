import 'dart:async';
import 'dart:io';

import 'package:bambuddy_mobile/features/camera/mjpeg_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/tiny_jpeg.dart';

/// The response of one attempt. Only what the view touches is real; a member it
/// starts calling later lands in `noSuchMethod`, which throws rather than
/// answering null.
class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this.statusCode, this._body);

  @override
  final int statusCode;

  final Stream<List<int>> _body;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _body.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this._response);

  final HttpClientResponse _response;

  @override
  Future<HttpClientResponse> close() async => _response;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Counts the connections the view opens and hands each one a body the test
/// drives. Every attempt gets its own controller, so a test can end the second
/// stream without touching the first.
class _FakeHttpOverrides extends HttpOverrides {
  final attempts = <StreamController<List<int>>>[];
  int status = 200;

  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeClient(this);
}

class _FakeClient implements HttpClient {
  _FakeClient(this._overrides);

  final _FakeHttpOverrides _overrides;

  @override
  set connectionTimeout(Duration? value) {}

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    final body = StreamController<List<int>>();
    _overrides.attempts.add(body);
    return _FakeRequest(_FakeResponse(_overrides.status, body.stream));
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeHttpOverrides http;
  HttpOverrides? previous;

  setUp(() {
    http = _FakeHttpOverrides();
    previous = HttpOverrides.current;
    HttpOverrides.global = http;
  });

  tearDown(() {
    HttpOverrides.global = previous;
  });

  /// The view under test, with a backoff in milliseconds so a test does not
  /// have to sit out the real one.
  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MjpegView(
          url: 'http://printer.test/stream?token=t',
          loading: (_) => const Text('connecting'),
          error: (_, _) => const Text('failed'),
          reconnectDelays: const [
            Duration(milliseconds: 100),
            Duration(milliseconds: 200),
            Duration(milliseconds: 400),
          ],
        ),
      ),
    );
    // The request is a couple of async gaps away from the first byte.
    await tester.pump();
    await tester.pump();
  }

  /// Fails the stream the view is reading.
  ///
  /// Through `runAsync`, because an error crossing `Stream.timeout` into an
  /// `async*` generator is one of the things fake async does not carry: the
  /// frames themselves arrive on a plain pump, an error does not (a device
  /// proves the real thing in `integration_test/camera_stream_test.dart`).
  Future<void> drop(WidgetTester tester) async {
    final failing = http.attempts.last;
    await tester.runAsync(() async {
      failing.addError(const SocketException('gone'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
  }

  /// Ends every stream the test opened and takes the view down.
  ///
  /// The view closes the socket and lets the resulting error land rather than
  /// cancelling its subscription (see `_stop`), so with a transport that has no
  /// socket to close nothing ends the stream — and its idle timer outlives the
  /// test, which the binding reports as a leak.
  Future<void> quiesce(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      for (final attempt in http.attempts) {
        // Not awaited: the attempt a status answered was never listened to, and
        // closing a controller nobody reads never completes.
        if (!attempt.isClosed) unawaited(attempt.close());
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
  }

  testWidgets('reconnects after the stream drops, backing off as it goes', (
    tester,
  ) async {
    await show(tester);
    expect(http.attempts, hasLength(1));

    Future<void> dropAndWait(Duration delay) async {
      final before = http.attempts.length;
      await drop(tester);
      expect(find.text('failed'), findsOneWidget);
      // One tick short of the wait: a reconnect that fires here is one the
      // backoff is not applying.
      await tester.pump(delay - const Duration(milliseconds: 1));
      expect(http.attempts, hasLength(before));
      await tester.pump(const Duration(milliseconds: 2));
      await tester.pump();
      expect(
        http.attempts,
        hasLength(before + 1),
        reason: 'no reconnect after $delay',
      );
    }

    await dropAndWait(const Duration(milliseconds: 100));
    await dropAndWait(const Duration(milliseconds: 200));
    await dropAndWait(const Duration(milliseconds: 400));
    // The last delay repeats rather than growing without end.
    await dropAndWait(const Duration(milliseconds: 400));
    await quiesce(tester);
  });

  testWidgets('a frame puts the backoff back to the start', (tester) async {
    await show(tester);

    await drop(tester);
    await tester.pump(const Duration(milliseconds: 101));
    await tester.pump();
    expect(http.attempts, hasLength(2));

    http.attempts.last.add(tinyJpeg());
    await tester.pump();
    await tester.pump();
    expect(find.text('failed'), findsNothing);

    await drop(tester);
    // The first delay again, not the second one the next failure in a row
    // would otherwise take.
    await tester.pump(const Duration(milliseconds: 101));
    await tester.pump();
    expect(http.attempts, hasLength(3));
    await quiesce(tester);
  });

  testWidgets('leaves a status for the caller to act on', (tester) async {
    http.status = 401;
    await show(tester);

    expect(find.text('failed'), findsOneWidget);
    // A re-mint changes the URL and starts a stream that way. Retrying on a
    // timer here would replay the stale token at the server every few seconds.
    await tester.pump(const Duration(seconds: 30));
    expect(http.attempts, hasLength(1));
    await quiesce(tester);
  });

  testWidgets('stops reconnecting once the view is gone', (tester) async {
    await show(tester);
    await drop(tester);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 30));

    expect(http.attempts, hasLength(1));
  });

  testWidgets('drops the frame it stopped showing from the image cache', (
    tester,
  ) async {
    await show(tester);
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();

    for (var i = 0; i < 5; i++) {
      http.attempts.last.add(tinyJpeg());
      await tester.pump();
    }

    // Every frame is a cache entry of its own — the key is the identity of the
    // byte list — so without the eviction this is five, and on a real stream it
    // is however many decoded frames fit in 100 MB.
    expect(
      cache.pendingImageCount + cache.liveImageCount,
      lessThanOrEqualTo(2),
    );
    await quiesce(tester);
  });
}
