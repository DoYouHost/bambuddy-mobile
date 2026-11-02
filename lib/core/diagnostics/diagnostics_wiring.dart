import 'dart:io';

import 'package:app_diagnostics/app_diagnostics.dart';

import '../auth/credentials_store.dart';
import '../settings/settings_repository.dart';
import 'session_facts.dart';
import 'report_config.dart';
import 'ws_probe.dart';

/// bambuddy's side of the two ports `app_diagnostics` leaves open, plus the one
/// entry point the package deliberately does not carry.

/// The WebSocket probe, told when a session opens and closes: it reports changes and
/// aggregates repeats, so both moments matter (docs/logging-guide.md, "startActionRecording and the
/// watch socket probe").
class WsSessionListener implements DiagnosticSessionListener {
  const WsSessionListener();

  @override
  void onSessionStart() => WsProbe.openSession();

  @override
  void onSessionFlush() => WsProbe.flushAll();
}

/// `startBackground` for an isolate woken to do one job and gone a second later — a
/// notification action, a request relayed from the watch. Null, the normal case, when
/// there is nothing to record into. [LogStream.action] is the stream of the one such
/// path that is not already recording. Here, not in the package, because every
/// argument is bambuddy's own. **Never throws**: the caller is carrying out the user's
/// tap (docs/logging-guide.md, "startActionRecording and the watch socket probe").
Future<BackgroundRecording?> startActionRecording({
  Future<SettingsRepository> Function() openSettings =
      SettingsRepository.opened,
  Future<Directory?> Function() resolveDirectory = diagnosticsDirectory,
}) async {
  try {
    if (DiagnosticRecorder.isRecording) return null;
    final settings = await openSettings();
    return await DiagnosticRecorder.startBackground(
      sessions: settings.diagnosticsSessions,
      redactor: bambuddyRedactor,
      sessionLimit: recordingLimit,
      stream: LogStream.action,
      resolveDirectory: resolveDirectory,
      loadSecrets: () => sessionSecrets(
        profile: settings.loadProfile(),
        credentials: SecureCredentialsStore(),
      ),
      attachErrors: false,
    );
  } on Object {
    return null;
  }
}
