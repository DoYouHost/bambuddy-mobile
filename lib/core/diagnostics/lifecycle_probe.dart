import 'package:flutter/widgets.dart';

import 'log_event.dart';
import 'log_store.dart';

/// Records the app going to the background and coming back.
///
/// Without it every such gap reads as a hang: the UI isolate stops polling and
/// the socket closes, so a screen-off looks exactly like a freeze. App-wide
/// rather than hung off the dashboard, because a recording can start on the
/// setup screen.
class LifecycleProbe {
  LifecycleProbe({required this.store});

  final LogStore store;

  /// `inactive` and `hidden` are left out: they also fire for the notification
  /// shade, a permission dialog or the app switcher, putting three records
  /// where the interesting one is `paused`.
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
