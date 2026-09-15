/// Demo mode ("store review" mode): Play review needs full app access, and the
/// app only works against a self-hosted server, so a magic address serves a
/// fabricated dataset in-process (`DemoBackend`) and nothing leaves the device.
///
/// Reviewer instructions (Play Console → App access):
///   server address: `demo`, username: `demo`, password: `demo1234`.
abstract final class DemoConfig {
  /// Saved as the profile after a demo login. A single-label host never
  /// resolves publicly, so a request that escaped the interception would fail
  /// locally rather than reach anyone.
  static const baseUrl = 'http://demo';

  static const username = 'demo';
  static const password = 'demo1234';

  static bool isDemoUrl(String normalizedUrl) {
    final host = Uri.tryParse(normalizedUrl)?.host.toLowerCase();
    return host == 'demo' || host == 'demo.bambuddy.app';
  }
}
