import 'dart:io' show pid;
import 'dart:math';

import '../settings/settings_repository.dart';

/// Marks *which* watch-relay responder is listening, so the native service does
/// not wake a second one: a command answered twice is executed twice.
///
/// The value is `<pid>:<nonce>`. The **pid** is what the service compares with
/// its own `Process.myPid()`, so a flag left behind by a killed process cannot
/// silence the phone for good; the **nonce** tells apart two responders in the
/// same process, which the foreground service's isolate and the app's handler
/// are. In prefs because neither side can see into the other.
///
/// Ordering is part of the contract — see `WearRelayHandler.start`.
class WearRelayClaim {
  /// [processId] and [nonce] are for tests; the defaults are this process and
  /// a value no other responder will pick.
  WearRelayClaim(this._settings, {int? processId, String? nonce})
    : _token =
          '${processId ?? pid}:'
          '${nonce ?? Random().nextInt(1 << 32).toRadixString(36)}';

  final SettingsRepository _settings;
  final String _token;

  /// Whether the claim is now ours. **False means the caller must not listen**
  /// — an unclaimed listener is answered by a woken engine as well, and the
  /// watch is not stranded either way. Never throws: this runs on the path that
  /// carries the user's tap.
  Future<bool> take() async {
    try {
      await _settings.saveWearRelayClaim(_token);
      return true;
    } on Object {
      return false;
    }
  }

  /// Releases the claim only while it is still *this* responder's — one that
  /// another has taken over in the meantime is theirs to release.
  Future<void> release() async {
    try {
      final settings = await _settings.reloaded();
      if (settings.loadWearRelayClaim() != _token) return;
      await settings.saveWearRelayClaim(null);
    } on Object {
      // A claim we failed to clear costs at most one unanswered request: the
      // next responder overwrites it, and the process dying invalidates it.
    }
  }
}
