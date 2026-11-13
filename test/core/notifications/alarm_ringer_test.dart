import 'dart:convert';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:bambuddy_mobile/core/diagnostics/report_config.dart';
import 'package:bambuddy_mobile/core/notifications/alarm_ringer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('page.codeberg.morganmlgman.bambuddy/alarm');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('ring sends what the native side reads', () async {
    MethodCall? sent;
    messenger.setMockMethodCallHandler(channel, (call) async {
      sent = call;
      return 'system';
    });
    final sound = await const AlarmRinger().ring(
      id: 42,
      title: 'T',
      body: 'B',
      stopLabel: 'Stop',
      minutes: 5,
      printer: 'X1C',
    );
    expect(sound, AlarmSound.system);
    expect(sent!.method, 'ring');
    expect(sent!.arguments, {
      'id': 42,
      'title': 'T',
      'body': 'B',
      'stop': 'Stop',
      'minutes': 5,
      'printer': 'X1C',
    });
  });

  test(
    'with no host nothing rang, and there is no permission to ask',
    () async {
      expect(
        await const AlarmRinger().ring(
          id: 1,
          title: '',
          body: '',
          stopLabel: '',
          minutes: 1,
          printer: '',
        ),
        isNull,
      );
      expect(await const AlarmRinger().canFullScreen(), isTrue);
    },
  );

  test('a host that refuses reads as nothing rang', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'boom'),
    );
    expect(
      await const AlarmRinger().ring(
        id: 1,
        title: '',
        body: '',
        stopLabel: '',
        minutes: 1,
        printer: '',
      ),
      isNull,
    );
  });

  group('reports from the native side', () {
    late DiagnosticRecorder recorder;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      recorder = DiagnosticRecorder(
        sessions: MemorySessionStore(),
        redactor: bambuddyRedactor,
        sessionDuration: recordingLimit,
        sessionBytes: recordingSizeLimit,
        loadFacts: () async => const SessionFacts(app: '0.17.2+1'),
        resolveDirectory: () async => null,
      );
      AlarmRinger.recordReports();
    });
    tearDown(() {
      channel.setMethodCallHandler(null);
      return recorder.discard();
    });

    /// What `PrintAlarm.report` sends, as the engine delivers it to Dart.
    Future<void> native(String method, Map<String, Object> fields) =>
        messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, fields),
          ),
          (_) {},
        );

    Future<List<Map<String, Object?>>> rows(
      Future<void> Function() body,
    ) async {
      await recorder.start();
      await body();
      return [
        for (final line in const LineSplitter().convert(await recorder.stop()))
          if (jsonDecode(line) case final Map<String, Object?> row
              when row['src'] == 'notif')
            row,
      ];
    }

    test('a stop is recorded with why, how long and on which sound', () async {
      final all = await rows(
        () => native('stopped', {
          'id': 18000001,
          'why': 'timeout',
          'rang_s': 600,
          'sound': 'player',
        }),
      );
      expect(all.single, containsPair('evt', 'alarm_stop'));
      expect(all.single, containsPair('nid', 18000001));
      expect(all.single, containsPair('why', 'timeout'));
      expect(all.single, containsPair('rang_s', 600));
      expect(all.single, containsPair('sound', 'player'));
    });

    test(
      'a dead player is recorded as a warning with the sound now on',
      () async {
        final all = await rows(
          () => native('recovered', {'id': 18000001, 'sound': 'system'}),
        );
        expect(all.single, containsPair('evt', 'alarm_recover'));
        expect(all.single, containsPair('lvl', 'warn'));
        expect(all.single, containsPair('sound', 'system'));
      },
    );

    test('a call it does not know records nothing', () async {
      final all = await rows(
        () => native('somethingElse', {'id': 1, 'sound': 'player'}),
      );
      expect(all, isEmpty);
    });
  });
}
