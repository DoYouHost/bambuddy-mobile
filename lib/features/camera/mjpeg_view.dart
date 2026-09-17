import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'mjpeg_frames.dart';

/// The server answered, but not with a stream we can show — the status is what
/// tells an expired token from a printer that is not there.
class MjpegHttpStatus implements Exception {
  const MjpegHttpStatus(this.status);

  final int status;

  @override
  String toString() => 'MjpegHttpStatus($status)';
}

/// The server closed the stream without an error.
class MjpegStreamEnded implements Exception {
  const MjpegStreamEnded();

  @override
  String toString() => 'MjpegStreamEnded';
}

/// Renders an MJPEG stream (`multipart/x-mixed-replace`).
///
/// The connection lives exactly as long as the widget is mounted and the app is
/// in the foreground; going to the background stops the socket but keeps the
/// last frame on screen, so returning to it does not flash a spinner.
///
/// A connection that drops is retried on its own, on the backoff in
/// [reconnectDelays]: a two-second Wi-Fi blip is not something the user should
/// have to tap a button about, and the view this replaced (`flutter_mjpeg` with
/// `isLive`) healed from one by itself. A response with an HTTP status is the
/// exception — the server answered, and what to do about a 401 is the caller's
/// policy, not a delay.
///
/// While that retry is working the last frame stays on screen under
/// [retrying], and [error] waits: a blip is over before anyone has read an
/// error message, and swapping the picture for one costs the user the view they
/// came for. Once the backoff has been through [reconnectDelays] once the drop
/// has outlived a blip, and [error] takes over — as it does immediately when
/// there is no frame to keep.
///
/// **On `HttpClient` rather than the app's Dio.** Dio returns the status and the
/// headers of a `multipart/x-mixed-replace` response and then never emits a byte
/// of the body — proved on a device against a local MJPEG server in
/// `integration_test/camera_stream_test.dart`, where the same server feeds an
/// `HttpClient` frame after frame. Nothing Dio adds is needed here anyway: the
/// stream is authorised by the `?token=` in the URL, not by an interceptor.
class MjpegView extends StatefulWidget {
  const MjpegView({
    super.key,
    required this.url,
    required this.loading,
    required this.error,
    required this.retrying,
    this.fit,
    this.idleTimeout = const Duration(seconds: 15),
    this.reconnectDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
    ],
  });

  final String url;
  final WidgetBuilder loading;
  final Widget Function(BuildContext context, Object error) error;

  /// Painted over the last frame while a dropped stream is being retried,
  /// aligned to the top corner. Without it a frozen picture is indisting-
  /// uishable from a live one that happens to be of a still printer.
  final WidgetBuilder retrying;

  final BoxFit? fit;

  /// How long a live stream may say nothing before it counts as dead. A remote
  /// connection is slow, not silent — 15 s is the same figure the app's HTTP
  /// client uses for a receive.
  final Duration idleTimeout;

  /// Waits before the first, second, … reconnect; the last one repeats for as
  /// long as the stream keeps failing. The counter is reset by a frame, so a
  /// connection that comes back and drops again starts over at the front.
  /// Empty switches the retry off.
  final List<Duration> reconnectDelays;

  @override
  State<MjpegView> createState() => _MjpegViewState();
}

class _MjpegViewState extends State<MjpegView> with WidgetsBindingObserver {
  /// Also the identity of the current attempt: an event from an older one —
  /// the error a closed socket raises, above all — is not this stream's news.
  HttpClient? _client;
  Uint8List? _frame;
  Object? _error;
  Timer? _reconnect;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  @override
  void didUpdateWidget(MjpegView old) {
    super.didUpdateWidget(old);
    // A re-minted token changes the query, so the URL is what identifies a
    // stream here, not the widget position.
    if (old.url != widget.url) {
      _stop();
      _evict(_frame);
      _frame = null;
      _error = null;
      _attempt = 0;
      unawaited(_start());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Also when the stream is showing an error: coming back to the screen is
      // as clear a "try again" as the button is, and the blip that broke it is
      // usually over by now.
      _attempt = 0;
      if (_client == null) unawaited(_start());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    _evict(_frame);
    super.dispose();
  }

  void _stop() {
    _reconnect?.cancel();
    _reconnect = null;
    // Force, because a live stream never ends on its own: without it the socket
    // stays open behind whatever screen the user opened next.
    //
    // The subscription is deliberately not cancelled. Closing the socket makes
    // the response stream raise "Connection closed while receiving data", and a
    // cancelled subscription leaves that error with nobody to hand it to — an
    // unhandled async error. Left listening, it lands in `_fail`, which drops
    // it because the client it came from is no longer the current one.
    _client?.close(force: true);
    _client = null;
  }

  Future<void> _start() async {
    // Every entry point here has already stopped, except the one that did not:
    // a resume while a retry is pending would otherwise leave the connection it
    // opens behind when the timer opens the next one, with nobody left holding
    // the socket to close it.
    _stop();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    _client = client;
    try {
      final response = await client
          .getUrl(Uri.parse(widget.url))
          .then((request) => request.close());
      if (!mounted || !identical(_client, client)) {
        client.close(force: true);
        return;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _fail(MjpegHttpStatus(response.statusCode), client);
        return;
      }
      mjpegFrames(response.timeout(widget.idleTimeout)).listen(
        (frame) {
          if (!mounted || !identical(_client, client)) return;
          _show(frame);
        },
        onError: (Object e) => _fail(e, client),
        onDone: () => _fail(const MjpegStreamEnded(), client),
      );
    } on Object catch (e) {
      _fail(e, client);
    }
  }

  void _show(Uint8List frame) {
    final previous = _frame;
    setState(() {
      _frame = frame;
      _error = null;
      _attempt = 0;
    });
    // `Image.memory` keys the image cache by the identity of the byte list, so
    // every frame is an entry of its own and a stream holds the cache at its
    // 100 MB ceiling — around a dozen decoded 1080p frames nothing will ever
    // ask for again. The widget keeps painting the one it is showing from its
    // own handle (that is what `gaplessPlayback` holds), not from the cache, so
    // dropping the entry does not take the picture with it.
    _evict(previous);
  }

  void _evict(Uint8List? frame) {
    if (frame != null) unawaited(MemoryImage(frame).evict());
  }

  void _fail(Object error, HttpClient from) {
    if (!mounted || !identical(_client, from)) return;
    _stop();
    // A status is an answer, not a failure of the connection: retrying it on a
    // timer would replay an expired token at the server every few seconds while
    // the caller is already re-minting it. Nor is a URL that cannot be parsed
    // or opened — `Uri.parse` raises the first, a scheme `HttpClient` does not
    // speak the second, and the next attempt would be handed the same string.
    final transient =
        error is! MjpegHttpStatus &&
        error is! FormatException &&
        error is! ArgumentError;
    setState(() {
      _error = error;
      // Clearing the counter is what puts the error on screen: `_retrying`
      // holds the last frame in front of it, and an answer the caller has to
      // act on — a 401 it re-mints a token for — must not wait behind a
      // picture because a blip happened to come first.
      if (!transient) _attempt = 0;
    });
    if (transient) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    final delays = widget.reconnectDelays;
    if (delays.isEmpty) return;
    final delay = delays[math.min(_attempt, delays.length - 1)];
    _attempt++;
    _reconnect = Timer(delay, () {
      if (!mounted) return;
      unawaited(_start());
    });
  }

  /// Whether the backoff is still inside its first pass through
  /// [MjpegView.reconnectDelays] — 15 s on the default, after which a drop has
  /// outlived anything worth calling a blip. A frame resets `_attempt`, and a
  /// failure that schedules no retry (a status, an unusable URL) clears it, so
  /// both reach [MjpegView.error] at once.
  bool get _retrying =>
      _attempt > 0 && _attempt <= widget.reconnectDelays.length;

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final frame = _frame;
    if (error != null && !(_retrying && frame != null)) {
      return widget.error(context, error);
    }
    if (frame == null) return widget.loading(context);
    final image = Image.memory(frame, gaplessPlayback: true, fit: widget.fit);
    if (!_retrying) return image;
    return Stack(
      fit: StackFit.passthrough,
      alignment: AlignmentDirectional.topEnd,
      children: [image, widget.retrying(context)],
    );
  }
}
