import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../settings/settings_repository.dart';
import 'error_probe.dart';
import 'interaction_probe.dart';
import 'lifecycle_probe.dart';
import 'log_event.dart';
import 'log_file_sink.dart';
import 'log_merge.dart';
import 'log_redactor.dart';
import 'log_store.dart';
import 'navigation_probe.dart';
import 'session_facts.dart';

/// Owns one recording session: builds the header, holds the buffer, wires the
/// probes, and hands back the finished JSONL.
///
/// ## What is wired
///
/// - user interactions — [InteractionProbe], attached for the session
/// - navigation — [NavigationProbe], installed on the router for the app's
///   lifetime; [start] opens the session with the screen it is showing
/// - HTTP — `HttpProbe`, a dio interceptor installed by `createBareDio` for the
///   app's lifetime; nothing to attach here, it reads [active] per request
/// - uncaught exceptions — [ErrorProbe], attached for the session
/// - background and resume — [LifecycleProbe], attached for the session
/// - the durable mirror of the UI stream, so a crash mid-recording still
///   leaves a log on disk
/// - the session id in [SettingsRepository], which is how the background
///   isolate will learn that a recording is running
///
/// ## What is NOT wired yet
///
/// Instrumentation still to come, in the order the plan calls for:
///
/// 1. **WebSocket** — frame types, disconnects, backoff in `ws_client.dart`
/// 2. **Background isolate** — the FGS stream in
///    `print_monitor_task_handler.dart`, written to its own file and merged
///    here at [stop]. Until it lands the isolate's own HTTP calls and crashes go
///    nowhere: [active] is a static, and that isolate has its own heap.
///
/// [stop] already merges an FGS stream if it finds one, so item 2 needs no
/// change here.
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
  ErrorProbe? _errors;
  LifecycleProbe? _lifecycle;

  /// The session that [stop] just finished, kept so [discard] can still delete
  /// its files. The user backs out from the review screen, which is reached
  /// *after* stopping — by then there is no active session to take the id from.
  String? _finished;

  Future<void> start() async {
    if (_active != null) return;

    final session = LogHeader.newSessionId();
    final facts = await loadFacts();
    final redactor = LogRedactor();
    facts.secrets.forEach(redactor.remember);

    final header = facts.toHeader(ts: _clock(), session: session);
    final directory = await _resolveQuietly();
    if (directory != null) await _sweepOtherSessions(directory, session);
    _finished = null;
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
    // Attached per session rather than for the app's lifetime: with no store to
    // write to there is nothing to record, and an idle app keeps Flutter's own
    // error handling exactly as it was.
    _errors = ErrorProbe(store: store)..attach();
    _lifecycle = LifecycleProbe(store: store)..attach();

    // The id doubles as the "recording is on" flag: two keys would be two
    // things to keep in sync across isolates.
    await settings.saveDiagnosticsSession(session);
    store.add(LogSource.app, 'recording_started');
    // Where the session starts. The navigation probe reports changes, so
    // without this the first screen would be named only once the user leaves it.
    final screen = NavigationProbe.screen;
    if (screen != null) {
      store.add(LogSource.ui, 'route', fields: {'to': screen});
    }
  }

  /// Stops and returns the session as JSONL, merging the background isolate's
  /// stream when there is one. Empty string if nothing was recording.
  Future<String> stop() async {
    final store = _active;
    if (store == null) return '';

    // Before the closing marker, so a burst still running when the user hits
    // stop has its count inside the session rather than after its end.
    _errors?.detach();
    _errors = null;
    _lifecycle?.detach();
    _lifecycle = null;
    store.add(LogSource.app, 'recording_stopped');
    _probe?.detach();
    _probe = null;
    _active = null;
    _finished = store.header.session;
    await settings.saveDiagnosticsSession(null);
    await _sink?.close();
    _sink = null;

    final background = await _readBackgroundStream(store.header.session);
    return background.isEmpty
        ? store.export()
        : mergeSessions(store.export(), background);
  }

  /// Throws the session away, files included — whether it is still running or
  /// was already stopped for review. For the user backing out of a report: the
  /// log must not outlive the intent to send it.
  Future<void> discard() async {
    final session = _active?.header.session ?? _finished;
    _errors?.detach();
    _errors = null;
    _lifecycle?.detach();
    _lifecycle = null;
    _probe?.detach();
    _probe = null;
    _active = null;
    _finished = null;
    await settings.saveDiagnosticsSession(null);
    await _sink?.close();
    _sink = null;
    if (session != null) await _deleteSessionFiles(session);
  }

  /// "The bug just happened." Cheapest thing that cuts the search through a
  /// few thousand records.
  void mark() => _active?.mark();

  /// The session an app that died mid-recording left on disk, as JSONL. Empty
  /// string when there is nothing worth offering — no files, or a file holding
  /// only its header because the crash came before anything was logged.
  ///
  /// This is the case the durable mirror exists for: a native crash or an
  /// out-of-memory kill takes the buffer with it, but every line was already
  /// written and redacted on the way in.
  Future<String> recover(String session) async {
    final directory = await _resolveQuietly();
    if (directory == null) return '';
    final ui = await LogFileSink(
      LogFileSink.fileFor(directory, session, LogStream.ui),
    ).read();
    final background = await _readBackgroundStream(session);
    final log = ui.isEmpty
        ? background
        : background.isEmpty
            ? ui
            : mergeSessions(ui, background);
    // A header and nothing else is not a report; offering it would only ask the
    // user to decide about an empty file.
    if (const LineSplitter().convert(log).length < 2) return '';
    // The recovered session takes the place of one just stopped: from here on
    // [discard] is what deletes it, exactly as after a normal review.
    _finished = session;
    return log;
  }

  /// Deletes a session by id, for a recovered log the user did not want.
  Future<void> discardSession(String session) async {
    if (_finished == session) _finished = null;
    await _deleteSessionFiles(session);
  }

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

  /// Deletes what earlier recordings left behind, keeping only [session].
  ///
  /// Nothing else ever removes these files: a session that was stopped and
  /// never sent, or one whose app died mid-recording, would otherwise sit on
  /// the device for the life of the install. Starting a new recording is the
  /// moment the old ones stop being of any use to anybody.
  Future<void> _sweepOtherSessions(Directory directory, String session) async {
    try {
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        final ours = name.startsWith('session-') && name.endsWith('.jsonl');
        if (!ours || name.contains(session)) continue;
        await entity.delete();
      }
    } on Object {
      // Best effort: a file that is locked or already gone must not be the
      // reason a recording refuses to start.
    }
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
