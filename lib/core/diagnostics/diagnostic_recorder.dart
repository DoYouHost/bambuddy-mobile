import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../settings/settings_repository.dart';
import 'interaction_probe.dart';
import 'log_event.dart';
import 'log_file_sink.dart';
import 'log_merge.dart';
import 'log_redactor.dart';
import 'log_store.dart';
import 'session_facts.dart';

/// Owns one recording session: builds the header, holds the buffer, wires the
/// probes, and hands back the finished JSONL.
///
/// ## What is wired
///
/// - user interactions — [InteractionProbe], attached for the session
/// - the durable mirror of the UI stream, so a crash mid-recording still
///   leaves a log on disk
/// - the session id in [SettingsRepository], which is how the background
///   isolate will learn that a recording is running
///
/// ## What is NOT wired yet
///
/// Instrumentation still to come, in the order the plan calls for:
///
/// 1. **HTTP** — an interceptor next to `AuthInterceptor` in `api_client.dart`
/// 2. **WebSocket** — frame types, disconnects, backoff in `ws_client.dart`
/// 3. **Uncaught exceptions** — `FlutterError.onError`,
///    `PlatformDispatcher.instance.onError`, `runZonedGuarded` in `main.dart`
/// 4. **Navigation** — a `GoRouter` observer (dialogs are routes, so open and
///    cancel come along for free)
/// 5. **Background isolate** — the FGS stream in
///    `print_monitor_task_handler.dart`, written to its own file and merged
///    here at [stop]
///
/// Until those land a recording contains interactions and session markers
/// only. [stop] already merges an FGS stream if it finds one, so item 5 needs
/// no change here.
class DiagnosticRecorder {
  DiagnosticRecorder({
    required this.settings,
    required this.loadFacts,
    this.resolveDirectory = diagnosticsDirectory,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SettingsRepository settings;
  final Future<SessionFacts> Function() loadFacts;

  /// Where session files go. Returning null keeps the session in memory only —
  /// which is what tests do, and what a device with no writable support
  /// directory degrades to.
  final Future<Directory?> Function() resolveDirectory;

  final DateTime Function() _clock;

  static LogStore? _active;

  /// The buffer to log into, or null when nothing is being recorded.
  ///
  /// Instrumentation writes through this: `DiagnosticRecorder.active?.add(…)`.
  /// Dart does not evaluate the arguments of a `?.` call on null, so building
  /// the field map costs nothing while recording is off — that is what makes
  /// it acceptable on paths as hot as every HTTP response.
  static LogStore? get active => _active;

  static bool get isRecording => _active != null;

  LogFileSink? _sink;
  InteractionProbe? _probe;

  Future<void> start() async {
    if (_active != null) return;

    final session = LogHeader.newSessionId();
    final facts = await loadFacts();
    final redactor = LogRedactor();
    facts.secrets.forEach(redactor.remember);

    final header = facts.toHeader(ts: _clock(), session: session);
    final directory = await _resolveQuietly();
    final sink = directory == null
        ? null
        : LogFileSink(LogFileSink.fileFor(directory, session, LogStream.ui));
    await sink?.writeHeader(header);

    final store = LogStore(
      header: header,
      redactor: redactor,
      onLine: sink?.writeLine,
    );

    _sink = sink;
    _active = store;
    _probe = InteractionProbe(store: store)..attach();

    // The id doubles as the "recording is on" flag: two keys would be two
    // things to keep in sync across isolates.
    await settings.saveDiagnosticsSession(session);
    store.add(LogSource.app, 'recording_started');
  }

  /// Stops and returns the session as JSONL, merging the background isolate's
  /// stream when there is one. Empty string if nothing was recording.
  Future<String> stop() async {
    final store = _active;
    if (store == null) return '';

    store.add(LogSource.app, 'recording_stopped');
    _probe?.detach();
    _probe = null;
    _active = null;
    await settings.saveDiagnosticsSession(null);
    await _sink?.close();
    _sink = null;

    final background = await _readBackgroundStream(store.header.session);
    return background.isEmpty
        ? store.export()
        : mergeSessions(store.export(), background);
  }

  /// Stops and throws the session away, files included. For the user backing
  /// out of a report — the log must not outlive the intent to send it.
  Future<void> discard() async {
    final session = _active?.header.session;
    _probe?.detach();
    _probe = null;
    _active = null;
    await settings.saveDiagnosticsSession(null);
    await _sink?.close();
    _sink = null;
    if (session != null) await _deleteSessionFiles(session);
  }

  /// "The bug just happened." Cheapest thing that cuts the search through a
  /// few thousand records.
  void mark() => _active?.mark();

  Future<Directory?> _resolveQuietly() async {
    try {
      return await resolveDirectory();
    } on Object {
      return null;
    }
  }

  Future<String> _readBackgroundStream(String session) async {
    final directory = await _resolveQuietly();
    if (directory == null) return '';
    return LogFileSink(
      LogFileSink.fileFor(directory, session, LogStream.fgs),
    ).read();
  }

  Future<void> _deleteSessionFiles(String session) async {
    final directory = await _resolveQuietly();
    if (directory == null) return;
    for (final stream in LogStream.values) {
      await LogFileSink(
        LogFileSink.fileFor(directory, session, stream),
      ).delete();
    }
  }
}

/// `<support>/diagnostics`, created on first use. Support directory rather
/// than documents: these files are ours, not the user's, and should not show
/// up in a file manager.
Future<Directory?> diagnosticsDirectory() async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory('${base.path}/diagnostics');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}
