import 'dart:io';

import 'package:app_diagnostics/app_diagnostics.dart';

import '../auth/credentials_store.dart';
import '../settings/settings_repository.dart';
import 'session_facts.dart';
import 'report_config.dart';
import 'ws_probe.dart';

/// bambuddy's side of the two ports `app_diagnostics` leaves open, plus the one
/// entry point the package deliberately does not carry.

/// The running session's id, kept where both isolates can read it.
class SettingsSessionStore implements DiagnosticsSessionStore {
  const SettingsSessionStore(this.settings);

  final SettingsRepository settings;

  @override
  String? loadSession() => settings.loadDiagnosticsSession();

  @override
  Future<void> saveSession(String? session) =>
      settings.saveDiagnosticsSession(session);
}

/// The WebSocket probe, told when a session opens and closes.
///
/// Both moments matter here. `WsProbe` reports *changes*, so state left by the
/// previous session would make this one's first frame read as "unchanged"; and
/// it aggregates repeat counts, so a session closed without a flush loses the
/// tail of the socket's story.
class WsSessionListener implements DiagnosticSessionListener {
  const WsSessionListener();

  @override
  void onSessionStart() => WsProbe.openSession();

  @override
  void onSessionFlush() => WsProbe.flushAll();
}

/// `startBackground` for an isolate woken to do one job and gone a second
/// later — a notification action, a request relayed from the watch. Null,
/// the normal case, when there is nothing to record into.
///
/// Those paths run in whichever isolate the platform picked, and two of the
/// three are already recording; there the records land in the stream they
/// belong to for free (`docs/logging-guide.md` §4). [LogStream.action] is
/// the third one's stream: `fgs` is the service's file for the same session
/// and two writers would tear it.
///
/// Here rather than in the package because every argument below is
/// bambuddy's: its settings repository, its keystore, its redactor and its
/// ceiling. The package keeps the parameterised `startBackground` that this
/// spells out for the one caller shape that recurs.
///
/// **Never throws.** The caller is carrying out the user's tap, and
/// diagnostics must not be why it does not happen — [SettingsRepository.opened]
/// alone is a platform read that a locked keystore can fail.
Future<BackgroundRecording?> startActionRecording({
  Future<SettingsRepository> Function() openSettings =
      SettingsRepository.opened,
  Future<Directory?> Function() resolveDirectory = diagnosticsDirectory,
  DateTime Function()? clock,
}) async {
  try {
    if (DiagnosticRecorder.isRecording) return null;
    final settings = await openSettings();
    return await DiagnosticRecorder.startBackground(
      sessions: SettingsSessionStore(settings),
      redactor: bambuddyRedactor,
      sessionLimit: recordingLimit,
      stream: LogStream.action,
      resolveDirectory: resolveDirectory,
      loadSecrets: () => sessionSecrets(
        profile: settings.loadProfile(),
        credentials: SecureCredentialsStore(),
      ),
      attachErrors: false,
      clock: clock,
    );
  } on Object {
    return null;
  }
}
