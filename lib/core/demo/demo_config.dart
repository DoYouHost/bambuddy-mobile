/// Demo mode ("store review" mode) constants.
///
/// Google Play review requires full app access, but the app only works against
/// a self-hosted bambuddy server. Instead of exposing a real server, the app
/// recognizes a magic address + credentials and serves a fabricated dataset
/// entirely in-process (see `DemoBackend`); no network traffic ever leaves the
/// device in demo mode.
///
/// Reviewer instructions (Play Console → App access):
///   server address: `demo`, username: `demo`, password: `demo1234`.
abstract final class DemoConfig {
  /// Canonical profile base URL saved after demo login. A single-label host
  /// never resolves publicly, so even an accidentally un-intercepted request
  /// fails locally without leaking anything.
  static const baseUrl = 'http://demo';

  static const username = 'demo';
  static const password = 'demo1234';

  /// Whether user-typed (normalized) server URL selects demo mode.
  /// Accepts `demo` and `demo.bambuddy.app` with any scheme.
  static bool isDemoUrl(String normalizedUrl) {
    final host = Uri.tryParse(normalizedUrl)?.host.toLowerCase();
    return host == 'demo' || host == 'demo.bambuddy.app';
  }
}
