import 'dart:io' show pid;
import 'dart:math';

import '../settings/settings_repository.dart';

/// Marks *which* watch-relay responder is listening, so the native listener
/// service does not wake a second one. Exactly one may answer a request: a
/// command answered twice is executed twice.
///
/// The value is `<pid>:<nonce>`, and both halves earn their place:
///
/// - the **pid** is what the service compares with its own `Process.myPid()`,
///   so a claim can only mean "claimed by a process that is still alive" —
///   a flag left behind by a killed process would silence the phone for good;
/// - the **nonce** is what tells two responders in the *same* process apart.
///   The foreground service's isolate shares the app's process, so during the
///   hand-over both write the same pid; without it, the outgoing handler's
///   release would wipe the incoming one's claim and the next request would be
///   answered by the service's isolate *and* by a freshly woken engine.
///
/// Prefs because neither side can see into the other: Dart has no view across
/// isolates, native has none into them.
///
/// Ordering is part of the contract — see `WearRelayHandler.start`.
class WearRelayClaim {
  /// [processId] and [nonce] are for tests; the defaults are this process and
  /// a value no other responder will pick.
  WearRelayClaim(this._settings, {int? processId, String? nonce})
      : _token = '${processId ?? pid}:'
            '${nonce ?? Random().nextInt(1 << 32).toRadixString(36)}';

  final SettingsRepository _settings;
  final String _token;

  /// Whether the claim is now ours. **False means the caller must not
  /// listen**: an unclaimed listener is answered by a woken engine as well,
  /// which is the double execution this class exists to prevent. The watch is
  /// not left stranded either way — the engine answers it.
  ///
  /// Never throws; a prefs write is a platform call and this one runs on the
  /// path that carries the user's tap.
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
