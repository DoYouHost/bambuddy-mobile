import 'dart:io';

import 'package:bambuddy_mobile/core/diagnostics/log_event.dart';
import 'package:bambuddy_mobile/core/diagnostics/log_file_sink.dart';
import 'package:bambuddy_mobile/core/diagnostics/log_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('bambuddy_logs'));
  tearDown(() => dir.deleteSync(recursive: true));

  LogHeader header(LogStream stream) => LogHeader(
        ts: DateTime.utc(2026, 7, 25, 12),
        session: 'sess1',
        app: '0.11.2+1102',
        flavor: 'mobile',
        stream: stream,
      );

  test('names the fgs stream apart from the ui one', () {
    expect(
      LogFileSink.fileFor(dir, 'sess1', LogStream.ui).path,
      endsWith('session-sess1.jsonl'),
    );
    expect(
      LogFileSink.fileFor(dir, 'sess1', LogStream.fgs).path,
      endsWith('session-sess1-fgs.jsonl'),
    );
  });

  test('writes the header and appends lines in order', () async {
    final sink = LogFileSink(LogFileSink.fileFor(dir, 'sess1', LogStream.fgs));

    await sink.writeHeader(header(LogStream.fgs));
    for (var i = 0; i < 20; i++) {
      sink.writeLine('{"t":$i}');
    }
    await sink.close();

    final lines = (await sink.read()).trim().split('\n');
    expect(lines, hasLength(21));
    expect(lines.first, contains('"stream":"fgs"'));
    expect(lines[1], '{"t":0}');
    expect(lines.last, '{"t":19}');
  });

  test('a store mirrors its records into the file', () async {
    final sink = LogFileSink(LogFileSink.fileFor(dir, 'sess1', LogStream.fgs));
    await sink.writeHeader(header(LogStream.fgs));

    final store = LogStore(header: header(LogStream.fgs), onLine: sink.writeLine)
      ..add(LogSource.fgs, 'cycle', fields: const {'printers': 2});
    await sink.close();

    expect(store.recordCount, 1);
    expect(await sink.read(), contains('"evt":"cycle"'));
  });

  test('reading a file that was never written yields empty, not a throw',
      () async {
    final sink = LogFileSink(LogFileSink.fileFor(dir, 'missing', LogStream.ui));

    expect(await sink.read(), isEmpty);
  });

  test('writes after close are dropped silently', () async {
    final sink = LogFileSink(LogFileSink.fileFor(dir, 'sess1', LogStream.ui));

    await sink.writeHeader(header(LogStream.ui));
    await sink.close();
    sink.writeLine('{"late":true}');

    expect(await sink.read(), isNot(contains('late')));
  });

  test('delete removes the file and tolerates a missing one', () async {
    final sink = LogFileSink(LogFileSink.fileFor(dir, 'sess1', LogStream.ui));

    await sink.writeHeader(header(LogStream.ui));
    await sink.delete();
    await sink.delete();

    expect(sink.file.existsSync(), isFalse);
  });

  test('names the notification-action stream apart too', () {
    expect(
      LogFileSink.fileFor(dir, 'sess1', LogStream.action).path,
      endsWith('session-sess1-act.jsonl'),
    );
  });

  group('reading the session header back', () {
    test('returns the first line without reading the rest', () async {
      // The background isolate needs the UI stream's header, and by then that file
      // can be hundreds of kilobytes.
      final sink = LogFileSink(LogFileSink.fileFor(dir, 'sess1', LogStream.ui));
      await sink.writeHeader(header(LogStream.ui));
      for (var i = 0; i < 50; i++) {
        sink.writeLine('{"t":$i,"src":"ui","evt":"tap"}');
      }
      await sink.close();

      expect(await sink.readFirstLine(), contains('"stream":"ui"'));
    });

    test('a missing file reads as empty, not as a throw', () async {
      final sink = LogFileSink(LogFileSink.fileFor(dir, 'nope', LogStream.ui));

      expect(await sink.readFirstLine(), isEmpty);
    });
  });

  group('appending to a file another isolate left behind', () {
    test('a complete file reports a trailing newline', () async {
      final sink = LogFileSink(LogFileSink.fileFor(dir, 'sess1', LogStream.fgs));
      await sink.writeHeader(header(LogStream.fgs));

      expect(await sink.endsWithNewline(), isTrue);
    });

    test('a torn last line does not, and a missing file does not either',
        () async {
      final file = LogFileSink.fileFor(dir, 'sess1', LogStream.fgs);
      final sink = LogFileSink(file);
      expect(await sink.endsWithNewline(), isFalse); // no file yet

      // What a process killed mid-write leaves: no closing newline. Appending
      // straight onto it would glue two records into one unparseable line and
      // cost both.
      file.writeAsStringSync('{"t":1,"src":"fgs","ev');

      expect(await sink.endsWithNewline(), isFalse);
    });
  });
}
