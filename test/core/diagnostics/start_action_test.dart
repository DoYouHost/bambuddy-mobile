import 'dart:convert';
import 'dart:io';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bambuddy_mobile/core/diagnostics/diagnostics_wiring.dart';
import 'package:bambuddy_mobile/core/diagnostics/report_config.dart';

/// `startActionRecording` — bambuddy's one call for an isolate woken to do a
/// single job, and the arguments it spells out on the way to
/// `DiagnosticRecorder.startBackground`.
///
/// The background stream itself — continuing the UI's header, the ceilings, the
/// restart cases — is tested in `app_diagnostics`. What is left here is the
/// wiring that cannot move: this app's settings repository, its keystore, its
/// redactor and its ceiling.
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
          os: 'Android 15',
          locale: 'pl-PL',
          extra: const {'flavor': 'mobile', 'auth': 'apiKey'},
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
  }) => DiagnosticRecorder.startBackground(
    sessions: SettingsSessionStore(settings),
    redactor: bambuddyRedactor,
    sessionLimit: recordingLimit,
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

  /// `startAction` is the one call the woken isolates make — a notification
  /// action, a request relayed from the watch — instead of each spelling out
  /// the same four arguments.
  group('an isolate woken for one job', () {
    Future<BackgroundRecording?> startAction({
      Future<SettingsRepository> Function()? openSettings,
    }) => startActionRecording(
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

    test(
      'a platform read that fails costs the recording, not the job',
      () async {
        // The caller is carrying out the user's tap; a keystore that cannot be
        // read must leave it unrecorded, never undone.
        expect(
          await startAction(
            openSettings: () => Future.error(StateError('keystore')),
          ),
          isNull,
        );
      },
    );
  });
}
