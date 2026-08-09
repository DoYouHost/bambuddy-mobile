import 'dart:ui' show ErrorCallback, PlatformDispatcher;

import 'package:flutter/foundation.dart';

import 'log_event.dart';
import 'log_store.dart';

/// Records what nobody caught: exceptions from the framework (build, layout,
/// gestures) and asynchronous errors that escaped their future.
///
/// Without this a crash is the one thing a report cannot describe: the user
/// sees a blank screen, the log shows the tap that led to it and then nothing,
/// because the exception went to the console. Repeats collapse into a count —
/// see `docs/diagnostics-log.md`.
///
/// No `runZonedGuarded`: root-zone errors already reach
/// [PlatformDispatcher.onError], so a guarded zone would add only errors thrown
/// before a recording exists — unloggable by definition — at the cost of
/// initialising the binding inside `runApp`'s zone.
class ErrorProbe {
  ErrorProbe({required this.store});

  final LogStore store;

  /// Long enough that a stuttering rebuild loop costs one record every five
  /// seconds, short enough that a log salvaged from disk after a kill still
  /// shows the storm.
  static const _burstWindow = 5000;

  FlutterExceptionHandler? _previousOnError;
  ErrorCallback? _previousPlatformOnError;
  bool _attached = false;

  /// What the pending repeats are repeats *of*, and how many there are.
  String? _burstKey;
  String? _burstType;
  int _repeats = 0;
  int _lastFlushMs = 0;

  /// Stamping the count with the moment it gets written would put a storm that
  /// ended at fourteen seconds at the end of the session instead.
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
        // "while handling a gesture", "during a scheduler callback".
        context: details.context?.toDescription(),
      );
      // Chained, not replaced: this prints the error and paints the red screen
      // in debug, and a recording must not change what the app does.
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

  /// Writes out the pending repeat count. Called when the recording stops too,
  /// so the last storm is not lost with its tail.
  void flushRepeats() {
    if (_repeats == 0) return;
    store.add(
      LogSource.err,
      'repeated',
      lvl: LogLevel.error,
      fields: {'type': _burstType, 'n': _repeats},
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
          // Clipped by the redactor's string ceiling to about twenty-five
          // frames, enough to place the failure without eating the buffer.
          'stack': trace,
        },
      );
    } on Object {
      // Nothing sane left to do: the log loses one record, the app keeps going.
    }
  }

  /// `toString()` without the class name in front — that is already the `type`.
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
