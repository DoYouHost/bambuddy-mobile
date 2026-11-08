/// Runs async tasks one at a time, in the order they were queued. A task that
/// fails does not stop the next one; its error goes to its own caller.
///
/// For writes whose steps must not interleave: two calls that each await a
/// store, a flag and then set state can otherwise finish in either order and
/// leave the three disagreeing.
class SerialQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() task) {
    final result = _tail.then((_) => task());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }
}
