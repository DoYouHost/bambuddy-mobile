import 'dart:async';
import 'dart:convert';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:bambuddy_mobile/core/diagnostics/diagnostics_wiring.dart';
import 'package:bambuddy_mobile/core/diagnostics/report_config.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:bambuddy_mobile/features/announcements/app_update.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(PlayCheckProbe.forget);

  // Through the app's own providers, so both wirings are under test: the
  // checker reports to the probe, and the recorder repeats it at its start.
  Future<List<Map<String, dynamic>>> recordedChecks({
    required bool askedBeforeRecording,
  }) async {
    PackageInfo.setMockInitialValues(
      appName: 'app',
      packageName: 'app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
      installerStore: 'dev.imranr.obtainium',
    );
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        settingsRepositoryProvider.overrideWithValue(SettingsRepository(prefs)),
        sessionFactsProvider.overrideWithValue(
          () async => const SessionFacts(app: '1.0.0+1'),
        ),
      ],
    );
    addTearDown(container.dispose);
    final recorder = container.read(diagnosticRecorderProvider);
    addTearDown(recorder.discard);

    if (!askedBeforeRecording) await recorder.start();
    container.read(appUpdateProvider);
    await pumpEventQueue();
    if (askedBeforeRecording) await recorder.start();

    return [
      for (final line in const LineSplitter().convert(await recorder.stop()))
        if (jsonDecode(line) case final Map<String, dynamic> row
            when row['evt'] == 'play_check')
          row,
    ];
  }

  test(
    'an answer that lands while the recording starts is written once',
    () async {
      final sessions = _GatedSessions();
      final recorder = DiagnosticRecorder(
        sessions: sessions,
        redactor: bambuddyRedactor,
        sessionDuration: recordingLimit,
        sessionBytes: recordingSizeLimit,
        loadFacts: () async => const SessionFacts(app: '1.0.0+1'),
        resolveDirectory: () async => null,
        listeners: const [PlayCheckProbe()],
      );
      addTearDown(recorder.discard);

      final started = recorder.start();
      await pumpEventQueue();
      PlayCheckProbe.answered({'installer': 'com.android.vending'});
      sessions.gate.complete();
      await started;

      final events = [
        for (final line in const LineSplitter().convert(await recorder.stop()))
          (jsonDecode(line) as Map<String, dynamic>)['evt'],
      ];
      expect(events.where((e) => e == 'play_check'), hasLength(1));
      expect(
        events.indexOf('play_check'),
        greaterThan(events.indexOf('recording_started')),
      );
    },
  );

  for (final before in [true, false]) {
    test('the installer is readable in a recording, '
        'Play asked ${before ? 'before' : 'during'} it', () async {
      final checks = await recordedChecks(askedBeforeRecording: before);
      expect(checks, [containsPair('installer', 'dev.imranr.obtainium')]);
    });
  }
}

/// Holds the recorder between publishing its buffer and opening its listeners.
class _GatedSessions implements DiagnosticsSessionStore {
  final gate = Completer<void>();
  String? _session;

  @override
  String? loadSession() => _session;

  @override
  Future<void> saveSession(String? session) async {
    if (session != null) await gate.future;
    _session = session;
  }
}
