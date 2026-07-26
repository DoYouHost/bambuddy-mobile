import 'dart:async';
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

  /// `session-<id>.jsonl` / `session-<id>-fgs.jsonl` inside [dir].
  static File fileFor(Directory dir, String session, LogStream stream) {
    final suffix = stream == LogStream.fgs ? '-fgs' : '';
    return File('${dir.path}/session-$session$suffix.jsonl');
  }

  Future<void> writeHeader(LogHeader header) => _enqueue(header.toJsonLine());

  void writeLine(String line) => unawaited(_enqueue(line));

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
