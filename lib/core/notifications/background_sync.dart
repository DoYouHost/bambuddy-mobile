/// A fact the app writes to `SharedPreferences` that the service isolate has to
/// re-read while it runs.
///
/// The isolate reads preferences once, at start-up — which misses a service
/// Android restarted after a swipe, since that one outlives the next launch and
/// `startService` is then a no-op. Each value is one such fact, and one message
/// on the port `main` opens.
enum BackgroundSync {
  /// Which bug report this isolate should log into, if any.
  diagnostics,

  /// Whether the user reads a 24-hour clock — see `DateTimeFormats.system`.
  clock,

  /// How many printers the demo runs a print on. Demo only: on a real server
  /// this isolate is fed by the server, and nothing here reads it.
  demoPrinters;

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
