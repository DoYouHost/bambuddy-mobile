import 'dart:typed_data';

/// JPEG marker bytes: a frame runs from SOI (`FF D8`) to EOI (`FF D9`).
const _marker = 0xFF;
const _soi = 0xD8;
const _eoi = 0xD9;

/// Ceiling for a frame that has started but not ended. The server decides how
/// much it sends before an EOI, so without a cap a route that answers with
/// something that is not MJPEG — or a truncated response — grows the buffer
/// until the app dies. Dropping the buffer resynchronises on the next SOI.
const defaultMaxFrameBytes = 8 * 1024 * 1024;

/// Cuts an MJPEG byte stream into whole JPEG frames.
///
/// The multipart headers between frames (`--frame`, `Content-Type: …`) are not
/// parsed: everything outside an SOI…EOI pair is dropped, which is what makes
/// this work the same for a server that sends them and one that does not.
/// Markers split across two chunks are handled — the scan starts one byte
/// before the end of what was already searched.
Stream<Uint8List> mjpegFrames(
  Stream<List<int>> chunks, {
  int maxFrameBytes = defaultMaxFrameBytes,
}) async* {
  var buffer = Uint8List(0);
  var frameStart = -1; // Index of the SOI being collected, -1 between frames.
  var scanned = 0;

  await for (final chunk in chunks) {
    buffer = _concat(buffer, chunk);

    var i = scanned == 0 ? 0 : scanned - 1;
    while (i + 1 < buffer.length) {
      if (buffer[i] != _marker) {
        i++;
        continue;
      }
      final next = buffer[i + 1];
      if (frameStart < 0 && next == _soi) {
        frameStart = i;
        i += 2;
      } else if (frameStart >= 0 && next == _eoi) {
        yield Uint8List.sublistView(buffer, frameStart, i + 2);
        buffer = Uint8List.fromList(buffer.sublist(i + 2));
        frameStart = -1;
        i = 0;
      } else {
        i++;
      }
    }

    if (frameStart < 0) {
      // Nothing before the next SOI can belong to a frame. The last byte stays:
      // it may be the `FF` of a marker whose `D8` is in the next chunk.
      buffer = buffer.isEmpty
          ? buffer
          : Uint8List.fromList([buffer[buffer.length - 1]]);
    } else if (frameStart > 0) {
      buffer = Uint8List.fromList(buffer.sublist(frameStart));
      frameStart = 0;
    }
    if (buffer.length > maxFrameBytes) {
      buffer = Uint8List(0);
      frameStart = -1;
    }
    scanned = buffer.length;
  }
}

Uint8List _concat(Uint8List head, List<int> tail) {
  if (head.isEmpty) {
    return tail is Uint8List ? tail : Uint8List.fromList(tail);
  }
  final out = Uint8List(head.length + tail.length)
    ..setRange(0, head.length, head);
  out.setRange(head.length, out.length, tail);
  return out;
}
