import 'dart:async';

/// Timer factory — injectable so tests can control time instead of waiting out
/// the window.
typedef TimerFactory = Timer Function(Duration, void Function());

/// The rule the printer card and the offline alert both follow: a
/// `connected:false` frame is not an offline printer yet.
///
/// `connected` flickers. The socket can say one thing while the poll lane still
/// says the other — which is what switching a printer's power at the plug looks
/// like from here — so a disconnect is believed only once it has stood for
/// [window]. A printer that comes back first cancels the countdown, and the
/// caller is told ([onFlicker]) that whatever it was holding back never
/// happened.
///
/// Written twice before this, with the same 15 seconds in two files and two
/// different answers to a partial frame. There is one answer now: `null` is not
/// `false`. An older server, or a frame that carries a subset of the fields,
/// says nothing about reachability — and a card that read that as "offline"
/// would collapse on a frame that never mentioned the printer's connection.
class OfflineDebounce {
  OfflineDebounce({this.window = defaultWindow, TimerFactory? timerFactory})
    : _timer = timerFactory ?? Timer.new;

  /// Long enough for the other lane to contradict the frame, short enough that
  /// a printer someone switched off does not look present for a whole minute.
  static const defaultWindow = Duration(seconds: 15);

  final Duration window;
  final TimerFactory _timer;

  Timer? _countdown;
  bool _offline = false;

  /// Whether the disconnect has been believed — the card collapses on this and
  /// the monitor alerts on it.
  bool get offline => _offline;

  /// Whether a countdown is running: a disconnect seen, not yet believed.
  bool get counting => _countdown != null;

  /// Adopt a state without acting on it. Both callers meet a printer that is
  /// already offline when they start — the card on its first build, the monitor
  /// when it primes a printer it has never seen — and neither may treat that as
  /// something that just happened.
  void seed(bool? connected) {
    if (connected == null) return;
    _countdown?.cancel();
    _countdown = null;
    _offline = !connected;
  }

  /// Feed every frame's `connected`.
  ///
  /// [onSustained] runs when the disconnect is believed: after [window], or
  /// immediately when [debounce] is false. Pass `debounce: false` for a frame
  /// nothing could contradict — the first one after the line to the server came
  /// up, where a countdown would only hold a stale layout together.
  ///
  /// [onFlicker] runs when a countdown is cancelled by the printer answering
  /// again, so a caller that records what it suppressed can say the alert it
  /// was holding back never happened. It never runs for a disconnect that was
  /// already believed, so it stays one record per flap.
  void observe(
    bool? connected, {
    required void Function() onSustained,
    void Function()? onFlicker,
    bool debounce = true,
  }) {
    if (connected == null) return;
    if (connected) {
      final held = _countdown;
      _countdown = null;
      _offline = false;
      if (held != null) {
        held.cancel();
        onFlicker?.call();
      }
      return;
    }
    if (_offline || _countdown != null) return;
    if (!debounce) {
      _offline = true;
      onSustained();
      return;
    }
    _countdown = _timer(window, () {
      _countdown = null;
      _offline = true;
      onSustained();
    });
  }

  void dispose() {
    _countdown?.cancel();
    _countdown = null;
  }
}
