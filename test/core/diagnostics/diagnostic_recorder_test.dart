import 'dart:convert';
import 'dart:io';

import 'package:bambuddy_mobile/core/diagnostics/diagnostic_recorder.dart';
import 'package:bambuddy_mobile/core/diagnostics/log_event.dart';
import 'package:bambuddy_mobile/core/diagnostics/log_file_sink.dart';
import 'package:bambuddy_mobile/core/diagnostics/session_facts.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
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
}
