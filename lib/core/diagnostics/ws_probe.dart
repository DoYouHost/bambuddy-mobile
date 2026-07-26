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
/// and how many frames of what type arrived while they lasted.
///
/// This is the source that explains "the dashboard says Reconnecting and never
/// stops". A handshake rejected with 401, a token mint that failed, a server
/// that accepts the socket and then sends nothing, and a Wi-Fi roam that leaves
/// a half-open TCP all look identical from the UI — and only the last one is the
/// app's own fault.
///
/// Like `HttpProbe`, it writes through `DiagnosticRecorder.active` rather than
/// holding a store: a [WsProbe] lives as long as its `WsClient`, which is longer
/// than any recording, and recordings routinely start mid-connection.
///
/// ## Every frame is a record
///
/// ```json
/// {"src":"ws","evt":"frame","type":"printer_status","printer_id":1,"state":"RUNNING","stage":"Heating","progress":12,"layer":3,"nozzle":218,"bed":60}
/// {"src":"ws","evt":"repeated","type":"printer_status","n":4}
/// ```
///
/// Sometimes the whole point of a report is *what* arrived — a status frame that
/// says the printer is idle while the card shows a print, or an HMS error that
/// appeared and vanished. So the fields go in one record per frame; measured on a
/// live print that is a frame every two seconds, roughly a hundred and fifty
/// records and fifteen kilobytes over the five-minute ceiling, well inside both
/// caps.
///
/// What deliberately never enters a record is the payload: `data` carries the
/// model and file name of what is printing, spool names and printer serials —
/// the same user content the label rule keeps out of the log. Only scalars the
/// server owns go in, and the ones that explain reports: the printer's state and
/// stage, progress, layer, temperatures, whether it dropped off, and how many
/// HMS errors are standing.
///
/// ## Repeats
///
/// The server pushes on any change to its own status key, which covers fans, AMS
/// trays and the chamber light — fields a record would be a status dump to carry.
/// A frame that changes nothing we log is therefore normal, and a server stuck in
/// a push loop would otherwise sweep the buffer clean of everything that explains
/// the bug. So consecutive identical frames collapse into a count, the same way
/// `ErrorProbe` handles a widget that throws on every frame.
class WsProbe {
  WsProbe({DateTime Function()? clock}) : _now = clock ?? DateTime.now {
    _live.add(this);
  }

  /// How long a run of identical frames may last before its count is written
  /// out, so a push loop still shows up on the timeline where it happened
  /// instead of as one number at the end. Checked when a frame arrives — a loop
  /// by definition keeps arriving, so this needs no timer of its own.
  static const repeatWindow = Duration(seconds: 5);

  /// Frame type names are the server's strings, so they are held to the shape it
  /// actually uses; anything else is logged as `other` rather than trusted into
  /// the log.
  static final _typeShape = RegExp(r'^[a-z][a-z0-9_]{2,31}$');

  static final Set<WsProbe> _live = {};

  /// Writes out every live probe's pending repeat count. Called when a recording
  /// stops, so a run still going at that moment is counted inside the session.
  static void flushAll() {
    for (final probe in _live.toList()) {
      probe.flushRepeats();
    }
  }

  /// Opens a session with where each connection stands, the same way the
  /// recorder opens it with the screen it is showing.
  ///
  /// A recording almost always starts on an app whose socket has been up for a
  /// while, so `connect` and `open` are already history: the first live run
  /// produced exactly one WebSocket record in forty seconds, and nothing before
  /// it said whether the live view was even connected.
  static void openSession() {
    for (final probe in _live.toList()) {
      probe._reportState();
    }
  }

  final DateTime Function() _now;

  /// The client's state as it last reported it (a `WsConnectionState` name, kept
  /// as a string so this file doesn't have to import the client that owns it).
  /// Tracked without writing anything: transitions already have their own
  /// records, and this only exists so a session can open with where things
  /// stand.
  String _state = 'disconnected';

  /// When the current attempt started dialling, for the handshake duration.
  /// Stamped whether or not a recording runs — starting one mid-handshake is
  /// normal, and an `open` without `ms` would be the result.
  DateTime? _connectStartedAt;

  DateTime? _openedAt;

  /// What the pending repeats are repeats *of*, and how many. [_counting] is the
  /// store they belong to: a run that started before the recording must not be
  /// written into it as if it had happened inside.
  String? _repeatKey;
  String? _repeatType;
  int _repeats = 0;
  LogStore? _counting;

  /// When the run's count was last written out, on the probe's own clock — the
  /// window is wall time, and taking it from here rather than from the store
  /// keeps it under a test's control.
  DateTime? _lastFlushAt;

  /// When the last counted repeat arrived. The count is written out later, and
  /// stamping it with *that* moment would put a run that ended in the fourteenth
  /// second at the end of the session instead.
  int _lastRepeatMs = 0;

  /// What the client's connection state is now. Silent by design — see [_state].
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

  /// The attempt failed. [error] is the exception with the transport's wrapper
  /// already unwrapped, so `cause` names what actually broke —
  /// `HandshakeException` versus `SocketException` separates "TLS refused" from
  /// "nothing listening there". [status] is the HTTP status of a rejected
  /// upgrade, which is the whole story when it is 401.
  ///
  /// [phase] `token` means the mint failed and no socket was ever attempted;
  /// the mint itself is an HTTP call, so `HttpProbe` has the details.
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

  /// The next attempt is due. Separate from the record that reports the failure
  /// because the delay is decided afterwards, and "how long until it tries
  /// again" is what the user is waiting through.
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
        // How long the connection lasted. A socket that keeps reopening every
        // few seconds is a different report than one that dropped once.
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
        // How long the socket has been up, which is the part the records that
        // opened it would have said and can't: they predate the recording.
        'up_ms': openedAt == null ? null : _msSince(openedAt, _now()),
      },
    );
  }

  /// What the frame said.
  ///
  /// The rule is not "which fields are worth it" — that question produced a
  /// first version that logged a third of the frame and left the rest to be
  /// guessed. The rule is **whose the value is**: everything the printer or the
  /// server owns goes in, and nothing the user wrote does. So the file and model
  /// being printed, the printer's name, the cover URL and the commercial spool
  /// names stay out, exactly as the label rule requires; states, stages,
  /// temperatures, fan speeds and slot numbers go in.
  ///
  /// The set deliberately covers the server's own `status_key` — the tuple it
  /// deduplicates broadcasts on. That is what makes a `repeated` record mean
  /// "the server pushed a frame identical in everything it dedups on", rather
  /// than "the frame changed something we chose not to look at".
  static Map<String, Object?> _detailsOf(WsMessage? msg) => switch (msg) {
        WsPrinterStatus(status: final s) => {
          'printer_id': s.id,
          // Only when it is false: "the printer went offline mid-print" is a
          // report, "it is still there" on every record is padding.
          'connected': s.connected == false ? false : null,
          'state': s.state,
          // English from the server ("Heating", "Auto bed leveling") — the four
          // words that explain why a print looks stuck.
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

  /// The AMS modules: what is loaded, how wet it is, whether it is drying.
  ///
  /// A slot's material goes through the closed list ([FilamentMaterial]), which
  /// is what keeps the commercial name out — `tray_type` is free text on some
  /// server versions, and the brand next to it ("Professional Lab PETG Basic")
  /// is the user's data. The colour and the sub-brand are not logged at all.
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

  /// The errors the printer is standing on: how many, and which.
  ///
  /// The codes are hex identifiers from Bambu's firmware with a catalog in
  /// `assets/hms` — the printer's own vocabulary, never user text — and in a
  /// status frame they are the only field that says what is actually wrong. The
  /// count stays because the list is capped: a printer in a bad mood must not be
  /// able to fill the line.
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
  /// Whatever arrives rather than a list of three: the first version picked
  /// `nozzle`/`bed`/`chamber` and so logged neither the targets — a bed target of
  /// zero mid-print explains a whole report on its own — nor `nozzle_2`, which
  /// is half of what a dual-head X2D/H2D is doing. The model's parser has
  /// already dropped the `*_heating` booleans and the `*_time` metadata, so what
  /// is left is numbers from the machine.
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

  /// The frame type as it goes into the log. Known types are named by the
  /// parser's own vocabulary; an unknown one is the server's string, which is
  /// how a newly added frame type gets noticed at all.
  static String _typeName(WsMessage? msg) => switch (msg) {
        WsPrinterStatus() => 'printer_status',
        WsPlateNotEmpty() => 'plate_not_empty',
        WsPrintEvent(completed: final completed) =>
          completed ? 'print_complete' : 'print_start',
        WsPong() => 'pong',
        WsUnknown(type: final type) => _knownShape(type),
        null => 'unparsed',
      };

  /// An unknown type is the server's own string, so it is held to the shape the
  /// server actually uses: anything else is not a frame type, and a sentence
  /// from a confused endpoint has no business being logged verbatim.
  static String _knownShape(String? type) {
    if (type == null || type.isEmpty) return 'untyped';
    return _typeShape.hasMatch(type) ? type : 'other';
  }

  /// `toString()` without what the record already says: the class name is the
  /// `cause` and, on a rejected upgrade, `dart:io` spells the status out in the
  /// message too. Same reasoning as in `HttpProbe` and `ErrorProbe`.
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
    // A clock moved backwards mid-connection must not produce a duration that
    // reads as an event arriving before what caused it.
    return ms < 0 ? 0 : ms;
  }
}
