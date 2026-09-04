import 'dart:convert';
import 'dart:io';

import 'package:bambuddy_mobile/core/diagnostics/diagnostic_recorder.dart';
import 'package:bambuddy_mobile/core/diagnostics/log_event.dart';
import 'package:bambuddy_mobile/core/diagnostics/log_file_sink.dart';
import 'package:bambuddy_mobile/core/diagnostics/log_store.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The background isolates' half of a recording: a stream that continues one the
/// UI started, written straight to disk because the heap it lives on can be taken
/// away at any moment.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = 'sess-abc';
  final sessionStart = DateTime.utc(2026, 7, 25, 12);

  late Directory dir;
  late SettingsRepository settings;
  late DateTime now;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = SettingsRepository(await SharedPreferences.getInstance());
    dir = Directory.systemTemp.createTempSync('bambuddy_fgs');
    now = sessionStart.add(const Duration(seconds: 30));
  });

  tearDown(() => dir.deleteSync(recursive: true));

  /// The stream the UI would have left on disk before going into the background.
  Future<void> writeUiStream({
    String forSession = session,
    DateTime? ts,
    String? firstLine,
  }) async {
    final file = LogFileSink.fileFor(dir, session, LogStream.ui);
    final sink = LogFileSink(file);
    if (firstLine != null) {
      sink.writeLine(firstLine);
    } else {
      await sink.writeHeader(
        LogHeader(
          ts: ts ?? sessionStart,
          session: forSession,
          app: '0.11.3+1103',
          flavor: 'mobile',
          os: 'Android 15',
          locale: 'pl-PL',
          auth: 'apiKey',
          serverUrl: ServerFingerprint.tryParse('https://nas.example:8443'),
        ),
      );
    }
    sink.writeLine('{"t":0,"src":"app","evt":"recording_started"}');
    await sink.close();
  }

  Future<BackgroundRecording?> start({
    LogStream stream = LogStream.fgs,
    Map<String, String> secrets = const {},
  }) =>
      DiagnosticRecorder.startBackground(
        settings: settings,
        stream: stream,
        resolveDirectory: () async => dir,
        loadSecrets: () async => secrets,
        clock: () => now,
        attachErrors: false,
      );

  /// Skips what it cannot parse, the way `mergeSessions` and `LogSummary` do — a
  /// stream read off disk can end in a line a killed process never finished.
  List<Map<String, Object?>> linesOf(LogStream stream) {
    final file = LogFileSink.fileFor(dir, session, stream);
    if (!file.existsSync()) return const [];
    final rows = <Map<String, Object?>>[];
    for (final line in const LineSplitter().convert(file.readAsStringSync())) {
      if (line.trim().isEmpty) continue;
      try {
        if (jsonDecode(line) case final Map<String, Object?> row) rows.add(row);
      } on FormatException {
        continue;
      }
    }
    return rows;
  }

  group('refuses to record', () {
    test('when no recording is running', () async {
      await writeUiStream();

      expect(await start(), isNull);
      expect(linesOf(LogStream.fgs), isEmpty);
    });

    test('when the UI left no stream to continue', () async {
      await settings.saveDiagnosticsSession(session);

      // Nothing to merge into, and a file with a clock of its own would be worse
      // than no file at all.
      expect(await start(), isNull);
    });

    test('when the first line of the UI stream is a record, not a header',
        () async {
      // Reachable: the header write is allowed to fail silently while the writes
      // after it succeed. Accepted as a header it would have no `ts`, and the merge
      // would drop this whole stream from every report.
      await settings.saveDiagnosticsSession(session);
      await writeUiStream(firstLine: '{"t":5,"src":"ui","evt":"tap"}');

      expect(await start(), isNull);
    });

    test('when the UI header belongs to a different session', () async {
      await settings.saveDiagnosticsSession(session);
      await writeUiStream(forSession: 'someone-else');

      expect(await start(), isNull);
    });

    test('when the session already ran out of its five minutes', () async {
      await settings.saveDiagnosticsSession(session);
      await writeUiStream();
      now = sessionStart.add(recordingLimit).add(const Duration(seconds: 1));

      expect(await start(), isNull);
    });

    test('when the clock moved backwards past the session start', () async {
      // Without the sign check this granted a budget *longer* than the limit while
      // every record stamped itself `t:0` — an unbounded file collapsed onto one
      // instant of the timeline.
      await settings.saveDiagnosticsSession(session);
      await writeUiStream();
      now = sessionStart.subtract(const Duration(minutes: 20));

      expect(await start(), isNull);
    });

    test('when this isolate already has a stream of its own', () async {
      // The notification-action callback runs in whichever isolate the plugin
      // picked, and two of the three are already recording. There it must write
      // into the stream that exists rather than open a second file for the same
      // session on the same heap.
      await settings.saveDiagnosticsSession(session);
      await writeUiStream();
      final first = await start();
      addTearDown(() => first!.stop());

      expect(await start(stream: LogStream.action), isNull);
      expect(DiagnosticRecorder.active, same(first!.store));
      expect(
        LogFileSink.fileFor(dir, session, LogStream.action).existsSync(),
        isFalse,
      );
    });

    test('when the directory cannot be resolved', () async {
      await settings.saveDiagnosticsSession(session);
      await writeUiStream();

      final recording = await DiagnosticRecorder.startBackground(
        settings: settings,
        stream: LogStream.fgs,
        resolveDirectory: () async => throw const FileSystemException('nope'),
        clock: () => now,
        attachErrors: false,
      );

      // The service must go on monitoring: a broken recorder cannot be the reason
      // the thing it observes stops working.
      expect(recording, isNull);
      expect(DiagnosticRecorder.isRecording, isFalse);
    });
  });

  group('continues the session the UI started', () {
    setUp(() async {
      await settings.saveDiagnosticsSession(session);
      await writeUiStream();
    });

    test('inherits the header, retagged as its own stream', () async {
      final recording = await start();
      await recording!.stop();

      final header = linesOf(LogStream.fgs).first;
      expect(header['stream'], 'fgs');
      expect(header['session'], session);
      // One session, one clock: the merge then shifts nothing and `t` values from
      // the two files are directly comparable.
      expect(header['ts'], sessionStart.toIso8601String());
      // Facts came off disk, so they cannot drift between the two files.
      expect(header['app'], '0.11.3+1103');
      expect(header['os'], 'Android 15');
      expect(header['scheme'], 'https');
      expect(header['port'], 8443);
    });

    test('stamps records with the session clock, not with its own start',
        () async {
      final recording = await start();
      recording!.store.add(LogSource.fgs, 'start');
      await recording.stop();

      expect(linesOf(LogStream.fgs).last['t'], 30000); // 30 s into the session
    });

    test('a second start appends without a second header', () async {
      // Android restarts this service after a swipe or a kill, so one recording is
      // several stores. A stray header mid-file is read as a record at t=0 — in
      // front of everything, with no source and no event name.
      final first = await start();
      first!.store.add(LogSource.fgs, 'start');
      await first.stop();

      now = sessionStart.add(const Duration(minutes: 2));
      final second = await start();
      second!.store.add(LogSource.fgs, 'start');
      await second.stop();

      final lines = linesOf(LogStream.fgs);
      expect(lines.where((l) => l.containsKey('session')), hasLength(1));
      expect([for (final l in lines.skip(1)) l['t']], [30000, 120000]);
    });

    test('a torn last line does not swallow the next record', () async {
      final first = await start();
      first!.store.add(LogSource.fgs, 'start');
      await first.stop();
      // What a killed process leaves behind: no closing newline.
      final file = LogFileSink.fileFor(dir, session, LogStream.fgs);
      file.writeAsStringSync('{"t":1,"src":"fgs","ev', mode: FileMode.append);

      final second = await start();
      second!.store.add(LogSource.fgs, 'destroy');
      await second.stop();

      // The torn line costs itself; the record after it parses.
      expect(linesOf(LogStream.fgs).last['evt'], 'destroy');
    });

    test('the deadline belongs to the session, not to the store', () async {
      // Every restart would otherwise begin the five minutes again, so a service
      // crash-looping every few seconds could record for an hour.
      now = sessionStart.add(const Duration(minutes: 4, seconds: 55));
      final recording = await start();
      recording!.store.add(LogSource.fgs, 'start');
      now = sessionStart.add(recordingLimit).add(const Duration(seconds: 1));
      recording.store.add(LogSource.ws, 'frame');
      await recording.stop();

      final last = linesOf(LogStream.fgs).last;
      expect(last['evt'], 'limit_reached');
      // The limit reported is the session's, not what was left of it.
      expect(last['minutes'], recordingLimit.inMinutes);
    });

    test('redacts with secrets of its own, which the header cannot carry',
        () async {
      // The header holds no secrets by design, so a stream that only inherited it
      // would write the user's hostname into the first socket error. A failed
      // lookup is not a URL, so only an exact value catches it.
      final recording = await start(secrets: {'nas.example': '[HOST]'});
      recording!.store.add(
        LogSource.ws,
        'connect_error',
        fields: {'msg': "Failed host lookup: 'nas.example'"},
      );
      await recording.stop();

      expect(linesOf(LogStream.fgs).last['msg'], contains('[HOST]'));
      expect(linesOf(LogStream.fgs).last['msg'], isNot(contains('nas')));
    });

    test('owns the static while it lives and lets go of it after', () async {
      final recording = await start();
      expect(DiagnosticRecorder.active, same(recording!.store));

      await recording.stop();

      // The isolate outlives the recording — a leftover store would keep a dead
      // sink alive and swallow every record after it.
      expect(DiagnosticRecorder.isRecording, isFalse);
    });

    test('a second stream of the same session gets its own file', () async {
      final fgs = await start();
      await fgs!.stop();
      final action = await start(stream: LogStream.action);
      action!.store.add(LogSource.notif, 'action');
      await action.stop();

      expect(linesOf(LogStream.action).first['stream'], 'action');
      expect(linesOf(LogStream.action).last['evt'], 'action');
    });

    test('a later session gets its own file and leaves the earlier one alone',
        () async {
      // What the isolate does when the app tells it the recording changed: close
      // the stream it has, then open the new one. A service that outlived the
      // previous recording is the reason this path exists at all.
      final first = await start();
      first!.store.add(LogSource.fgs, 'start');
      await first.stop();
      final firstLines = linesOf(LogStream.fgs).length;

      await settings.saveDiagnosticsSession('sess-second');
      final secondUi = LogFileSink(
        LogFileSink.fileFor(dir, 'sess-second', LogStream.ui),
      );
      await secondUi.writeHeader(
        LogHeader(
          ts: now,
          session: 'sess-second',
          app: '0.11.3+1103',
          flavor: 'mobile',
        ),
      );
      await secondUi.close();

      final second = await start();
      second!.store.add(LogSource.fgs, 'attach');
      await second.stop();

      expect(linesOf(LogStream.fgs), hasLength(firstLines));
      final other = LogFileSink.fileFor(dir, 'sess-second', LogStream.fgs);
      expect(other.readAsStringSync(), contains('"evt":"attach"'));
    });

    test('restores the error handlers it installed', () async {
      final mine = FlutterError.onError;
      final recording = await DiagnosticRecorder.startBackground(
        settings: settings,
        stream: LogStream.fgs,
        resolveDirectory: () async => dir,
        clock: () => now,
      );
      expect(FlutterError.onError, isNot(same(mine)));

      await recording!.stop();

      expect(FlutterError.onError, same(mine));
    });
  });

  /// `startAction` is the one call the woken isolates make — a notification
  /// action, a request relayed from the watch — instead of each spelling out
  /// the same four arguments.
  group('an isolate woken for one job', () {
    Future<BackgroundRecording?> startAction({
      Future<SettingsRepository> Function()? openSettings,
    }) =>
        DiagnosticRecorder.startAction(
          openSettings: openSettings ?? () async => settings,
          resolveDirectory: () async => dir,
          clock: () => now,
        );

    test('records into the action stream, not the service\'s', () async {
      // Both are open at once whenever the phone is backgrounded, and two
      // writers on one file is a torn session.
      await settings.saveDiagnosticsSession(session);
      await writeUiStream();

      final recording = await startAction();
      expect(recording, isNotNull);
      recording!.store.add(LogSource.app, 'wear_wake');
      await recording.stop();

      expect(
        linesOf(LogStream.action).map((r) => r['evt']),
        contains('wear_wake'),
      );
      expect(linesOf(LogStream.fgs), isEmpty);
    });

    test('stands down when this isolate is already recording', () async {
      await settings.saveDiagnosticsSession(session);
      await writeUiStream();
      final first = await start();
      addTearDown(() => first!.stop());

      expect(await startAction(), isNull);
      expect(DiagnosticRecorder.active, same(first!.store));
    });

    test('a platform read that fails costs the recording, not the job',
        () async {
      // The caller is carrying out the user's tap; a keystore that cannot be
      // read must leave it unrecorded, never undone.
      expect(
        await startAction(
          openSettings: () => Future.error(StateError('keystore')),
        ),
        isNull,
      );
    });
  });
}
