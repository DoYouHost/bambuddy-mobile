import 'dart:async';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/background_sync.dart';
import '../../providers.dart';
import '../notifications/finish_photo_providers.dart';
import 'providers.dart';
import 'ws_providers.dart';

/// Who watches the printers: this isolate in the foreground, the foreground
/// service in the background, never both and never neither.
///
/// Owned by the app, not by a screen. It used to live in the dashboard's
/// state, which made a mounted dashboard a condition of background monitoring
/// and split the cold-start order over two files: the watch relay started in
/// `app.dart` before the dashboard's first frame had stopped a service left
/// over from the last launch.
final backgroundHandoverProvider = Provider<BackgroundHandover>((ref) {
  final handover = BackgroundHandover(ref);
  ref.onDispose(handover.dispose);
  return handover;
});

class BackgroundHandover {
  BackgroundHandover(this._ref);

  final Ref _ref;
  AppLifecycleListener? _lifecycle;
  bool _disposed = false;

  /// Whether the service is known to be stopped, so the UI's finish-photo
  /// notifier may run: the two share one read-modify-write memory. False until
  /// [start] has dealt with a surviving service, and while paused.
  bool _serviceDown = false;

  /// The tail of [_serviceTurn]'s queue.
  Future<void> _serviceChanges = Future.value();

  /// Counts pauses and resumes, so a callback that outlived the transition it
  /// was started for can tell and stand down.
  int _epoch = 0;

  /// Idempotent. Called once by the app as it comes up, which is already
  /// resumed: no transition will announce it.
  void start() {
    if (_lifecycle != null || _disposed) return;
    _lifecycle = AppLifecycleListener(onPause: _onPause, onResume: _onResume);
    // A rebuilt notifier (a new socket, a new profile) comes back stopped.
    _ref.listen(finishPhotoNotifierProvider, (_, next) {
      if (_serviceDown) next?.start();
    });
    final epoch = _epoch;
    // `whenComplete`: a platform that cannot answer still leaves this isolate
    // the only one there is, and the error goes on to the uncaught handler.
    unawaited(
      _takeOverFromSurvivingService().whenComplete(() => _takeBack(epoch)),
    );
  }

  void dispose() {
    _disposed = true;
    _lifecycle?.dispose();
    _lifecycle = null;
  }

  /// Background monitoring was switched off: a running service ends now
  /// rather than at the next resume.
  Future<void> stopDisabledService() async {
    final stopped = await _serviceTurn(
      _ref.read(backgroundMonitorProvider).stop,
    );
    // Its own verb: the one explanation the service's `destroy` cannot carry.
    if (stopped) _log('ui_stop_disabled');
  }

  void _onPause() {
    _epoch++;
    // Nothing to watch without a server, and the service would only stop
    // itself (`PrintMonitorTaskHandler.onStart`).
    if (_ref.read(serverProfileProvider) == null) return;
    if (_ref.read(bgMonitoringEnabledProvider)) {
      final monitor = _ref.read(backgroundMonitorProvider);
      unawaited(
        _serviceTurn(monitor.start).then((started) {
          // Recorded from here, the one isolate that is certainly able to
          // write: the service's own stream gives up silently in several cases
          // and each looks like an app that was never backgrounded.
          _log('ui_start', started: started);
          // Already running, so its start-up never ran for this recording and
          // it has no idea one exists: the normal state after one swipe-away.
          if (!started) monitor.sync(BackgroundSync.diagnostics);
        }),
      );
      // Exactly one responder may listen at a time — a request answered twice
      // is a command executed twice (e.g. double startNext).
      unawaited(_ref.read(wearRelayHandlerProvider).stop());
    }
    // The UI goes silent: the service keeps the process alive, so a timer
    // left running would keep polling and feed a second set of alerts.
    if (_ref.exists(printerStatusesProvider)) {
      _ref.read(printerStatusesProvider.notifier).suspend();
    }
    if (_ref.exists(dashboardProvider)) {
      _ref.read(dashboardProvider.notifier).pausePolling();
    }
    _ref.read(dashboardWatchedProvider.notifier).setForeground(false);
    _ref.read(tokenRefresherProvider)?.stop();
    _ref.read(cameraTokenRefresherProvider)?.stop();
    _ref.read(mediaAuthRefresherProvider)?.stop();
    _serviceDown = false;
    final finishPhoto = _ref.read(finishPhotoNotifierProvider);
    if (finishPhoto != null) unawaited(finishPhoto.stop());
  }

  void _onResume() {
    final epoch = ++_epoch;
    unawaited(
      _serviceTurn(_ref.read(backgroundMonitorProvider).stop).then((stopped) {
        // Only when there was something to stop: with monitoring off the app
        // still asks on every resume.
        if (stopped) _log('ui_stop');
        // `then`, unlike [start]: a stop that threw may have left the service
        // running, and two relays cost more than none for one session.
        _takeBack(epoch);
      }),
    );
    if (_ref.read(serverProfileProvider) == null) return;
    if (_ref.exists(dashboardProvider)) {
      _ref.read(dashboardProvider.notifier).resumePolling();
    }
    if (_ref.exists(printerStatusesProvider)) {
      _ref.read(printerStatusesProvider.notifier).resume();
    }
    _ref.read(dashboardWatchedProvider.notifier).setForeground(true);
    _ref.read(tokenRefresherProvider)?.start();
    _ref.read(cameraTokenRefresherProvider)?.start();
    _ref.read(mediaAuthRefresherProvider)?.start();
  }

  /// Takes the watch relay and the photo hunt for this isolate, with the
  /// service down. Stands down when the app was paused again before the stop
  /// landed: both went back to the service by then.
  void _takeBack(int epoch) {
    if (_disposed || epoch != _epoch) return;
    unawaited(_ref.read(wearRelayHandlerProvider).start());
    _serviceDown = true;
    _ref.read(finishPhotoNotifierProvider)?.start();
  }

  /// A service Android restarted after a swipe-away runs on whatever it froze
  /// at its own start-up, and its watch relay answers alongside this one's.
  Future<void> _takeOverFromSurvivingService() {
    final monitor = _ref.read(backgroundMonitorProvider);
    return _serviceTurn(() async {
      if (!await monitor.isRunning()) return;
      _log('ui_stop_survivor');
      await monitor.stop();
    });
  }

  /// Runs a service start or stop after the one before it has landed. Each is
  /// a platform call that takes time, and a stop that overtakes the start it
  /// follows finds nothing to stop and leaves the service running under an
  /// app that is back in the foreground.
  Future<T> _serviceTurn<T>(Future<T> Function() change) {
    final done = _serviceChanges.then((_) => change());
    _serviceChanges = done.then((_) {}, onError: (Object _) {});
    return done;
  }

  /// Hands the background service's lifecycle to the log from the UI side, where
  /// there is always a buffer to write into.
  ///
  /// `LogSource.fgs` even though the UI isolate writes it: the source names the
  /// **subsystem**, not the writer, and a reader who filters the service's lane
  /// has to see the half of its lifecycle only this side can report. These used
  /// to file as `app`/`bg_service` with the verb in a field, which split one
  /// story across two lanes and two grammars.
  ///
  /// The `ui_` verbs stay distinct from the service's own `start` / `destroy`:
  /// "the UI asked" and "the service's start-up ran" are different moments, and
  /// a report carrying the first without the second is exactly the interesting
  /// one.
  void _log(String event, {bool? started}) => DiagnosticRecorder.active?.add(
    LogSource.fgs,
    event,
    fields: {'started': started},
  );
}
