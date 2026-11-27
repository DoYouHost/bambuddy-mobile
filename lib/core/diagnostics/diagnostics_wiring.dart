import 'dart:io';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

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

/// What the last question to Google Play came to (`PlayUpdate.onAnswer`). Written
/// again when a recording starts: Play is asked at start and on resume, and a
/// recording may see neither.
class PlayCheckProbe implements DiagnosticSessionListener {
  const PlayCheckProbe();

  static Map<String, Object?>? _last;

  /// The recording [onSessionStart] has opened. The recorder takes records a
  /// moment before that, and an answer landing then waits for it rather than
  /// being written twice.
  static LogStore? _open;

  @visibleForTesting
  static void forget() {
    _last = null;
    _open = null;
  }

  static void answered(Map<String, Object?> answer) {
    _last = answer;
    if (identical(DiagnosticRecorder.active, _open)) _record();
  }

  @override
  void onSessionStart() {
    _open = DiagnosticRecorder.active;
    _record();
  }

  @override
  void onSessionFlush() {}

  static void _record() {
    final last = _last;
    if (last == null) return;
    DiagnosticRecorder.active?.add(LogSource.app, 'play_check', fields: last);
  }
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
