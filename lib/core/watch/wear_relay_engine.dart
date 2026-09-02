import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_connectivity/watch_connectivity.dart';

import '../auth/credentials_store.dart';
import '../diagnostics/diagnostic_recorder.dart';
import '../diagnostics/log_event.dart';
import '../diagnostics/session_facts.dart';
import '../notifications/background_api.dart';
import '../settings/settings_repository.dart';
import 'wear_relay_handler.dart';
import 'wear_rpc.dart';

/// Channel the native listener service hands forwarded requests over.
/// Mirrored in `WearRelayListenerService.kt`.
const wearRelayChannel = 'page.codeberg.morganmlgman.bambuddy/wear_relay';

/// Body of the headless engine's entry point, which lives in `main.dart` —
/// `wearRelayMain` there says why it cannot live here.
void serveWearRelay() {
  WidgetsFlutterBinding.ensureInitialized();
  final engine = WearRelayEngine();
  const MethodChannel(wearRelayChannel).setMethodCallHandler((call) async {
    if (call.method != 'handle') return null;
    final message = call.arguments;
    return message is Map ? engine.handle(message) : false;
  });
}

/// The phone's watch relay in a process that was dead a moment ago.
///
/// It deliberately does **not** listen on the Data Layer message stream the
/// other two responders use. The request that woke this process was already
/// consumed natively (no stream replays it), and every later one reaches the
/// service too — so being driven only by the service is what guarantees this
/// engine can never answer a request that a live listener is answering as
/// well. `WearRelayClaim` is the other half of that guarantee.
class WearRelayEngine {
  WearRelayEngine({
    WatchConnectivity? watch,
    Future<Dio?> Function()? openDio,
  })  : _watch = watch ?? WatchConnectivity(),
        _openDio = openDio ?? _dioFromPrefs;

  /// The same client the foreground service builds, minus Riverpod: profile
  /// from prefs, credentials from the keystore, JWT re-login wired in.
  static Future<Dio?> _dioFromPrefs() async =>
      (await buildBackgroundApiClient(await SharedPreferences.getInstance()))
          ?.dio;

  final WatchConnectivity _watch;
  final Future<Dio?> Function() _openDio;

  WearRelayHandler? _handler;
  Dio? _dio;
  bool _dioOpened = false;

  /// True until the first request is handled — that one, and only that one, is
  /// the request that woke this process.
  bool _cold = true;

  /// Answers one forwarded request; false means this build could not read it
  /// as one (a newer watch's action, or a foreign map), so the native side can
  /// tell a wake that did nothing from one that answered.
  ///
  /// Never throws: the caller is a platform channel on a service thread, and a
  /// Dart exception there is reported to the watch as nothing at all.
  Future<bool> handle(Map<Object?, Object?> message) async {
    final req = WearRpcRequest.decode(message);
    if (req == null) return false;
    final cold = _cold;
    _cold = false;
    final recording = await _openRecording();
    final started = DateTime.now();
    var outcome = 'answered';
    try {
      if (cold && !_mayRunOnWake(req)) {
        outcome = 'sender_cannot_wait';
        return false;
      }
      // Built once per wake and kept: the watch usually follows a command with
      // a fleet read, and a second keystore round trip would land inside the
      // window it is already waiting in. A null client is a valid outcome (no
      // server profile) — the handler answers `phone-unconfigured`, which the
      // watch reads as "do it yourself".
      if (!_dioOpened) {
        _dioOpened = true;
        _dio = await _openDio();
      }
      final handler = _handler ??=
          WearRelayHandler(watch: _watch, dio: () => _dio);
      await handler.handle(req);
      return true;
    } on Object {
      outcome = 'failed';
      return false;
    } finally {
      // Before the reply is answered, not after: once the service returns,
      // nothing keeps this process alive and a closed sink drops queued lines
      // without a word.
      _record(req, since: started, cold: cold, outcome: outcome);
      await recording?.stop();
    }
  }

  /// Whether a request may be *executed* on the wake it caused.
  ///
  /// A watch older than [wearRpcWakeAwareVersion] does not know the wake ack
  /// and has given up long before a cold boot can answer, so for it this wake
  /// exists to leave the engine warm for the retry — and the retry must not be
  /// the second run of something that does not repeat. Every later request
  /// reaches a warm engine, is answered in milliseconds, and is not gated.
  bool _mayRunOnWake(WearRpcRequest req) =>
      req.version >= wearRpcWakeAwareVersion || req.action.isRepeatSafe;

  /// Same rule as the notification-action engine (`docs/logging-guide.md` §4):
  /// only an engine where nothing else is logging opens a stream of its own,
  /// and a wake with no recording session on disk opens nothing at all.
  ///
  /// Cannot throw, by the same rule: this runs before the request does, and
  /// diagnostics failing must never be the reason the watch got no answer —
  /// `SettingsRepository.opened` alone is a platform read that can fail on a
  /// hostile OEM keystore.
  Future<BackgroundRecording?> _openRecording() async {
    try {
      if (DiagnosticRecorder.isRecording) return null;
      final settings = await SettingsRepository.opened();
      return await DiagnosticRecorder.startBackground(
        settings: settings,
        stream: LogStream.action,
        loadSecrets: () => sessionSecrets(
          profile: settings.loadProfile(),
          credentials: SecureCredentialsStore(),
        ),
        attachErrors: false,
      );
    } on Object {
      return null;
    }
  }

  void _record(
    WearRpcRequest req, {
    required DateTime since,
    required bool cold,
    required String outcome,
  }) {
    // The one line that separates "the watch never reached the phone" from
    // "the phone woke up and still could not answer" — the whole reason this
    // path is hard to report on.
    DiagnosticRecorder.active?.add(
      LogSource.app,
      'wear_wake',
      fields: {
        'action': req.action.name,
        'ms': DateTime.now().difference(since).inMilliseconds,
        // The engine boot is in here only when `cold` — the number is why a
        // watch that waited says the phone was slow, and the `outcome` is why
        // one that waited in vain got nothing.
        'cold': cold,
        'outcome': outcome,
        'sender_v': req.version,
      },
    );
  }
}
