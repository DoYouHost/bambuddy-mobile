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
}
