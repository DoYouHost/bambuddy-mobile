import 'package:flutter/widgets.dart';

import 'log_event.dart';
import 'log_store.dart';

/// Records the app going to the background and coming back.
///
/// Without it every such gap reads as a hang. A log that goes quiet for forty
/// seconds and then resumes mid-poll looks exactly like an app that froze,
/// while what usually happened is that the screen turned off: the UI isolate
/// stops polling, the socket closes and the foreground service takes over. One
/// record per transition turns "it stopped responding" into a timeline.
///
/// Attached for the session, like the other probes that need a buffer to write
/// to. App-wide rather than hung off the dashboard's own lifecycle listener —
/// a recording can start on the setup screen, where there is no dashboard.
class LifecycleProbe {
  LifecycleProbe({required this.store});

  final LogStore store;

  /// What earns a record. `inactive` and `hidden` also fire for a pulled-down
  /// notification shade, a permission dialog or the app switcher — states the
  /// user does not experience as leaving the app, and which would put three
  /// records where the interesting one is `paused`.
  static const _reported = {
    AppLifecycleState.resumed,
    AppLifecycleState.paused,
    AppLifecycleState.detached,
  };

  AppLifecycleListener? _listener;

  void attach() {
    _listener ??= AppLifecycleListener(onStateChange: _onStateChange);
  }

  void detach() {
    _listener?.dispose();
    _listener = null;
  }

  void _onStateChange(AppLifecycleState state) {
    if (!_reported.contains(state)) return;
    store.add(LogSource.app, 'lifecycle', fields: {'state': state.name});
  }
}
