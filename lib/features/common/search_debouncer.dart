import 'dart:async';

/// Runs the last of several quick search changes once the user pauses for
/// [delay]. The helper knows nothing about widgets: the caller guards its own
/// `mounted` inside [apply] and cancels through [dispose] from its `dispose`.
class SearchDebouncer {
  SearchDebouncer(this.delay);

  final Duration delay;
  Timer? _timer;

  /// Restarts the wait; only the last query of a burst reaches [apply], trimmed.
  void run(String query, void Function(String trimmed) apply) {
    _timer?.cancel();
    _timer = Timer(delay, () => apply(query.trim()));
  }

  void cancel() => _timer?.cancel();

  void dispose() => cancel();
}
