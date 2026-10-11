import 'dart:async';

/// Something a notification tap asks the app shell to do — a confirmation it
/// has to show, a sheet it has to open — handed over from wherever the tap
/// landed.
///
/// Two ways in, because Android has two: a tap while the app runs arrives on
/// [stream]; one posted before anything listens waits in [take]. The shell
/// takes a live one off the slot as it handles it, so a later read of the
/// slot — `_onNotificationLaunch` replaying the tap that launched the app —
/// cannot hand the same one out again.
class LaunchRelay<T extends Object> {
  final _controller = StreamController<T>.broadcast();
  T? _pending;

  Stream<T> get stream => _controller.stream;

  void post(T value) {
    _pending = value;
    _controller.add(value);
  }

  /// Clears what it returns, so one tap is handled once.
  T? take() {
    final value = _pending;
    _pending = null;
    return value;
  }
}
