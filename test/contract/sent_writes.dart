/// The writes a screen really sends, carried from its widget test to a live
/// server.
///
/// A widget test proves which requests a tap produces, against a mock that
/// answers whatever it is asked; a contract test proves what the server does
/// with a request, but one it spelled out by hand. Neither alone says that the
/// server accepts what the button sends. Here the widget test records its
/// writes to `test/fixtures/sent/<name>.json` (`flutter test --update-goldens`
/// rewrites the file, a plain run fails when the screen sends something else),
/// and the contract test replays that file on the docker server.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

typedef SentWrite = ({String method, String path, Object? body});

/// Every request in [requests] that changes something, oldest first.
List<SentWrite> writesOf(Iterable<RequestOptions> requests) => [
  for (final r in requests)
    if (r.method != 'GET') (method: r.method, path: r.path, body: r.data),
];

String _encode(List<SentWrite> writes) =>
    '${const JsonEncoder.withIndent('  ').convert([
      for (final w in writes) {'method': w.method, 'path': w.path, 'body': w.body},
    ])}\n';

/// Asserts [writes] are what `sent/[name].json` holds, or rewrites the file
/// under `--update-goldens`.
void expectSentAsRecorded(String name, List<SentWrite> writes) {
  final file = File('test/fixtures/sent/$name.json');
  if (autoUpdateGoldenFiles) {
    file
      ..createSync(recursive: true)
      ..writeAsStringSync(_encode(writes));
    return;
  }
  expect(
    _encode(writes),
    file.readAsStringSync(),
    reason:
        'the screen sends something else now: rerun with --update-goldens '
        'and run the contract test that replays $name on a live server',
  );
}

/// The writes recorded as [name].
List<SentWrite> recordedWrites(String name) => [
  for (final w in readFixture('sent/$name.json') as List<dynamic>)
    (method: w['method'] as String, path: w['path'] as String, body: w['body']),
];

/// Sends [writes] through [dio] in order and returns each answer; a refusal is
/// returned too, for the test to name. Ids that differ on the live server are
/// swapped in: [item] for the queue item in a path, and [ids] for the body keys
/// it names (a key the body lacks stays absent).
Future<List<Response<dynamic>>> replayWrites(
  Dio dio,
  List<SentWrite> writes, {
  int? item,
  Map<String, Object?> ids = const {},
}) async => [
  for (final w in writes)
    await dio.request<dynamic>(
      item == null
          ? w.path
          : w.path.replaceFirst(RegExp(r'(?<=/queue/)\d+'), '$item'),
      data: switch (w.body) {
        final Map<String, dynamic> body => {
          ...body,
          for (final e in ids.entries)
            if (body.containsKey(e.key)) e.key: e.value,
        },
        final other => other,
      },
      options: Options(method: w.method, validateStatus: (_) => true),
    ),
];
