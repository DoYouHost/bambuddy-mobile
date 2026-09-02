import 'dart:io' show pid;

import '../settings/settings_repository.dart';

/// Marks this process as the one whose watch-relay responder is listening, so
/// the native listener service does not wake a second one. Exactly one may
/// answer a request: a command answered twice is executed twice.
///
/// It is a **process id, not a flag** — the service compares it with its own
/// `Process.myPid()`, so a claim can only mean "claimed by a process that is
/// still alive", where a boolean left behind by a killed process would silence
/// the phone for good. Prefs because neither side can see into the other:
/// Dart has no view across isolates, native has none into them.
///
/// Ordering is part of the contract — see `WearRelayHandler.start`.
class WearRelayClaim {
  /// [processId] is for tests; the default is this process.
  WearRelayClaim(this._settings, {int? processId})
      : _pid = processId ?? pid;

  final SettingsRepository _settings;
  final int _pid;

  Future<void> take() => _settings.saveWearRelayPid(_pid);

  /// Only releases a claim that is still ours — another process taking over
  /// while this one was shutting down must keep it.
  Future<void> release() async {
    final settings = await _settings.reloaded();
    if (settings.loadWearRelayPid() != _pid) return;
    await settings.saveWearRelayPid(null);
  }
}
