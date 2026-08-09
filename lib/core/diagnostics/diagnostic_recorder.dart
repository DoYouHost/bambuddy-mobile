import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../settings/settings_repository.dart';
import 'error_probe.dart';
import 'http_probe.dart';
import 'interaction_probe.dart';
import 'lifecycle_probe.dart';
import 'log_event.dart';
import 'report_config.dart';
import 'log_file_sink.dart';
import 'log_merge.dart';
import 'log_store.dart';
import 'navigation_probe.dart';
import 'session_facts.dart';
import 'ws_probe.dart';

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
/// - the live view — [WsProbe], owned by `WsClient` for the app's lifetime; like
///   the HTTP probe it reads [active] per event, and [stop] writes out its
///   pending frame counts so the last window isn't lost with the session
/// - the durable mirror of the UI stream, so a crash mid-recording still
///   leaves a log on disk
/// - the session id in [SettingsRepository], which is how a background isolate
///   learns that a recording is running
/// - notifications — `NotifProbe` and its decorator, which read [active] per
///   call and therefore write into whichever isolate's stream is theirs
///
/// ## The other isolates
///
/// [startBackground] opens a stream for an isolate that has its own heap and
/// therefore its own, always-null [active]: the foreground service, and the
/// engine the plugin spawns for a notification action. Each writes its own file,
/// [stop] and [recover] fold them all in, and every record they contribute is
/// stamped with the stream it came from.
///
/// This class stays the only owner of [active]. A public setter would be a way
/// for anything to point the app's buffer somewhere else.
class DiagnosticRecorder {
  DiagnosticRecorder({
    required this.settings,
    required this.loadFacts,
    this.resolveDirectory = diagnosticsDirectory,
    this.ringRecords = ringRecordLimit,
    this.ringChars = ringCharLimit,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SettingsRepository settings;
  final Future<SessionFacts> Function() loadFacts;

  /// Where session files go. Returning null keeps the session in memory only —
  /// which is what tests do, and what a device with no writable support
  /// directory degrades to.
  final Future<Directory?> Function() resolveDirectory;

  /// The ring's runaway guards, forwarded to the session's [LogStore]. Only the
  /// tests move them: proving that eviction no longer costs the report takes a
  /// ring that fills in a handful of records, and filling the real one would mean
  /// writing four megabytes through a sink that flushes every line.
  final int ringRecords;
  final int ringChars;

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

  /// [onLimitReached] fires when the store closes itself on one of its ceilings,
  /// with the ceiling's name (`time` or `size`). The caller owns what that means
  /// for the UI; this class only knows the recording stopped taking records.
  Future<void> start({void Function(String limit)? onLimitReached}) async {
    if (_active != null) return;

    final session = LogHeader.newSessionId();
    final facts = await loadFacts();
    final redactor = bambuddyRedactor();
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
      maxRecords: ringRecords,
      maxChars: ringChars,
      onLine: sink?.writeLine,
      onClosed: onLimitReached,
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
    // Same reason for the live view: the socket is normally up long before
    // anybody starts recording, so its `connect` and `open` are already history.
    WsProbe.openSession();
    // Response fingerprints from an earlier session would make this session's
    // first answer from each endpoint read as "unchanged".
    HttpProbe.openSession();
  }

  /// Stops and returns the session as JSONL, merging the background isolate's
  /// stream when there is one. Empty string if nothing was recording.
  Future<String> stop() async {
    final store = _active;
    if (store == null) return '';

    // Before the closing marker, so a burst still running when the user hits
    // stop has its count inside the session rather than after its end. The same
    // goes for frames counted since the last window was written out.
    _errors?.detach();
    _errors = null;
    WsProbe.flushAll();
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

    return _withBackgroundStreams(store.header.session, await _uiStream(store));
  }

  /// The session's UI stream, taken from its file rather than from the ring.
  ///
  /// The ring evicts its oldest records once it hits its memory caps, and
  /// [LogStore.export] can only read what the ring still holds — so a session
  /// busy enough to rotate used to reach the report with its start already gone,
  /// while the file next to it held all of it. The file is the session; the ring
  /// is a heap guard. What bounds the report is [recordingSizeLimit], the same
  /// ceiling that bounds the file.
  ///
  /// Falls back to the ring when there is no usable file: a device with no
  /// writable support directory records in memory only, and so do the tests. A
  /// file holding nothing but its header counts as unusable — the writes never
  /// landed (a full disk, a permission the platform took back), and the records
  /// are still in memory.
  Future<String> _uiStream(LogStore store) async {
    final directory = await _resolveQuietly();
    if (directory == null) return store.export();
    final ordered = orderSession(
      await LogFileSink(
        LogFileSink.fileFor(directory, store.header.session, LogStream.ui),
      ).read(),
    );
    return const LineSplitter().convert(ordered).length < 2
        ? store.export()
        : ordered;
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

  /// Waits for the records added so far to reach the mirror file.
  ///
  /// Only the crash paths need it: [stop] and [discard] close the sink and so
  /// already wait, while [recover] reads a session nobody stopped — by design,
  /// since the process that was writing it is gone. Nothing in the app calls
  /// this; a test that reads the file behind a live recording does.
  @visibleForTesting
  Future<void> flushMirror() async => _sink?.flush();

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
    final ui = orderSession(
      await LogFileSink(
        LogFileSink.fileFor(directory, session, LogStream.ui),
      ).read(),
    );
    // No UI stream, no report. A background stream on its own is in *arrival*
    // order — the sort lives in `export` and in the merge, neither of which ran —
    // and it can be a file a killed isolate recreated by appending to a path the
    // UI had already deleted, i.e. records with no header at all. Offering that
    // as a bug report would be offering something we cannot vouch for.
    if (ui.isEmpty) return '';
    final log = await _withBackgroundStreams(session, ui);
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

  /// Folds every background stream of [session] into [ui], in stream order.
  ///
  /// Merging is chained rather than generalised to N inputs: each pass keeps the
  /// earliest `ts` as the origin, so the next one shifts nothing already placed.
  /// A throw is swallowed per stream — a mangled background file must cost at
  /// most itself, never the recording the user actually made.
  Future<String> _withBackgroundStreams(String session, String ui) async {
    final directory = await _resolveQuietly();
    if (directory == null) return ui;
    var merged = ui;
    for (final stream in LogStream.values) {
      if (stream == LogStream.ui) continue;
      final jsonl = await LogFileSink(
        LogFileSink.fileFor(directory, session, stream),
      ).read();
      if (jsonl.isEmpty) continue;
      try {
        merged = mergeSessions(merged, jsonl);
      } on Object {
        // Keep what we had. `mergeSessions` promises this, and here it is enforced.
      }
    }
    return merged;
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

  /// Opens a background isolate's own stream for a recording the UI already
  /// started, or returns null when there is nothing to continue.
  ///
  /// A static on this class rather than a free function, because it is the only
  /// other thing allowed to set [active] — a public setter would be a way for any
  /// caller to hijack the UI's buffer.
  ///
  /// **Nothing here can throw.** The foreground service's `onStart` is called
  /// through a platform channel that swallows a Dart exception and reports success
  /// anyway: the service would stay up, its notification would keep saying
  /// "monitoring", and nothing would be monitored. A diagnostic recorder must not
  /// be able to cause the failure it exists to describe, so every step —
  /// preferences, directory, header read, header write — lives inside one guard
  /// whose only failure mode is returning null, with a deadline on the file work
  /// so a stuck disk cannot delay the socket either.
  ///
  /// The stream is strictly a *continuation* of the UI's:
  ///
  /// - the session id comes from [settings], which is how a recording started in
  ///   the app reaches an isolate with its own heap;
  /// - the header is the UI's header re-tagged, so `app`, `os`, `locale` and the
  ///   server fingerprint cannot drift between two files of one session, and no
  ///   `PackageInfo` call is needed here;
  /// - `ts` is therefore the *session's* start, which puts both streams on one
  ///   clock: the merge shifts nothing, and `t` values are directly comparable;
  /// - without a readable UI header we do not record at all. There would be
  ///   nothing to merge into, and an orphan file with a clock of its own is the
  ///   kind of silent wrongness this whole tor exists to remove.
  static Future<BackgroundRecording?> startBackground({
    required SettingsRepository settings,
    required LogStream stream,
    Future<Directory?> Function() resolveDirectory = diagnosticsDirectory,
    Future<Map<String, String>> Function()? loadSecrets,
    bool attachErrors = true,
    DateTime Function()? clock,
    Duration fileTimeout = const Duration(seconds: 2),
  }) async {
    if (_active != null) return null;
    LogFileSink? opened;
    try {
      final session = settings.loadDiagnosticsSession();
      if (session == null) return null;
      final now = (clock ?? DateTime.now)();

      final prepared = await Future(() async {
        final directory = await resolveDirectory();
        if (directory == null) return null;
        final header = LogHeader.tryParse(
          await LogFileSink(
            LogFileSink.fileFor(directory, session, LogStream.ui),
          ).readFirstLine(),
          session: session,
        );
        return header == null ? null : (directory, header);
      }).timeout(fileTimeout);
      if (prepared == null) return null;
      final (directory, uiHeader) = prepared;

      // Both ends matter. Past the ceiling there is nothing left to record, and a
      // *negative* elapsed — a clock corrected backwards mid-session — would hand
      // out a budget longer than the limit while every record stamped itself `t:0`,
      // i.e. an unbounded file collapsed onto one instant of the timeline.
      final elapsed = now.difference(uiHeader.ts);
      if (elapsed.isNegative || elapsed >= recordingLimit) return null;

      final redactor = bambuddyRedactor();
      (await loadSecrets?.call() ?? const <String, String>{})
          .forEach(redactor.remember);

      final file = LogFileSink.fileFor(directory, session, stream);
      final sink = opened = LogFileSink(file);
      if (await file.exists()) {
        // Second `onStart` of one recording: Android restarts this service after a
        // swipe or a kill, each time on a fresh heap. A second header mid-file
        // would be read as a record at the very front of the merged timeline, so
        // the existing one stands — the clock is the same either way. An empty line
        // first in case the previous run was killed mid-write; it is ignored
        // everywhere and keeps a torn record from swallowing the next one.
        if (!await sink.endsWithNewline()) sink.writeLine('');
      } else {
        await sink.writeHeader(uiHeader.copyWith(stream: stream));
      }

      final store = LogStore(
        header: uiHeader.copyWith(stream: stream),
        redactor: redactor,
        // The file is the only reader of this store — nothing here ever calls
        // `export`, so a ring is pure heap in the process whose OOM kill ends
        // monitoring. One record is the minimum the eviction loop keeps, and
        // `onLine` still fires for every one of them.
        maxRecords: 1,
        // Absolute deadline shared by every store of this session, so restarts
        // cannot hand themselves five fresh minutes each.
        openedAt: uiHeader.ts,
        clock: clock,
        onLine: sink.writeLine,
      );
      _active = store;
      final errors = attachErrors ? (ErrorProbe(store: store)..attach()) : null;
      return BackgroundRecording._(store, sink, errors);
    } on Object {
      // Including a TimeoutException. Recording is the thing that gives up here;
      // whatever called us carries on as if diagnostics did not exist. Anything
      // already opened is closed, so a half-started stream cannot leave a sink
      // holding queued lines nobody will ever flush.
      _active = null;
      await opened?.close();
      return null;
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

/// A background isolate's live stream: the buffer to write into, and the way to
/// close it.
///
/// Returned by [DiagnosticRecorder.startBackground]. [store] is public so the
/// caller can add its own records — the isolate's lifecycle, and the exceptions it
/// currently swallows — without a wrapper method per event.
class BackgroundRecording {
  const BackgroundRecording._(this.store, this._sink, this._errors);

  final LogStore store;
  final LogFileSink _sink;
  final ErrorProbe? _errors;

  /// Closes the stream: pending WebSocket repeat counts out, global error handlers
  /// restored, queued lines flushed to disk.
  ///
  /// Call it **after** the isolate's own teardown, not before. `WsClient.dispose`
  /// writes its last two records through the static — the disconnect reason and
  /// whatever frames were still being counted — so a stream closed first would
  /// lose the end of the WebSocket story. (`WsProbe.flushAll` below is then a
  /// no-op, because that dispose already flushed and unregistered its probe; it
  /// stays for the case where no client was ever built.)
  ///
  /// Between the caller's last record and here there should be no `await`: once
  /// `onDestroy` returns, the process is free to be killed.
  Future<void> stop() async {
    WsProbe.flushAll();
    if (DiagnosticRecorder.active == store) DiagnosticRecorder._active = null;
    _errors?.detach();
    await _sink.close();
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
