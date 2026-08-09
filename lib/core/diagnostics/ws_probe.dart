import '../api/ws_messages.dart';
import '../models/printer_status.dart' show AmsTray, AmsUnit, HmsError;
import 'diagnostic_recorder.dart';
import 'filament_material.dart';
import 'log_event.dart';
import 'log_store.dart';

/// Why the socket went away. The names are wire values — the summarising Action
/// groups by them, so renaming one breaks logs already attached to an issue.
enum WsDisconnectReason {
  /// The server hung up (stream done). `code` says how politely.
  remote,

  /// The stream failed rather than ended — connectivity lost mid-connection.
  error,

  /// No frame of any kind for the idle timeout: the client gave up on a socket
  /// that looks open but isn't (the classic half-open TCP after a Wi-Fi roam).
  idle,

  /// The app went to the background and closed the socket on purpose.
  suspend,

  /// The client itself was thrown away — profile change or app teardown.
  dispose,
}

/// Records what the live view is doing: connection attempts, how they ended,
/// and what frames arrived while they lasted.
///
/// This is what explains "the dashboard says Reconnecting and never stops": a
/// 401 handshake, a failed token mint, a server that accepts the socket and
/// sends nothing, and a Wi-Fi roam leaving a half-open TCP all look identical
/// from the UI, and only the last is the app's own fault.
///
/// Writes through `DiagnosticRecorder.active` rather than holding a store: a
/// [WsProbe] outlives any recording, and recordings routinely start
/// mid-connection.
///
/// Which frame fields go in and why repeats collapse:
/// `docs/diagnostics-log.md`.
class WsProbe {
  WsProbe({DateTime Function()? clock}) : _now = clock ?? DateTime.now {
    _live.add(this);
  }

  static const repeatWindow = Duration(seconds: 5);

  static final _typeShape = RegExp(r'^[a-z][a-z0-9_]{2,31}$');

  static final Set<WsProbe> _live = {};

  /// Writes out every live probe's pending repeat count, so a run still going
  /// when a recording stops is counted inside the session.
  static void flushAll() {
    for (final probe in _live.toList()) {
      probe.flushRepeats();
    }
  }

  /// Opens a session with where each connection stands. A recording almost
  /// always starts on an app whose socket has been up a while, so `connect` and
  /// `open` are already history: the first live run produced exactly one
  /// WebSocket record in forty seconds, none of it saying whether the live view
  /// was even connected.
  static void openSession() {
    for (final probe in _live.toList()) {
      probe._reportState();
    }
  }

  final DateTime Function() _now;

  /// A `WsConnectionState` name, kept as a string so this file need not import
  /// the client that owns it. Tracked without writing anything: transitions
  /// have their own records, and this only exists so a session can open with
  /// where things stand.
  String _state = 'disconnected';

  /// Stamped whether or not a recording runs — starting one mid-handshake is
  /// normal, and an `open` without `ms` would be the result.
  DateTime? _connectStartedAt;

  DateTime? _openedAt;

  /// What the pending repeats are repeats *of*, and how many. [_counting] is
  /// the store they belong to: a run that started before the recording must not
  /// be written into it as if it had happened inside.
  String? _repeatKey;
  String? _repeatType;
  int _repeats = 0;
  LogStore? _counting;

  /// The window is wall time, and taking it from the probe's own clock rather
  /// than from the store keeps it under a test's control.
  DateTime? _lastFlushAt;

  /// Stamping the count with the moment it gets written would put a run that
  /// ended in the fourteenth second at the end of the session instead.
  int _lastRepeatMs = 0;

  /// Silent by design — see [_state].
  void trackState(String state) => _state = state;

  /// About to dial. [queryToken] tells apart the current servers, which require
  /// a minted `?token=`, from the older header-only ones — a handshake rejected
  /// on one is a different report than on the other.
  void connecting({required bool queryToken}) {
    _connectStartedAt = _now();
    DiagnosticRecorder.active?.add(
      LogSource.ws,
      'connect',
      fields: {'via': queryToken ? 'token' : 'header'},
    );
  }

  void opened() {
    final now = _now();
    _openedAt = now;
    DiagnosticRecorder.active?.add(
      LogSource.ws,
      'open',
      fields: {'ms': _msSince(_connectStartedAt, now)},
    );
    _connectStartedAt = null;
  }

  /// The attempt failed. [error] arrives with the transport's wrapper already
  /// unwrapped, so `cause` names what actually broke. [status] is the HTTP
  /// status of a rejected upgrade, which is the whole story when it is 401.
  /// [phase] `token` means the mint failed and no socket was ever attempted —
  /// the mint is an HTTP call, so `HttpProbe` has the details.
  void connectError(
    Object error, {
    required String phase,
    int? status,
  }) {
    final cause = error.runtimeType.toString();
    DiagnosticRecorder.active?.add(
      LogSource.ws,
      'connect_error',
      lvl: LogLevel.error,
      fields: {
        'phase': phase,
        'cause': cause,
        'status': status,
        'ms': _msSince(_connectStartedAt, _now()),
        'msg': _messageOf(error, cause, status: status),
      },
    );
    _connectStartedAt = null;
  }

  /// One frame arrived. [msg] is what the parser made of it; `null` is text that
  /// wasn't JSON at all.
  void frame(WsMessage? msg) => _frame(_typeName(msg), _detailsOf(msg));

  /// A binary frame. bambuddy only sends text, so this is worth telling apart
  /// from a frame that failed to parse.
  void binaryFrame() => _frame('binary', const {});

  void _frame(String type, Map<String, Object?> details) {
    final store = DiagnosticRecorder.active;
    if (store == null) {
      // Drop a run that was in progress instead of writing it into the next
      // recording, which never saw it.
      _repeats = 0;
      _repeatKey = null;
      _counting = null;
      return;
    }
    if (store != _counting) {
      _repeats = 0;
      _repeatKey = null;
      _counting = store;
    }

    final fields = {'type': type, ...details};
    final key = fields.toString();
    if (key == _repeatKey) {
      _repeats++;
      _lastRepeatMs = store.elapsedMs;
      if (_msSince(_lastFlushAt, _now())! >= repeatWindow.inMilliseconds) {
        flushRepeats();
      }
      return;
    }

    // A different frame ends the previous run, so its count lands before the
    // record that interrupted it.
    flushRepeats();
    _repeatKey = key;
    _repeatType = type;
    _lastFlushAt = _now();
    store.add(LogSource.ws, 'frame', fields: fields);
  }

  /// Writes out the pending repeat count, if any.
  void flushRepeats() {
    if (_repeats == 0) return;
    _counting?.add(
      LogSource.ws,
      'repeated',
      fields: {'type': _repeatType, 'n': _repeats},
      at: _lastRepeatMs,
    );
    _repeats = 0;
    _lastFlushAt = _now();
  }

  /// The next attempt is due. Separate from the failure record because the
  /// delay is decided afterwards, and it is what the user waits through.
  void retryScheduled({required Duration delay, required int attempt}) {
    DiagnosticRecorder.active?.add(
      LogSource.ws,
      'retry',
      fields: {'in_ms': delay.inMilliseconds, 'attempt': attempt},
    );
  }

  /// The connection is over. [code] and [closeReason] are what the peer sent,
  /// when the transport reports them; [error] is what broke the stream.
  void disconnected({
    required WsDisconnectReason reason,
    int? code,
    String? closeReason,
    Object? error,
  }) {
    final openedAt = _openedAt;
    _openedAt = null;
    // Before the record, so a run of frames is counted inside the connection
    // that produced it rather than after its end.
    flushRepeats();
    DiagnosticRecorder.active?.add(
      LogSource.ws,
      'disconnect',
      lvl: _closeLevel(reason),
      fields: {
        'reason': reason.name,
        'code': code,
        'close_reason': closeReason,
        'cause': error?.runtimeType.toString(),
        // A socket reopening every few seconds is a different report than one
        // that dropped once.
        'up_ms': openedAt == null ? null : _msSince(openedAt, _now()),
      },
    );
  }

  void dispose() {
    flushRepeats();
    _live.remove(this);
  }

  void _reportState() {
    final openedAt = _openedAt;
    DiagnosticRecorder.active?.add(
      LogSource.ws,
      'state',
      fields: {
        'state': _state,
        // What the `connect` and `open` records would have said had they not
        // predated the recording.
        'up_ms': openedAt == null ? null : _msSince(openedAt, _now()),
      },
    );
  }

  /// Everything the printer or server owns, nothing the user wrote — and wide
  /// enough to cover the server's own `status_key`, so a `repeated` record
  /// means what it says.
  static Map<String, Object?> _detailsOf(WsMessage? msg) => switch (msg) {
        WsPrinterStatus(status: final s) => {
          'printer_id': s.id,
          // Only when it is false: "the printer went offline mid-print" is a
          // report, "it is still there" on every record is padding.
          'connected': s.connected == false ? false : null,
          'state': s.state,
          // English from the server ("Heating", "Auto bed leveling").
          'stage': s.stgCurName,
          'progress': s.progress?.round(),
          'layer': s.layerNum,
          'layers': s.totalLayers,
          'eta_min': s.remainingTime,
          ..._temperatures(s.temperatures),
          'cooling_fan': s.coolingFanSpeed,
          'big_fan1': s.bigFan1Speed,
          'big_fan2': s.bigFan2Speed,
          'heatbreak_fan': s.heatbreakFanSpeed,
          'speed': s.speedLevel,
          'light': s.chamberLight,
          'airduct': s.airductMode,
          'door_open': s.doorOpen == true ? true : null,
          'plate_wait': s.awaitingPlateClear == true ? true : null,
          'extruder': s.activeExtruder,
          'tray_now': s.trayNow,
          ..._hms(s.hmsErrors),
          ..._ams(s.ams),
          ..._external(s.vtTray),
        },
        // Whose plate, not what the server said about it: the message is a
        // localized sentence that can carry the printer's name.
        WsPlateNotEmpty(printerId: final id) => {'printer_id': id},
        WsPrintEvent(printerId: final id) => {'printer_id': id},
        _ => const {},
      };

  /// `tray_type` is free text on some server versions, so a slot's material
  /// goes through [FilamentMaterial]'s closed list; colour and sub-brand are
  /// not logged at all.
  static Map<String, Object?> _ams(List<AmsUnit>? units) {
    if (units == null || units.isEmpty) return const {};
    return {
      'ams': [
        for (final unit in units)
          _pruned({
            'id': unit.id,
            'rh': unit.humidity,
            'temp': unit.temp?.round(),
            // Only while something is happening: 0 is "off" and would be on
            // every record of every session.
            'dry': _positive(unit.dryStatus),
            'dry_min': _positive(unit.dryTime),
            'trays': _trays(unit.trays),
          }),
      ],
    };
  }

  /// The external spool holders, same rule as the AMS slots.
  static Map<String, Object?> _external(List<AmsTray>? trays) {
    if (trays == null || trays.isEmpty) return const {};
    return {'vt': _trays(trays)};
  }

  static List<Map<String, Object?>> _trays(List<AmsTray>? trays) => [
        for (final tray in trays ?? const <AmsTray>[])
          _pruned({
            'id': tray.id,
            'mat': FilamentMaterial.canonical(tray.trayType),
            // -1 means "no RFID tag", i.e. nobody knows.
            'remain': (tray.remain ?? -1) < 0 ? null : tray.remain,
          }),
      ];

  static int? _positive(int? value) => (value ?? 0) > 0 ? value : null;

  /// [LogEvent] drops null fields, but only at the top level — a nested map has
  /// to clean up after itself or every AMS entry carries its own `null`s.
  static Map<String, Object?> _pruned(Map<String, Object?> fields) {
    fields.removeWhere((_, value) => value == null);
    return fields;
  }

  /// The errors the printer is standing on: how many, and which. The codes are
  /// hex identifiers from Bambu's firmware — the printer's own vocabulary,
  /// never user text. The count stays because the list is capped: a printer in
  /// a bad mood must not be able to fill the line.
  static Map<String, Object?> _hms(List<HmsError>? errors) {
    if (errors == null || errors.isEmpty) return const {};
    final codes = [
      for (final error in errors.take(3))
        if (error.code case final String code) code,
    ];
    return {
      'hms': errors.length,
      if (codes.isNotEmpty) 'hms_codes': codes,
    };
  }

  /// Every temperature the server sent, under its own name and rounded.
  ///
  /// Whatever arrives rather than a fixed list: the first version picked
  /// `nozzle`/`bed`/`chamber` and so logged neither the targets — a bed target
  /// of zero mid-print explains a whole report on its own — nor `nozzle_2`,
  /// half of what a dual-head X2D/H2D is doing. The model's parser has already
  /// dropped the `*_heating` and `*_time` fields.
  static Map<String, Object?> _temperatures(Map<String, double>? temps) {
    if (temps == null || temps.isEmpty) return const {};
    return {
      for (final entry in temps.entries) entry.key: entry.value.round(),
    };
  }

  static LogLevel _closeLevel(WsDisconnectReason reason) => switch (reason) {
        // The app's own doing, and it says so; nothing to explain.
        WsDisconnectReason.suspend ||
        WsDisconnectReason.dispose =>
          LogLevel.info,
        _ => LogLevel.warn,
      };

  /// Known types are named by the parser's own vocabulary; an unknown one is
  /// the server's string, which is how a new frame type gets noticed at all.
  static String _typeName(WsMessage? msg) => switch (msg) {
        WsPrinterStatus() => 'printer_status',
        WsPlateNotEmpty() => 'plate_not_empty',
        WsPrintEvent(completed: final completed) =>
          completed ? 'print_complete' : 'print_start',
        WsPong() => 'pong',
        WsUnknown(type: final type) => _knownShape(type),
        null => 'unparsed',
      };

  /// Held to [_typeShape] because a sentence from a confused endpoint is not a
  /// frame type and has no business being logged verbatim.
  static String _knownShape(String? type) {
    if (type == null || type.isEmpty) return 'untyped';
    return _typeShape.hasMatch(type) ? type : 'other';
  }

  /// `toString()` without what the record already says: the class name is the
  /// `cause`, and on a rejected upgrade `dart:io` spells the status out too.
  static String? _messageOf(Object error, String cause, {int? status}) {
    var text = error.toString().trim();
    if (text.startsWith('$cause: ')) text = text.substring(cause.length + 2);
    if (status != null) text = text.replaceFirst(_httpStatusTail, '');
    return text.isEmpty ? null : text;
  }

  /// What `WebSocketException.toString()` appends when it carries a status.
  static final _httpStatusTail = RegExp(r',?\s*HTTP status code:\s*\d+\.?$');

  int? _msSince(DateTime? from, DateTime now) {
    if (from == null) return null;
    final ms = now.difference(from).inMilliseconds;
    // A clock moved backwards must not produce an event arriving before what
    // caused it.
    return ms < 0 ? 0 : ms;
  }
}
