import 'dart:ui' show ErrorCallback, PlatformDispatcher;

import 'package:flutter/foundation.dart';

import 'log_event.dart';
import 'log_store.dart';

/// Records what nobody caught: exceptions from the framework (build, layout,
/// gestures) and asynchronous errors that escaped their future.
///
/// Without this a crash is the one thing a report cannot describe. The user
/// sees a blank screen, the log shows the tap that led to it and then nothing —
/// the exception went to the console, which is exactly where a user cannot look.
///
/// ## Repeats
///
/// A widget that throws in `build` throws again on **every frame**. Sixty
/// identical records a second empty a four-thousand-record buffer in about a
/// minute, taking with them everything that happened before the failure — the
/// only part that explains it. So the first occurrence is recorded in full and
/// the rest are counted:
///
/// ```json
/// {"evt":"uncaught","type":"RangeError","msg":"…","stack":"…"}
/// {"evt":"repeated","type":"RangeError","n":312}
/// ```
///
/// The count is written out when the storm ends (a different error arrives, or
/// the recording stops) and every [_burstWindow] while it lasts, so a burst
/// still shows up on the timeline where it happened instead of collapsing into
/// one number at the end. The window is checked when an error arrives — a storm
/// by definition keeps arriving, so this needs no timer of its own.
///
/// ## Why no `runZonedGuarded`
///
/// Uncaught errors from the root zone already reach
/// [PlatformDispatcher.onError], so a guarded zone would add only errors thrown
/// before a recording exists — which are unloggable by definition. It would also
/// mean initialising the binding inside the same zone as `runApp`, a trap that
/// buys nothing here.
class ErrorProbe {
  ErrorProbe({required this.store});

  final LogStore store;

  /// How long a burst may run before its count is written out. Long enough that
  /// a stuttering rebuild loop costs one record every five seconds, short enough
  /// that a log salvaged from disk after a kill still shows the storm.
  static const _burstWindow = 5000;

  FlutterExceptionHandler? _previousOnError;
  ErrorCallback? _previousPlatformOnError;
  bool _attached = false;

  /// What the pending repeats are repeats *of*, and how many there are.
  String? _burstKey;
  String? _burstType;
  int _repeats = 0;
  int _lastFlushMs = 0;

  /// When the last counted repeat happened. The count is written out later —
  /// when another error arrives or the recording stops — and stamping it with
  /// *that* moment would put a storm that ended at fourteen seconds at the end
  /// of the session instead.
  int _lastRepeatMs = 0;

  void attach() {
    if (_attached) return;
    _attached = true;

    _previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      _record(
        details.exception,
        details.stack,
        via: 'flutter',
        // "while handling a gesture", "during a scheduler callback" — where the
        // framework was when it broke, in four words.
        context: details.context?.toDescription(),
      );
      // Chained, not replaced: this is what prints the error and paints the red
      // screen in debug. A recording must not change what the app does.
      _previousOnError?.call(details);
    };

    _previousPlatformOnError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      _record(error, stack, via: 'async');
      // Whatever was there decides whether the error counts as handled; with
      // nothing there the answer is no, so the platform still reports it.
      return _previousPlatformOnError?.call(error, stack) ?? false;
    };
  }

  void detach() {
    if (!_attached) return;
    flushRepeats();
    FlutterError.onError = _previousOnError;
    PlatformDispatcher.instance.onError = _previousPlatformOnError;
    _previousOnError = null;
    _previousPlatformOnError = null;
    _attached = false;
  }

  /// Writes out the pending repeat count, if any. Called when a burst ends and
  /// when the recording stops, so the last storm is not lost with its tail.
  void flushRepeats() {
    if (_repeats == 0) return;
    store.add(
      LogSource.err,
      'repeated',
      lvl: LogLevel.error,
      fields: {'type': _burstType, 'n': _repeats},
      // Stamped with the last error it counts, not with the moment somebody
      // got around to writing the count down.
      at: _lastRepeatMs,
    );
    _repeats = 0;
    _lastFlushMs = store.elapsedMs;
  }

  void _record(
    Object error,
    StackTrace? stack, {
    required String via,
    String? context,
  }) {
    // An exception thrown while logging an exception would come straight back
    // through the handler we are standing in.
    try {
      final type = error.runtimeType.toString();
      final message = _messageOf(error, type);
      final trace = stack?.toString();
      final key = '$via|$type|$message|${_firstFrame(trace)}';

      if (key == _burstKey) {
        _repeats++;
        _lastRepeatMs = store.elapsedMs;
        if (_lastRepeatMs - _lastFlushMs >= _burstWindow) flushRepeats();
        return;
      }

      // A new error ends the previous burst, so its count lands before the
      // record that interrupted it.
      flushRepeats();
      _burstKey = key;
      _burstType = type;
      _lastFlushMs = store.elapsedMs;

      store.add(
        LogSource.err,
        'uncaught',
        lvl: LogLevel.error,
        fields: {
          'via': via,
          'type': type,
          'ctx': context,
          'msg': message,
          // Clipped by the redactor's string ceiling — about twenty-five frames,
          // enough to place the failure without one record eating the buffer.
          'stack': trace,
        },
      );
    } on Object {
      // Nothing sane left to do: the log loses one record, the app keeps going.
    }
  }

  /// `toString()` without the class name in front of it — that is already the
  /// `type`, and the same reasoning as in `HttpProbe`.
  static String _messageOf(Object error, String type) {
    final text = error.toString().trim();
    return text.startsWith('$type: ') ? text.substring(type.length + 2) : text;
  }

  /// The innermost frame, which is what makes two same-typed errors from
  /// different places count separately.
  static String _firstFrame(String? stack) {
    if (stack == null || stack.isEmpty) return '';
    final end = stack.indexOf('\n');
    return end == -1 ? stack : stack.substring(0, end);
  }
}
