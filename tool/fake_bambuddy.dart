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
/// Named the way the server names a finish shot, with the extension of whatever
/// is actually being served — the app picks the archive's photo by this name.
late final String _photoName;

/// What the printer reports, and therefore what the app's monitor sees.
String _state = 'RUNNING';
int _progress = 40;

/// Whether the archive already carries the finish photo. Separate from sending
/// the frame on purpose: the real server attaches the ordinary capture with
/// nothing on the wire (`main.py` write phase) and only broadcasts when it later
/// replaces it with a frame off the timelapse.
bool _photoAttached = false;

final _sockets = <WebSocket>[];
late final List<int> _photoBytes;

Future<void> main(List<String> args) async {
  final port = int.tryParse(_arg(args, '--port') ?? '') ?? 8099;
  final photo = _arg(args, '--photo');
  _photoBytes = photo == null
      ? _generatePhoto(1600, 900)
      : File(photo).readAsBytesSync();
  final extension = photo == null ? 'png' : photo.split('.').last.toLowerCase();
  _photoName = 'finish_20260815_120000_ab12cd34.$extension';

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

Future<void> _command(String cmd) async {
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
  status   what this server currently reports''');
    case 'print':
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
      _photoAttached = false;
      stdout.writeln('  archive has no photo again');
    case 'status':
      stdout.writeln(
        '  $_state $_progress% · photo: ${_photoAttached ? 'attached' : 'none'}'
        ' · ${_sockets.length} client(s)',
      );
    default:
      stdout.writeln('  ? `help` lists the commands');
  }
}

void _set(String state, int progress) {
  _state = state;
  _progress = progress;
  _broadcastStatus();
  stdout.writeln('  printer → $state $progress%');
}

/// Puts the photo on the archive; [broadcast] adds the `archive_updated` frame
/// the real server only sends from its photo-upgrade path
/// (`main.py::_upgrade_finish_photo_from_timelapse`).
void _attachPhoto({required bool broadcast}) {
  _photoAttached = true;
  stdout.writeln('  archive now has $_photoName');
  if (!broadcast) {
    stdout.writeln('  (no frame sent — the app has to poll for it)');
    return;
  }
  _broadcast({
    'type': 'archive_updated',
    'data': {'id': _archiveId, 'photo_added': _photoName},
  });
  stdout.writeln('  archive_updated photo_added=$_photoName');
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
  'photos': _photoAttached ? [_photoName] : <String>[],
};

Map<String, Object?> _statusData() => {
  'name': 'X1C (atrapa)',
  'model': 'X1C',
  'state': _state,
  'connected': true,
  'progress': _progress,
  'current_print': _printName,
  'layer_num': (_progress * 2.4).round(),
  'total_layers': 240,
  'remaining_time': math.max(0, 100 - _progress),
  'bed_temper': 60.0,
  'nozzle_temper': 220.0,
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
    if (path == '/api/v1/archives/$_archiveId/photos/$_photoName') {
      // Same gate as the real route: the camera token rides in `?token=`, and a
      // request without one is exactly how a stale token fails in production.
      if (request.uri.queryParameters['token'] == null) {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        continue;
      }
      request.response.headers.contentType = ContentType(
        'image',
        _photoName.endsWith('.png') ? 'png' : 'jpeg',
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
