import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart' as ambient;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../auth/credentials_store.dart';
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
/// probes, and hands back the finished JSONL. The stream model it implements is
/// described in `docs/diagnostics-log.md`.
///
/// Probes come in two kinds. [InteractionProbe], [ErrorProbe] and
/// [LifecycleProbe] are attached for the session — with no store to write to
/// there is nothing to record, and an idle app keeps Flutter's own error
/// handling exactly as it was. `HttpProbe`, [NavigationProbe], [WsProbe] and
/// `NotifProbe` live for the app's lifetime and read [active] per event.
///
/// This class stays the only owner of [active] — a public setter would be a way
/// for anything to point the app's buffer somewhere else.
class DiagnosticRecorder {
  DiagnosticRecorder({
    required this.settings,
    required this.loadFacts,
    this.resolveDirectory = diagnosticsDirectory,
    this.ringRecords = ringRecordLimit,
    this.ringChars = ringCharLimit,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => ambient.clock.now());

  final SettingsRepository settings;
  final Future<SessionFacts> Function() loadFacts;

  /// Where session files go. Returning null keeps the session in memory only —
  /// which is what tests do, and what a device with no writable support
  /// directory degrades to.
  final Future<Directory?> Function() resolveDirectory;

  /// The ring's runaway guards, forwarded to the session's [LogStore]. Only the
  /// tests move them: proving eviction no longer costs the report takes a ring
  /// that fills in a handful of records.
  final int ringRecords;
  final int ringChars;

  final DateTime Function() _clock;

  static LogStore? _active;

  /// The buffer to log into, or null when nothing is being recorded.
  ///
  /// Dart does not evaluate the arguments of a `?.` call on null, so
  /// `DiagnosticRecorder.active?.add(…)` builds no field map while recording is
  /// off — which is what makes it acceptable on every HTTP response.
  static LogStore? get active => _active;

  static bool get isRecording => _active != null;

  LogFileSink? _sink;
  InteractionProbe? _probe;
  ErrorProbe? _errors;
  LifecycleProbe? _lifecycle;

  /// The session that [stop] just finished, kept so [discard] can still delete
  /// its files: the review screen is reached *after* stopping, so by then there
  /// is no active session to take the id from.
  String? _finished;

  /// [onLimitReached] fires when the store closes itself on one of its
  /// ceilings, with that ceiling's name (`time` or `size`).
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
    _errors = ErrorProbe(store: store)..attach();
    _lifecycle = LifecycleProbe(store: store)..attach();

    // The id doubles as the "recording is on" flag: two keys would be two
    // things to keep in sync across isolates.
    await settings.saveDiagnosticsSession(session);
    store.add(LogSource.app, 'recording_started');
    // The probes below only report *changes*, and the screen and the socket are
    // normally settled long before anybody starts recording — so without this
    // the first screen is named only once the user leaves it.
    final screen = NavigationProbe.screen;
    if (screen != null) {
      store.add(LogSource.ui, 'route', fields: {'to': screen});
    }
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

    // Before the closing marker, so a burst or a frame window still running
    // when the user hits stop has its count inside the session, not after it.
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
  /// [LogStore.export] can only read what the ring still holds, so a session
  /// busy enough to rotate used to reach the report with its start already
  /// gone. The file is the session; the ring is a heap guard.
  ///
  /// Falls back to the ring when there is no usable file — a device with no
  /// writable support directory, and the tests. A file holding nothing but its
  /// header counts as unusable: the writes never landed (a full disk, a
  /// permission the platform took back) and the records are still in memory.
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

  /// "The bug just happened."
  void mark() => _active?.mark();

  /// Waits for the records added so far to reach the mirror file. Nothing in
  /// the app needs it — [stop] and [discard] close the sink and so already
  /// wait; a test that reads the file behind a live recording does.
  @visibleForTesting
  Future<void> flushMirror() async => _sink?.flush();

  /// The session an app that died mid-recording left on disk, as JSONL. Empty
  /// string when there is nothing worth offering.
  Future<String> recover(String session) async {
    final directory = await _resolveQuietly();
    if (directory == null) return '';
    final ui = orderSession(
      await LogFileSink(
        LogFileSink.fileFor(directory, session, LogStream.ui),
      ).read(),
    );
    // No UI stream, no report. A background stream on its own is in *arrival*
    // order (the sort lives in `export` and in the merge, neither of which ran)
    // and can be a file a killed isolate recreated by appending to a path the
    // UI had already deleted — records with no header at all.
    if (ui.isEmpty) return '';
    final log = await _withBackgroundStreams(session, ui);
    // A header and nothing else is not a report.
    if (const LineSplitter().convert(log).length < 2) return '';
    // Takes the place of a session just stopped: from here on [discard] is what
    // deletes it, exactly as after a normal review.
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
  /// Chained rather than generalised to N inputs: each pass keeps the earliest
  /// `ts` as the origin, so the next shifts nothing already placed. A throw
  /// costs at most its own stream, never the recording the user made.
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
        // Keep what we had; `mergeSessions` promises this and here it is
        // enforced.
      }
    }
    return merged;
  }

  /// Deletes what earlier recordings left behind, keeping only [session].
  /// Nothing else removes these files, so a session stopped and never sent
  /// would otherwise sit on the device for the life of the install.
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
  /// started, or returns null when there is nothing to continue. A static here
  /// rather than a free function because it is the only other thing allowed to
  /// set [active]. Why the stream continues the UI's header rather than minting
  /// one: `docs/diagnostics-log.md`.
  ///
  /// **Nothing here can throw**, so every step lives inside one guard whose
  /// only failure mode is returning null, with a deadline on the file work so a
  /// stuck disk cannot delay the socket either.
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
      final now = (clock ?? ambient.clock.now)();

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

      // Both ends matter: a *negative* elapsed — a clock corrected backwards
      // mid-session — would hand out a budget longer than the limit while every
      // record stamped itself `t:0`, an unbounded file collapsed onto one
      // instant of the timeline.
      final elapsed = now.difference(uiHeader.ts);
      if (elapsed.isNegative || elapsed >= recordingLimit) return null;

      final redactor = bambuddyRedactor();
      (await loadSecrets?.call() ?? const <String, String>{})
          .forEach(redactor.remember);

      final file = LogFileSink.fileFor(directory, session, stream);
      final sink = opened = LogFileSink(file);
      if (await file.exists()) {
        // Second `onStart` of one recording — Android restarts this service on
        // a fresh heap. A header mid-file would read as a record at the very
        // front of the merged timeline, so the existing one stands; the clock
        // is the same either way. The empty line covers a previous run killed
        // mid-write, keeping a torn record from swallowing the next one.
        if (!await sink.endsWithNewline()) sink.writeLine('');
      } else {
        await sink.writeHeader(uiHeader.copyWith(stream: stream));
      }

      final store = LogStore(
        header: uiHeader.copyWith(stream: stream),
        redactor: redactor,
        // Nothing here calls `export`, so a ring would be pure heap in the
        // process whose OOM kill ends monitoring. One is the minimum the
        // eviction loop keeps, and `onLine` still fires for every record.
        maxRecords: 1,
        // Absolute deadline shared by every store of this session, so restarts
        // cannot hand themselves a fresh budget each.
        openedAt: uiHeader.ts,
        clock: clock,
        onLine: sink.writeLine,
      );
      _active = store;
      final errors = attachErrors ? (ErrorProbe(store: store)..attach()) : null;
      return BackgroundRecording._(store, sink, errors);
    } on Object {
      // Including a TimeoutException. Recording is what gives up here; the
      // caller carries on as if diagnostics did not exist. Closing what was
      // opened keeps a half-started stream from leaving queued lines behind.
      _active = null;
      await opened?.close();
      return null;
    }
  }

  /// [startBackground] for an isolate woken to do one job and gone a second
  /// later — a notification action, a request relayed from the watch. Null,
  /// the normal case, when there is nothing to record into.
  ///
  /// Those paths run in whichever isolate the platform picked, and two of the
  /// three are already recording; there the records land in the stream they
  /// belong to for free (`docs/logging-guide.md` §4). [LogStream.action] is
  /// the third one's stream: `fgs` is the service's file for the same session
  /// and two writers would tear it.
  ///
  /// **Never throws.** The caller is carrying out the user's tap, and
  /// diagnostics must not be why it does not happen — [SettingsRepository.opened]
  /// alone is a platform read that a locked keystore can fail. The parameters
  /// are test seams, as on [startBackground].
  static Future<BackgroundRecording?> startAction({
    Future<SettingsRepository> Function() openSettings =
        SettingsRepository.opened,
    Future<Directory?> Function() resolveDirectory = diagnosticsDirectory,
    DateTime Function()? clock,
  }) async {
    try {
      if (isRecording) return null;
      final settings = await openSettings();
      return await startBackground(
        settings: settings,
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
/// close it. [store] is public so the caller can add its own records without a
/// wrapper method per event.
class BackgroundRecording {
  const BackgroundRecording._(this.store, this._sink, this._errors);

  final LogStore store;
  final LogFileSink _sink;
  final ErrorProbe? _errors;

  /// Closes the stream: pending WebSocket repeat counts out, global error
  /// handlers restored, queued lines flushed to disk.
  ///
  /// Call it **after** the isolate's own teardown. `WsClient.dispose` writes
  /// its last two records through the static, so a stream closed first would
  /// lose the end of the WebSocket story; [WsProbe.flushAll] here is then a
  /// no-op and stays for the case where no client was ever built.
  ///
  /// No `await` between the caller's last record and here: once `onDestroy`
  /// returns, the process is free to be killed.
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
