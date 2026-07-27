import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'log_event.dart';

/// Append-only JSONL file for one stream of one session.
///
/// Exists for the foreground-service isolate: it has its own heap and can be
/// killed by the system at any time, so anything it logs must already be on
/// disk when the UI comes to collect it. Writes are serialised through a
/// future chain — [writeLine] is fire-and-forget from the caller's side but
/// lines can't interleave or land out of order.
class LogFileSink {
  LogFileSink(this.file);

  final File file;

  Future<void> _chain = Future<void>.value();
  bool _closed = false;

  /// `session-<id>.jsonl`, plus a suffix naming any stream that is not the UI's.
  static File fileFor(Directory dir, String session, LogStream stream) {
    final suffix = switch (stream) {
      LogStream.ui => '',
      LogStream.fgs => '-fgs',
      LogStream.action => '-act',
    };
    return File('${dir.path}/session-$session$suffix.jsonl');
  }

  Future<void> writeHeader(LogHeader header) => _enqueue(header.toJsonLine());

  void writeLine(String line) => unawaited(_enqueue(line));

  /// The file's first line, or empty when there is none.
  ///
  /// Streams rather than reading the whole file: the UI stream can be hundreds of
  /// kilobytes by the time the background isolate wants its header, and the
  /// header is the first thing in it. Appends land at the end, so a concurrent
  /// writer cannot disturb this.
  Future<String> readFirstLine() async {
    try {
      if (!await file.exists()) return '';
      final lines = file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        return line;
      }
      return '';
    } on Object {
      return '';
    }
  }

  /// Whether the file already ends in a newline, so an append cannot glue itself
  /// onto a half-written record. False for a file that does not exist.
  ///
  /// A killed process can leave the last line torn even with a flush per write.
  /// Concatenating onto it costs two records: the tail of the old one and all of
  /// the new one, both dropped as unparseable.
  Future<bool> endsWithNewline() async {
    try {
      final length = await file.length();
      if (length == 0) return false;
      final handle = await file.open();
      try {
        await handle.setPosition(length - 1);
        final tail = await handle.read(1);
        return tail.isNotEmpty && tail.first == 0x0a;
      } finally {
        await handle.close();
      }
    } on Object {
      return false;
    }
  }

  Future<void> _enqueue(String line) {
    if (_closed) return Future<void>.value();
    _chain = _chain.then((_) async {
      try {
        // Flushing every line costs an fsync-ish write, which is fine at the
        // rate the background isolate logs — and it's the whole point: an
        // unflushed buffer dies with the service.
        await file.writeAsString('$line\n',
            mode: FileMode.append, flush: true);
      } on Object {
        // A broken sink must never take down the thing it was observing.
      }
    });
    return _chain;
  }

  /// Waits for queued writes to land, then refuses further ones.
  Future<void> close() async {
    await _chain;
    _closed = true;
  }

  Future<String> read() async {
    try {
      return (await file.exists()) ? await file.readAsString() : '';
    } on Object {
      return '';
    }
  }

  Future<void> delete() async {
    try {
      if (await file.exists()) await file.delete();
    } on Object {
      // Nothing to do — a leftover file is bounded by the ring caps anyway.
    }
  }
}
