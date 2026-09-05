/// A fact the app writes to `SharedPreferences` that the service isolate has to
/// re-read while it runs.
///
/// The isolate reads preferences once, at start-up. That covers a service which
/// starts *because* the app went to the background, and misses the opposite
/// order — a service Android restarted after a swipe outlives the next launch,
/// so `startService` is a no-op and nothing it decided at boot is ever revisited.
/// Each value here is one such fact, and one message on the port `main` opens.
enum BackgroundSync {
  /// Which bug report this isolate should log into, if any.
  diagnostics,

  /// Whether the user reads a 24-hour clock — see `DateTimeFormats.system`.
  clock;

  /// The wire shape, kept as `{what: 'sync'}` because that is what shipped.
  Map<String, String> get message => {name: 'sync'};

  /// What [message] said, or null for anything else that arrives on the port.
  static BackgroundSync? parse(Object data) {
    if (data is! Map) return null;
    for (final what in values) {
      if (data[what.name] == 'sync') return what;
    }
    return null;
  }
}
