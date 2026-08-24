// Fake bambuddy server for exercising the print-ended notification path on an
// emulator, with no printer and no real server involved.
//
// It answers just enough of the API for the app to attach to it (auth probe,
// printer roster, camera token), then lets you drive the two events that matter
// from the keyboard: the print ending, and the server attaching the finish photo
// minutes later. Both are the real wire frames, so what gets tested is the real
// path — WebSocket parsing, the alert, the camera-token download, the notification
// update and, on a paired watch, the bridge.
//
//   dart run tool/fake_bambuddy.dart [--port 8099] [--photo shot.jpg]
//
// Point the app at http://10.0.2.2:<port> (the emulator's route to the host),
// then type `help`. Not part of the app, not shipped: dev tooling.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const _archiveId = 82;
const _printerId = 1;
const _printName = 'Benchy';
late final String _photoExtension;

/// Deliberately old, and never touched by a run: a reprint reuses its archive
/// row the same way, so anything picking the print by row age picks wrong here
/// exactly as it would against a real server.
final _createdAt = DateTime.now().subtract(const Duration(days: 7));

/// When the print last ended — the field a run actually moves.
DateTime? _completedAt;

/// What the printer reports, and therefore what the app's monitor sees.
String _state = 'RUNNING';
int _progress = 40;

/// The faults the printer is reporting, in the server's `hms_errors` shape.
List<Map<String, Object?>> _hmsErrors = [];

/// Whether the printer is reachable. Auto Power Off switches the machine off
/// the moment a print ends, so "gate up, printer down" is the ordinary end
/// state on a farm — and the only one where the plate-clear banner has ever
/// been hard to reach.
bool _connected = true;

/// The plate-clear gate. Bambuddy-side state the server persists and reports
/// whether or not the printer is reachable (#2864).
bool _awaitingPlateClear = false;

/// Whether to answer like a server older than #2864: it built the status of a
/// printer with no MQTT client from the schema default, so the gate read as
/// down the moment the machine powered off. The app has to keep working against
/// both, and this is the only way to see the old behaviour without an old
/// server.
bool _legacyPlateGate = false;

/// Whether the printer answers an HMS action. The real route publishes, waits
/// 2.5 s for a push back and 502s if none comes; turning this off is how the
/// "printer did not confirm" message gets exercised without a printer that
/// ignores commands.
bool _hmsAcks = true;

/// The archive's photo list, in the server's own order. Attaching is separate
/// from sending the frame on purpose: the real server writes the ordinary
/// capture with nothing on the wire (`main.py` write phase) and only broadcasts
/// when it later replaces it with a frame off the timelapse — which it puts at
/// the FRONT, while ordinary captures and uploads go on the end.
List<String> _photos = [];

bool get _photoAttached => _photos.isNotEmpty;

final _sockets = <WebSocket>[];
late final List<int> _photoBytes;

Future<void> main(List<String> args) async {
  final port = int.tryParse(_arg(args, '--port') ?? '') ?? 8099;
  final photo = _arg(args, '--photo');
  _photoBytes = photo == null
      ? _generatePhoto(1600, 900)
      : File(photo).readAsBytesSync();
  _photoExtension = photo == null
      ? 'png'
      : photo.split('.').last.toLowerCase();

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln('fake bambuddy on http://localhost:$port');
  stdout.writeln('emulator: http://10.0.2.2:$port  (auth off)');
  stdout.writeln('photo: ${photo ?? 'generated'} (${_photoBytes.length} B)');
  stdout.writeln('type `help` for commands\n');

  unawaited(_serve(server));
  _prompt();
  await for (final line in stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())) {
    await _command(line.trim());
    _prompt();
  }
}

void _prompt() => stdout.write('> ');

Future<void> _command(String raw) async {
  // `+door` adds a fault to the ones already reported; `door` replaces them.
  // A printer stacks faults — a runout that also trips the door sensor — and
  // the card has to hold several at once.
  final add = raw.startsWith('+');
  final cmd = add ? raw.substring(1).trim() : raw;
  switch (cmd) {
    case 'help' || '':
      stdout.writeln('''
  print    printer starts printing (RUNNING) — the state to end from
  finish   print ends well  → app posts "print finished"
  fail     print ends badly → app posts "print failed"
  photo    attach the finish photo the way the server normally does: written to
           the archive, nothing on the wire. The app has to find it by polling,
           so allow up to a minute.
  upgrade  attach it AND broadcast archive_updated — the rarer path, where the
           server replaces the live grab with a frame off the timelapse
  go       finish, wait 15 s, then `photo` — the ordinary sequence end to end
  reset    forget the photo, so the next round starts clean
  status   what this server currently reports

  runout   filament ran out (0300_8004), paused, with the buttons Bambu offers
  door     chamber door open (0300_800F), paused — resume or stop
  heat     heatbed temperature malfunction (0300_8009), no action offered
  clog     nozzle clogged (0300_8016) — resume or stop
  many     three faults at once, two of them with buttons
  pile     five faults, the worst the card can be handed
  hms[]    an hms[]-channel fault (0300_0100_0001_000A) — the app is meant to
           stay silent about it, card and notification alike
  blank    a fault whose full_code the server left empty — named, no buttons
  served   a code outside the bundled catalogue, named by the server's own
           `description` — the English fallback, whatever the UI language
  ok       clear the faults, as `hms/clear` would
  ack      toggle whether the printer answers an action (off → the route 502s)

  plate    raise the plate-clear gate, as a finished print does
  off/on   printer loses / regains its connection (Auto Power Off, by hand)
  legacy   toggle answering like a pre-#2864 server, which reported the gate as
           down for a printer it had no MQTT client for

  Prefix any fault with `+` to add it to the ones already reported
  (`runout`, then `+door`), the way a printer stacks them.''');
    case 'print':
      // Clears the photo too: a round that starts with one already on the
      // archive is the false pass this server exists to avoid — the app would
      // attach it while the print is still running.
      _photos = [];
      _set('RUNNING', 40);
    case 'finish':
      _set('FINISH', 100);
    case 'fail':
      _set('FAILED', 61);
    case 'photo':
      _attachPhoto(broadcast: false);
    case 'upgrade':
      _attachPhoto(broadcast: true);
    case 'go':
      _set('FINISH', 100);
      stdout.writeln('  waiting 15 s, as the server does while it captures…');
      await Future<void>.delayed(const Duration(seconds: 15));
      _attachPhoto(broadcast: false);
    case 'reset':
      _photos = [];
      stdout.writeln('  archive has no photos again');
    case 'runout':
      // Exactly what the server builds from a 32-bit print_error: attr carries
      // the whole value, code its low half, full_code the 8-hex key the
      // firmware matches a command against.
      _fault(0x03008004, add: add, actions: [
        'RESUME_PRINTING',
        'IGNORE_RESUME',
        'STOP_PRINTING',
      ]);
    case 'door':
      _fault(0x0300800F,
          add: add, actions: ['RESUME_PRINTING', 'STOP_PRINTING']);
    case 'heat':
      _fault(0x03008009, add: add);
    case 'clog':
      _fault(0x03008016,
          add: add, actions: ['RESUME_PRINTING', 'STOP_PRINTING']);
    case 'many':
      // Three at once, the way a real pile-up reads: two that offer buttons and
      // one that offers none, longest description last.
      _fault(0x03008004, actions: [
        'RESUME_PRINTING',
        'IGNORE_RESUME',
        'STOP_PRINTING',
      ]);
      _fault(0x0300800F,
          add: true, actions: ['RESUME_PRINTING', 'STOP_PRINTING']);
      _fault(0x03008016,
          add: true, actions: ['RESUME_PRINTING', 'STOP_PRINTING']);
    case 'pile':
      // Everything the card can be asked to hold, including the two kinds it
      // must stay quiet about (hms[] and the blank full_code).
      _fault(0x03008004, actions: ['RESUME_PRINTING', 'STOP_PRINTING']);
      _fault(0x0300800F, add: true, actions: ['RESUME_PRINTING']);
      _fault(0x03008009, add: true);
      _fault(0x03008016, add: true, actions: ['RESUME_PRINTING']);
      _fault(0x0300801A, add: true, actions: [
        'RESUME_PRINTING',
        'IGNORE_RESUME',
        'STOP_PRINTING',
      ]);
    case 'hms[]':
      // The other channel: 64-bit attr+code, a component-diagnostics fault.
      // bambuddy's UI does not name these and neither does the app.
      _hmsErrors = [
        if (add) ..._hmsErrors,
        {
          'code': '0x1000a',
          'attr': 0x03000100,
          'module': 3,
          'severity': 2,
          'actions': const <String>[],
          'job_id': _jobId,
          'full_code': '030001000001000A',
        },
      ];
      // Added to the wire, deliberately absent from the card: `+hms[]` on top of
      // a runout is how the count gets checked against what is really shown.
      _pause('hms[] 0300_0100_0001_000A (${_hmsErrors.length} reported)');
    case 'blank':
      _fault(0x03008004, actions: ['RESUME_PRINTING'], fullCode: '');
    case 'served':
      // 0300_FFFF is in no catalogue, ours or the server's, so the only thing
      // that can name this card is the `description` on the wire.
      _fault(
        0x0300FFFF,
        add: add,
        actions: ['STOP_PRINTING'],
        description: 'The toolhead reported a fault this app has no text for.',
      );
    case 'ok':
      _clearFaults(from: 'console');
    case 'plate':
      _awaitingPlateClear = true;
      _broadcastStatus();
      stdout.writeln('  plate-clear gate up'
          '${_connected ? '' : ' (printer is off — nothing on the wire)'}');
    case 'off':
      _connected = false;
      _broadcastStatus();
      stdout.writeln('  printer → offline');
    case 'on':
      _connected = true;
      _broadcastStatus();
      stdout.writeln('  printer → online');
    case 'legacy':
      _legacyPlateGate = !_legacyPlateGate;
      stdout.writeln('  status route answers like a '
          '${_legacyPlateGate ? 'pre-#2864' : 'current'} server');
    case 'ack':
      _hmsAcks = !_hmsAcks;
      stdout.writeln('  printer ${_hmsAcks ? 'answers' : 'ignores'} HMS actions'
          '${_hmsAcks ? '' : ' → the route will 502'}');
    case 'status':
      stdout.writeln(
        '  $_state $_progress% · ${_connected ? 'online' : 'offline'}'
        ' · plate gate: ${_awaitingPlateClear ? 'up' : 'down'}'
        '${_legacyPlateGate ? ' (legacy)' : ''}'
        ' · photo: ${_photoAttached ? 'attached' : 'none'}'
        ' · faults: ${_hmsErrors.isEmpty ? 'none' : _hmsErrors.map((e) => e['full_code']).join(', ')}'
        ' · acks: $_hmsAcks · ${_sockets.length} client(s)',
      );
    default:
      stdout.writeln('  ? `help` lists the commands');
  }
}

/// The job the fault belongs to. The firmware echoes it back with an HMS
/// command, so the app has to carry it through untouched.
const _jobId = '746795586';

/// Report a `print_error`-channel fault and pause the print, which is what the
/// printer does for everything in this class. [add] keeps the faults already
/// reported, replacing only an earlier copy of this same code.
void _fault(
  int printError, {
  List<String> actions = const [],
  String? fullCode,
  String? description,
  bool add = false,
}) {
  final code = fullCode ??
      printError.toRadixString(16).padLeft(8, '0').toUpperCase();
  final fault = {
    'code': '0x${(printError & 0xFFFF).toRadixString(16)}',
    'attr': printError,
    'module': (printError >> 24) & 0xFF,
    'severity': 3,
    'actions': actions,
    'job_id': _jobId,
    // Defaults to the 8-hex key; `blank` passes '' to reproduce the server's
    // own empty default, which must not turn into a button.
    'full_code': code,
    // Absent unless a command asks for it: an older server sends no such field,
    // and that absence is what the rest of these faults are testing.
    'description': ?description,
  };
  _hmsErrors = [
    if (add)
      for (final existing in _hmsErrors)
        if (existing['full_code'] != code || code.isEmpty) existing,
    fault,
  ];
  final short = '${(printError >> 16).toRadixString(16).padLeft(4, '0')}_'
      '${(printError & 0xFFFF).toRadixString(16).padLeft(4, '0')}';
  _pause('${short.toUpperCase()} (${_hmsErrors.length} reported)');
}

void _pause(String what) {
  _state = 'PAUSE';
  _broadcastStatus();
  stdout.writeln('  printer → PAUSE, fault $what');
}

void _clearFaults({required String from}) {
  _hmsErrors = [];
  _broadcastStatus();
  stdout.writeln('  faults cleared ($from)');
}

void _set(String state, int progress) {
  _state = state;
  _progress = progress;
  if (state == 'FINISH' || state == 'FAILED') {
    _completedAt = DateTime.now();
    // Any terminal status may have left material on the bed, so the real server
    // raises the gate for all of them — `finish`, then `off`, is the sequence
    // Auto Power Off produces on its own.
    _awaitingPlateClear = true;
  }
  _broadcastStatus();
  stdout.writeln('  printer → $state $progress%');
}

/// Puts the photo on the archive; [broadcast] adds the `archive_updated` frame
/// the real server only sends from its photo-upgrade path
/// (`main.py::_upgrade_finish_photo_from_timelapse`).
void _attachPhoto({required bool broadcast}) {
  final name = _photoName(DateTime.now());
  // The upgrade goes to the front, the ordinary capture to the back, which is
  // what makes "newest photo" a question the app has to answer by name.
  broadcast ? _photos.insert(0, name) : _photos.add(name);
  stdout.writeln('  archive photos: ${_photos.join(', ')}');
  if (!broadcast) {
    stdout.writeln('  (no frame sent — the app has to poll for it)');
    return;
  }
  _broadcast({
    'type': 'archive_updated',
    'data': {'id': _archiveId, 'photo_added': name},
  });
  stdout.writeln('  archive_updated photo_added=$name');
}

/// The server's own naming, which is what orders the photos: `finish_` plus a
/// fixed-width local timestamp.
String _photoName(DateTime at) {
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp = '${at.year}${two(at.month)}${two(at.day)}_'
      '${two(at.hour)}${two(at.minute)}${two(at.second)}';
  return 'finish_${stamp}_${at.millisecond.toString().padLeft(3, '0')}a'
      '.$_photoExtension';
}

void _broadcastStatus() => _broadcast({
  'type': 'printer_status',
  'printer_id': _printerId,
  'data': _statusData(),
});

Map<String, Object?> _archive() => {
  'id': _archiveId,
  'printer_id': _printerId,
  'filename': '$_printName.gcode.3mf',
  'print_name': _printName,
  'status': 'completed',
  'completed_at': _completedAt?.toUtc().toIso8601String(),
  'created_at': _createdAt.toUtc().toIso8601String(),
  'photos': _photos,
};

Map<String, Object?> _statusData() => {
  'name': 'X1C (atrapa)',
  'model': 'X1C',
  // The real route builds the status of a printer it holds no client for from
  // the schema alone: `connected` false, `state` null, and (since #2864) the
  // gate as it really stands.
  'state': _connected ? _state : null,
  'connected': _connected,
  // A pre-#2864 server had no truthful value to report for a printer it held no
  // client for, and sent the schema default instead.
  'awaiting_plate_clear':
      _awaitingPlateClear && !(_legacyPlateGate && !_connected),
  'progress': _progress,
  'current_print': _printName,
  'layer_num': (_progress * 2.4).round(),
  'total_layers': 240,
  'remaining_time': math.max(0, 100 - _progress),
  'bed_temper': 60.0,
  'nozzle_temper': 220.0,
  'hms_errors': _hmsErrors,
};

void _broadcast(Map<String, Object?> frame) {
  final text = jsonEncode(frame);
  for (final socket in [..._sockets]) {
    try {
      socket.add(text);
    } on Object {
      _sockets.remove(socket);
    }
  }
}

Future<void> _serve(HttpServer server) async {
  await for (final request in server) {
    final path = request.uri.path;
    stdout.writeln('\n  ← ${request.method} $path');
    _prompt();

    if (path == '/api/v1/ws') {
      unawaited(_upgrade(request));
      continue;
    }
    if (path == '/api/v1/auth/status') {
      await _json(request, {'auth_enabled': false, 'requires_setup': false});
      continue;
    }
    if (path == '/api/v1/printers/') {
      await _json(request, [
        {'id': _printerId, 'name': 'X1C (atrapa)', 'model': 'X1C',
         'status': _statusData()},
      ]);
      continue;
    }
    if (path == '/api/v1/printers/$_printerId/status') {
      await _json(request, {'id': _printerId, ..._statusData()});
      continue;
    }
    // What gates the banner and the pre-start confirmation app-side; without it
    // the app treats the whole feature as switched off on the server.
    if (path == '/api/v1/settings') {
      await _json(request, {'require_plate_clear': true});
      continue;
    }
    if (path == '/api/v1/printers/$_printerId/clear-plate') {
      if (!_awaitingPlateClear) {
        // The real route's own refusal: it only takes the acknowledgement from a
        // printer that is waiting for one, whatever its connection state.
        stdout.writeln('  → 400: printer is not awaiting plate-clear');
        request.response.statusCode = HttpStatus.badRequest;
        await _json(request, const {
          'detail': 'Printer is not awaiting plate-clear acknowledgment '
              '(state=unknown)',
        });
        continue;
      }
      _awaitingPlateClear = false;
      stdout.writeln('  plate-clear gate down');
      // Only a printer with a live client gets a frame — `_broadcast_status_change`
      // returns early without one, which is why the app drops the gate locally.
      if (_connected) _broadcastStatus();
      await _json(request, const {
        'success': true,
        'message': 'Plate cleared, next print will start shortly',
      });
      continue;
    }
    if (path == '/api/v1/printers/$_printerId/hms/clear') {
      _clearFaults(from: 'hms/clear');
      await _json(request, {'success': true, 'message': 'HMS errors cleared'});
      continue;
    }
    if (path == '/api/v1/printers/$_printerId/hms/execute-action') {
      await _executeHmsAction(request);
      continue;
    }
    if (path == '/api/v1/printers/camera/stream-token') {
      await _json(request, {'token': 'fake-camera-token'});
      continue;
    }
    if (path == '/api/v1/archives/$_archiveId') {
      await _json(request, _archive());
      continue;
    }
    // What the app polls while an alert is live, newest first.
    if (path == '/api/v1/archives/') {
      await _json(request, [_archive()]);
      continue;
    }
    // Any name the archive actually lists, so the app has to have picked one
    // of them rather than guessed — the real route checks membership too.
    if (_photos.any((n) => path == '/api/v1/archives/$_archiveId/photos/$n')) {
      // Same gate as the real route: the camera token rides in `?token=`, and a
      // request without one is exactly how a stale token fails in production.
      if (request.uri.queryParameters['token'] == null) {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        continue;
      }
      request.response.headers.contentType = ContentType(
        'image',
        _photoExtension == 'png' ? 'png' : 'jpeg',
      );
      request.response.add(_photoBytes);
      await request.response.close();
      continue;
    }
    // Everything else: the app treats a 404 here as "server does not have this"
    // and carries on, which is what old servers look like to it anyway.
    request.response.statusCode = HttpStatus.notFound;
    await _json(request, const {});
  }
}

/// The action route, with the two things about it that matter to the app: it
/// validates `print_error` the way the real one does (8 or 16 hex, else 422),
/// and it answers 502 when the printer stays silent — the case the card and the
/// notification each have their own wording for.
Future<void> _executeHmsAction(HttpRequest request) async {
  final body = await utf8.decoder.bind(request).join();
  final json = jsonDecode(body) as Map<String, dynamic>;
  final printError = '${json['print_error']}';
  final action = '${json['action']}';
  stdout.writeln('    body: print_error=$printError action=$action '
      'job_id=${json['job_id'] ?? '(none)'}');
  _prompt();

  if (!RegExp(r'^[0-9A-Fa-f]{8}([0-9A-Fa-f]{8})?$').hasMatch(printError)) {
    stdout.writeln('  → 422: print_error is not 8 or 16 hex digits');
    request.response.statusCode = HttpStatus.unprocessableEntity;
    await _json(request, {
      'detail': [
        {'msg': 'String should match pattern', 'loc': ['body', 'print_error']},
      ],
    });
    return;
  }
  if (!_hmsAcks) {
    // The real route publishes, sleeps 2.5 s and gives up. Sleeping here too
    // keeps the app's spinner honest about how long that feels.
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    stdout.writeln('  → 502: printer did not acknowledge');
    request.response.statusCode = HttpStatus.badGateway;
    await _json(request, {'detail': 'Printer did not acknowledge HMS action'});
    return;
  }

  switch (action) {
    case 'STOP_PRINTING':
      _hmsErrors = [];
      _set('FAILED', _progress);
    case 'RESUME_PRINTING' || 'IGNORE_RESUME' || 'PROBLEM_SOLVED_RESUME':
      _hmsErrors = [];
      _set('RUNNING', _progress);
    default:
      // Everything else clears the dialog without moving the print, which is
      // what the ams_control / idle_ignore commands do.
      _clearFaults(from: action);
  }
  await _json(request, {'success': true, 'message': 'HMS action executed'});
}

Future<void> _upgrade(HttpRequest request) async {
  final socket = await WebSocketTransformer.upgrade(request);
  _sockets.add(socket);
  socket.add(jsonEncode({
    'type': 'printer_status',
    'printer_id': _printerId,
    'data': _statusData(),
  }));
  // The client's watchdog drops a socket that says nothing, and its heartbeat
  // expects an answer.
  final ticker = Timer.periodic(const Duration(seconds: 3), (_) {
    if (!_sockets.contains(socket)) return;
    socket.add(jsonEncode({
      'type': 'printer_status',
      'printer_id': _printerId,
      'data': _statusData(),
    }));
  });
  socket.listen(
    (data) {
      if (data is String && data.contains('"ping"')) {
        socket.add(jsonEncode(const {'type': 'pong'}));
      }
    },
    onDone: () {
      ticker.cancel();
      _sockets.remove(socket);
    },
    onError: (_) {
      ticker.cancel();
      _sockets.remove(socket);
    },
  );
}

Future<void> _json(HttpRequest request, Object? body) async {
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}

String? _arg(List<String> args, String name) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

/// A stand-in "photo" at print-camera size, so the notification is judged at the
/// resolution the real one arrives at. PNG because `dart:io` already has the
/// deflate half of it; the notification only ever sees decoded pixels.
List<int> _generatePhoto(int width, int height) {
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0); // per-scanline filter: none
    for (var x = 0; x < width; x++) {
      final plate = y > height * 0.72;
      raw
        ..addByte(plate ? 60 : 30 + (x * 120 ~/ width))
        ..addByte(plate ? 62 : 40 + (y * 90 ~/ height))
        ..addByte(plate ? 66 : 70 + ((x + y) * 60 ~/ (width + height)));
    }
  }
  final ihdr = BytesBuilder()
    ..add(_be32(width))
    ..add(_be32(height))
    ..add([8, 2, 0, 0, 0]);
  return [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    ..._chunk('IHDR', ihdr.takeBytes()),
    ..._chunk('IDAT', ZLibCodec().encode(raw.takeBytes())),
    ..._chunk('IEND', const []),
  ];
}

List<int> _chunk(String type, List<int> data) {
  final body = [...utf8.encode(type), ...data];
  return [..._be32(data.length), ...body, ..._be32(_crc32(body))];
}

List<int> _be32(int v) => [v >> 24 & 0xFF, v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF];

final _crcTable = List<int>.generate(256, (i) {
  var c = i;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final byte in data) {
    c = _crcTable[(c ^ byte) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
