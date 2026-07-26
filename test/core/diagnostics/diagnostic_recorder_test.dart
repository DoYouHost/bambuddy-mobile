import 'dart:convert';
import 'dart:io';

import 'package:bambuddy_mobile/core/diagnostics/diagnostic_recorder.dart';
import 'package:bambuddy_mobile/core/diagnostics/log_event.dart';
import 'package:bambuddy_mobile/core/diagnostics/log_file_sink.dart';
import 'package:bambuddy_mobile/core/diagnostics/session_facts.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late SettingsRepository settings;
  late DiagnosticRecorder recorder;

  const facts = SessionFacts(
    app: '0.11.2+1102',
    flavor: 'mobile',
    os: 'Android 15',
    locale: 'pl-PL',
    auth: 'apikey',
    secrets: {'sk-live-abcdef': '[APIKEY]', 'bambuddy.local': '[HOST]'},
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = SettingsRepository(await SharedPreferences.getInstance());
    dir = Directory.systemTemp.createTempSync('bambuddy_diag');
    recorder = DiagnosticRecorder(
      settings: settings,
      loadFacts: () async => facts,
      resolveDirectory: () async => dir,
    );
  });

  tearDown(() async {
    await recorder.discard();
    dir.deleteSync(recursive: true);
  });

  List<Map<String, dynamic>> parse(String jsonl) => [
        for (final line in const LineSplitter().convert(jsonl))
          jsonDecode(line) as Map<String, dynamic>,
      ];

  test('a session opens with a header built from the facts', () async {
    await recorder.start();
    final header = parse(await recorder.stop()).first;

    expect(header['app'], '0.11.2+1102');
    expect(header['flavor'], 'mobile');
    expect(header['os'], 'Android 15');
    expect(header['locale'], 'pl-PL');
    expect(header['auth'], 'apikey');
    expect((header['session'] as String), hasLength(32));
  });

  test('brackets the session with start and stop markers', () async {
    await recorder.start();
    final records = parse(await recorder.stop()).skip(1).toList();

    expect(records.first['evt'], 'recording_started');
    expect(records.last['evt'], 'recording_stopped');
  });

  test('exposes the buffer only while recording', () async {
    expect(DiagnosticRecorder.active, isNull);
    expect(DiagnosticRecorder.isRecording, isFalse);

    await recorder.start();
    expect(DiagnosticRecorder.active, isNotNull);
    expect(DiagnosticRecorder.isRecording, isTrue);

    await recorder.stop();
    expect(DiagnosticRecorder.active, isNull);
  });

  test('instrumentation writes through the static handle', () async {
    await recorder.start();
    DiagnosticRecorder.active?.add(
      LogSource.http,
      'response',
      fields: const {'method': 'GET', 'path': '/printers', 'status': 502},
    );

    final records = parse(await recorder.stop());
    expect(records.any((r) => r['evt'] == 'response' && r['status'] == 502),
        isTrue);
  });

  test('the session redactor is seeded from the facts', () async {
    await recorder.start();
    DiagnosticRecorder.active?.add(
      LogSource.err,
      'uncaught',
      fields: const {'msg': 'rejected sk-live-abcdef by bambuddy.local'},
    );

    final log = await recorder.stop();
    expect(log, contains('rejected [APIKEY] by [HOST]'));
    expect(log, isNot(contains('sk-live-abcdef')));
  });

  test('publishes the session id for the background isolate', () async {
    await recorder.start();
    final session = settings.loadDiagnosticsSession();

    expect(session, isNotNull);
    expect(session, hasLength(32));

    await recorder.stop();
    expect(settings.loadDiagnosticsSession(), isNull);
  });

  test('mirrors the stream to disk so a crash mid-recording survives',
      () async {
    await recorder.start();
    DiagnosticRecorder.active?.add(LogSource.app, 'something_happened');
    final session = settings.loadDiagnosticsSession()!;
    await recorder.stop();

    final onDisk =
        await LogFileSink(LogFileSink.fileFor(dir, session, LogStream.ui))
            .read();
    expect(onDisk, contains('something_happened'));
  });

  test('merges the background stream found on disk', () async {
    await recorder.start();
    final session = settings.loadDiagnosticsSession()!;

    // Stands in for the FGS isolate, which writes its own file with its own
    // header while the UI session runs.
    final fgs = LogFileSink(LogFileSink.fileFor(dir, session, LogStream.fgs));
    await fgs.writeHeader(LogHeader(
      ts: DateTime.now().toUtc(),
      session: session,
      app: '0.11.2+1102',
      flavor: 'mobile',
      stream: LogStream.fgs,
    ));
    fgs.writeLine('{"t":10,"src":"fgs","evt":"cycle"}');
    await fgs.close();

    final merged = parse(await recorder.stop());
    expect(merged.first['stream'], 'merged');
    expect(merged.any((r) => r['evt'] == 'cycle'), isTrue);
  });

  test('starting twice keeps the first session', () async {
    await recorder.start();
    final first = settings.loadDiagnosticsSession();

    await recorder.start();

    expect(settings.loadDiagnosticsSession(), first);
  });

  test('stop without start yields nothing', () async {
    expect(await recorder.stop(), isEmpty);
  });

  test('discard deletes both stream files and clears the flag', () async {
    await recorder.start();
    final session = settings.loadDiagnosticsSession()!;
    DiagnosticRecorder.active?.add(LogSource.app, 'x');

    await recorder.discard();

    expect(settings.loadDiagnosticsSession(), isNull);
    expect(DiagnosticRecorder.active, isNull);
    expect(LogFileSink.fileFor(dir, session, LogStream.ui).existsSync(),
        isFalse);
  });

  test('discarding after the review deletes the files too', () async {
    // The only discard the app actually offers: the button lives on the review
    // screen, which is reached after stopping.
    await recorder.start();
    final session = settings.loadDiagnosticsSession()!;
    DiagnosticRecorder.active?.add(LogSource.app, 'x');
    await recorder.stop();

    await recorder.discard();

    expect(dir.listSync(), isEmpty);
    expect(
      LogFileSink.fileFor(dir, session, LogStream.ui).existsSync(),
      isFalse,
    );
  });

  test('a new recording sweeps what earlier ones left behind', () async {
    await recorder.start();
    final abandoned = settings.loadDiagnosticsSession()!;
    // Stopped and never sent, the way a user who forgot about it leaves it.
    await recorder.stop();
    // As if the app had died mid-recording: the isolate's file has no owner.
    LogFileSink.fileFor(dir, 'deadbeef', LogStream.fgs).writeAsStringSync('{}');
    final unrelated = File('${dir.path}/notes.txt')..writeAsStringSync('keep');

    await recorder.start();
    final current = settings.loadDiagnosticsSession()!;

    final left = dir.listSync().map((e) => e.uri.pathSegments.last).toSet();
    expect(left, {
      LogFileSink.fileFor(dir, current, LogStream.ui).uri.pathSegments.last,
      unrelated.uri.pathSegments.last,
    });
    expect(left.any((name) => name.contains(abandoned)), isFalse);
  });

  /// Waits for the mirror to catch up. Lines are written fire-and-forget
  /// through a future chain, so "it is on disk" is not true the instant the
  /// record is added.
  Future<void> untilOnDisk(File file, String needle) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      if (file.existsSync() && file.readAsStringSync().contains(needle)) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('"$needle" never reached ${file.path}');
  }

  test('hands back the session an app died in the middle of', () async {
    await recorder.start();
    final session = settings.loadDiagnosticsSession()!;
    DiagnosticRecorder.active?.add(LogSource.app, 'the_last_thing_it_saw');
    // No stop and no discard: the process is gone, the flag stays in prefs and
    // the file is whatever the mirror had already flushed.
    await untilOnDisk(
      LogFileSink.fileFor(dir, session, LogStream.ui),
      'the_last_thing_it_saw',
    );

    final recovered = await recorder.recover(session);

    expect(recovered, contains('the_last_thing_it_saw'));
    expect(parse(recovered).first['session'], session);
  });

  test('merges the background stream into a recovered session', () async {
    await recorder.start();
    final session = settings.loadDiagnosticsSession()!;
    DiagnosticRecorder.active?.add(LogSource.app, 'from_the_ui');
    final fgs = LogFileSink(LogFileSink.fileFor(dir, session, LogStream.fgs));
    await fgs.writeHeader(
      LogHeader(
        ts: DateTime.now().toUtc(),
        session: session,
        app: '0.11.2+1102',
        flavor: 'mobile',
        stream: LogStream.fgs,
      ),
    );
    fgs.writeLine('{"t":10,"src":"fgs","evt":"cycle"}');
    await fgs.close();

    final recovered = await recorder.recover(session);

    expect(recovered, contains('from_the_ui'));
    expect(recovered, contains('cycle'));
  });

  test('offers nothing when the crash beat the first record', () async {
    // A file holding only its header is not a report; asking the user to decide
    // about it is worse than saying nothing.
    await recorder.start();
    final session = settings.loadDiagnosticsSession()!;
    // Stopped first so the sink is closed and cannot append behind the test.
    await recorder.stop();
    LogFileSink.fileFor(dir, session, LogStream.ui)
        .writeAsStringSync('{"v":1,"session":"$session"}\n');

    expect(await recorder.recover(session), isEmpty);
  });

  test('a recovered session can still be thrown away', () async {
    await recorder.start();
    final session = settings.loadDiagnosticsSession()!;
    DiagnosticRecorder.active?.add(LogSource.app, 'x');
    await recorder.recover(session);

    // Discarding what is on the review screen, whether it got there by being
    // stopped or by surviving a crash.
    await recorder.discard();

    expect(LogFileSink.fileFor(dir, session, LogStream.ui).existsSync(), isFalse);
  });

  test('an unwritable directory degrades to a memory-only session', () async {
    final memoryOnly = DiagnosticRecorder(
      settings: settings,
      loadFacts: () async => facts,
      resolveDirectory: () async => throw const FileSystemException('nope'),
    );

    await memoryOnly.start();
    DiagnosticRecorder.active?.add(LogSource.app, 'still_recorded');
    final log = await memoryOnly.stop();

    expect(log, contains('still_recorded'));
    expect(dir.listSync(), isEmpty);
  });

  test('an uncaught exception lands in the session, and only while it runs',
      () async {
    final beforeAnyRecording = FlutterError.onError;
    void crash(String message) => FlutterError.reportError(
          FlutterErrorDetails(exception: StateError(message)),
        );

    crash('before');
    await recorder.start();
    crash('during');
    final log = await recorder.stop();
    crash('after');

    expect(log, contains('"evt":"uncaught"'));
    expect(log, contains('Bad state: during'));
    expect(log, isNot(contains('before')));
    // The session put Flutter's own handling back exactly as it found it.
    expect(FlutterError.onError, same(beforeAnyRecording));
  });
}
