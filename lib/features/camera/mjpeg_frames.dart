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
/// Markers split across two chunks are handled through the last byte of the
/// previous chunk.
///
/// Each chunk is scanned once and copied into the frame being collected once,
/// so the cost stays linear in the bytes received. Re-joining a growing buffer
/// with every chunk — what this did before — is quadratic, and a frame that
/// never ends made that hundreds of megabytes of copying on the UI isolate
/// before the cap dropped it.
Stream<Uint8List> mjpegFrames(
  Stream<List<int>> chunks, {
  int maxFrameBytes = defaultMaxFrameBytes,
}) async* {
  final frame = BytesBuilder();
  var inFrame = false;
  var previous = -1; // Last byte of the previous chunk, -1 before the first.

  await for (final chunk in chunks) {
    if (chunk.isEmpty) continue;
    final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
    var from = 0; // Start of this chunk's part of the frame being collected.

    for (var i = 0; i < bytes.length; i++) {
      final before = i == 0 ? previous : bytes[i - 1];
      if (before != _marker) continue;
      final byte = bytes[i];
      if (!inFrame && byte == _soi) {
        inFrame = true;
        frame.clear();
        if (i == 0) {
          frame.addByte(_marker); // The FF ended the previous chunk.
          from = 0;
        } else {
          from = i - 1;
        }
      } else if (inFrame && byte == _eoi) {
        frame.add(Uint8List.sublistView(bytes, from, i + 1));
        yield frame.takeBytes();
        inFrame = false;
      }
    }

    if (inFrame) {
      frame.add(Uint8List.sublistView(bytes, from));
      if (frame.length > maxFrameBytes) {
        frame.clear();
        inFrame = false;
      }
    }
    previous = bytes.last;
  }
}
