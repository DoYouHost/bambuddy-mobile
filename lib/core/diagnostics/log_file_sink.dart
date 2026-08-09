import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'log_event.dart';

/// Append-only JSONL file for one stream of one session — the durable mirror
/// described in `docs/diagnostics-log.md`.
///
/// Writes are serialised through a future chain: [writeLine] is
/// fire-and-forget from the caller's side, but lines cannot interleave or land
/// out of order.
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

  /// The file's first line, or empty when there is none. Streams rather than
  /// reading the whole file: the UI stream can be hundreds of kilobytes by the
  /// time the background isolate wants its header. Appends land at the end, so
  /// a concurrent writer cannot disturb this.
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

  /// Whether the file already ends in a newline; false when it does not exist.
  /// A killed process can leave the last line torn even with a flush per write,
  /// and concatenating onto it costs two records — the tail of the old one and
  /// all of the new, both dropped as unparseable.
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
        await file.writeAsString('$line\n',
            mode: FileMode.append, flush: true);
      } on Object {
        // A broken sink must never take down the thing it was observing.
      }
    });
    return _chain;
  }

  /// Completes once everything enqueued so far is on disk, leaving the sink
  /// open. [writeLine] enqueues synchronously, so awaiting this right after one
  /// is an exact guarantee rather than a guess at how long the chain needs.
  Future<void> flush() => _chain;

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
