import 'dart:async';
import 'dart:io';
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
    this.fit,
    this.idleTimeout = const Duration(seconds: 15),
  });

  final String url;
  final WidgetBuilder loading;
  final Widget Function(BuildContext context, Object error) error;
  final BoxFit? fit;

  /// How long a live stream may say nothing before it counts as dead. A remote
  /// connection is slow, not silent — 15 s is the same figure the app's HTTP
  /// client uses for a receive.
  final Duration idleTimeout;

  @override
  State<MjpegView> createState() => _MjpegViewState();
}

class _MjpegViewState extends State<MjpegView> with WidgetsBindingObserver {
  /// Also the identity of the current attempt: an event from an older one —
  /// the error a closed socket raises, above all — is not this stream's news.
  HttpClient? _client;
  Uint8List? _frame;
  Object? _error;

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
      _frame = null;
      _error = null;
      unawaited(_start());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_client == null && _error == null) unawaited(_start());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }

  void _stop() {
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
          setState(() {
            _frame = frame;
            _error = null;
          });
        },
        onError: (Object e) => _fail(e, client),
        onDone: () => _fail(const MjpegStreamEnded(), client),
      );
    } on Object catch (e) {
      _fail(e, client);
    }
  }

  void _fail(Object error, HttpClient from) {
    if (!mounted || !identical(_client, from)) return;
    _stop();
    setState(() => _error = error);
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) return widget.error(context, error);
    final frame = _frame;
    if (frame == null) return widget.loading(context);
    return Image.memory(frame, gaplessPlayback: true, fit: widget.fit);
  }
}
