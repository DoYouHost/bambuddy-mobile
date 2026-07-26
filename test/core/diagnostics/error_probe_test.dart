import 'dart:convert';

import 'package:bambuddy_mobile/core/diagnostics/error_probe.dart';
import 'package:bambuddy_mobile/core/diagnostics/log_event.dart';
import 'package:bambuddy_mobile/core/diagnostics/log_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final start = DateTime.utc(2026, 7, 26, 12);
  late DateTime now;
  late LogStore store;
  late ErrorProbe probe;

  setUp(() {
    now = start;
    store = LogStore(
      header: LogHeader(
        ts: start,
        session: 'test',
        app: '0.11.2+1102',
        flavor: 'mobile',
      ),
      clock: () => now,
    );
    probe = ErrorProbe(store: store);
  });

  /// Attaches for the body and detaches after it, which is also what writes out
  /// a pending repeat count. The teardown is the belt to that braces: a leaked
  /// handler would swallow the *next* test's failures.
  void withProbe(void Function() body) {
    probe.attach();
    addTearDown(probe.detach);
    body();
    probe.detach();
  }

  List<Map<String, dynamic>> records() => [
    for (final line in const LineSplitter().convert(store.export()).skip(1))
      jsonDecode(line) as Map<String, dynamic>,
  ];

  void throwAsync(Object error, [StackTrace? stack]) {
    PlatformDispatcher.instance.onError!(error, stack ?? StackTrace.empty);
  }

  void throwInBuild(Object error, {String? context}) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: StackTrace.fromString('#0      Card.build (card.dart:12:3)'),
        library: 'widgets library',
        context: context == null ? null : ErrorDescription(context),
      ),
    );
  }

  test('records an error nobody caught', () {
    withProbe(
      () => throwAsync(
        const FormatException('Unexpected character'),
        StackTrace.fromString('#0      parse (spool.dart:9:1)'),
      ),
    );

    final record = records().single;
    expect(record['src'], 'err');
    expect(record['lvl'], 'error');
    expect(record['evt'], 'uncaught');
    expect(record['via'], 'async');
    expect(record['type'], 'FormatException');
    // The class name rides in `type`; repeating it in the message is padding.
    expect(record['msg'], 'Unexpected character');
    expect(record['stack'], contains('spool.dart'));
  });

  test('records where the framework was when it broke', () {
    withProbe(
      () => throwInBuild(
        StateError('setState after dispose'),
        context: 'while handling a gesture',
      ),
    );

    final record = records().single;
    expect(record['via'], 'flutter');
    expect(record['ctx'], 'while handling a gesture');
    expect(record['type'], 'StateError');
    expect(record['stack'], contains('card.dart'));
  });

  test('leaves the app behaving exactly as it did', () {
    // The red screen in debug and the console line both come from the handler
    // that was there before; a recording must not silence them.
    final seen = <Object>[];
    final previousFlutter = FlutterError.onError;
    final previousPlatform = PlatformDispatcher.instance.onError;
    FlutterError.onError = (details) => seen.add(details.exception);
    PlatformDispatcher.instance.onError = (error, _) {
      seen.add(error);
      return true;
    };
    final mine = FlutterError.onError;
    addTearDown(() {
      FlutterError.onError = previousFlutter;
      PlatformDispatcher.instance.onError = previousPlatform;
    });

    probe.attach();
    throwInBuild(StateError('framework'));
    final handled = PlatformDispatcher.instance.onError!(
      StateError('async'),
      StackTrace.empty,
    );
    probe.detach();

    expect(seen.map((e) => '$e'), ['Bad state: framework', 'Bad state: async']);
    // And its answer is passed through, not invented.
    expect(handled, isTrue);
    // Detaching puts back what it found, not the probe's wrapper.
    expect(FlutterError.onError, same(mine));
    throwInBuild(StateError('after detach'));
    expect(records(), hasLength(2));
  });

  test('counts a storm instead of drowning in it', () {
    // A widget that throws in build throws again every frame.
    withProbe(() {
      for (var frame = 0; frame < 60; frame++) {
        throwInBuild(RangeError('index 5 out of range'));
      }
    });

    final all = records();
    expect(all, hasLength(2));
    expect(all.first['evt'], 'uncaught');
    expect(all.first['msg'], contains('index 5 out of range'));
    expect(all.last['evt'], 'repeated');
    expect(all.last['type'], 'RangeError');
    expect(all.last['n'], 59);
  });

  test('a different error ends the burst it interrupted', () {
    withProbe(() {
      throwInBuild(RangeError('a'));
      throwInBuild(RangeError('a'));
      throwInBuild(RangeError('a'));
      throwAsync(const FormatException('b'));
    });

    expect(records().map((r) => [r['evt'], r['n']]), [
      ['uncaught', null],
      ['repeated', 2],
      ['uncaught', null],
    ]);
  });

  test('the same error from another place is another error', () {
    withProbe(() {
      throwAsync(
        RangeError('index 5 out of range'),
        StackTrace.fromString('#0      grid (dashboard.dart:1:1)'),
      );
      throwAsync(
        RangeError('index 5 out of range'),
        StackTrace.fromString('#0      list (inventory.dart:1:1)'),
      );
    });

    expect(records().map((r) => r['evt']), ['uncaught', 'uncaught']);
  });

  test('a storm that keeps going reports itself while it lasts', () {
    // Otherwise a burst that outlives the app is a count nobody ever writes.
    withProbe(() {
      throwInBuild(RangeError('looping'));
      throwInBuild(RangeError('looping'));
      now = start.add(const Duration(seconds: 6));
      throwInBuild(RangeError('looping'));
      throwInBuild(RangeError('looping'));
    });

    final all = records();
    expect(all.map((r) => r['evt']), ['uncaught', 'repeated', 'repeated']);
    // Two while the window was open, then the tail on detach.
    expect(all[1]['n'], 2);
    expect(all[1]['t'], const Duration(seconds: 6).inMilliseconds);
    expect(all[2]['n'], 1);
  });

  test('a count belongs to when the errors happened, not to when it was '
      'written down', () {
    // The tail of a burst is written out at the end of the recording. Stamping
    // it then would put a storm that stopped after two seconds at the far end
    // of the session, next to records it has nothing to do with.
    withProbe(() {
      throwInBuild(RangeError('looping'));
      now = start.add(const Duration(seconds: 2));
      throwInBuild(RangeError('looping'));
      now = start.add(const Duration(seconds: 30));
    });

    final last = records().last;
    expect(last['evt'], 'repeated');
    expect(last['t'], const Duration(seconds: 2).inMilliseconds);
  });

  test('a message carrying the server host is scrubbed like any other', () {
    store.redactor.remember('printer.lan', '[HOST]');

    withProbe(
      () => throwAsync(
        const SocketExceptionLike("Failed host lookup: 'printer.lan'"),
      ),
    );

    final record = records().single;
    expect(record['msg'], contains('[HOST]'));
    expect(record['msg'], isNot(contains('printer.lan')));
  });
}

/// Stands in for `SocketException` without dragging `dart:io` into a test that
/// only cares about the message.
class SocketExceptionLike implements Exception {
  const SocketExceptionLike(this.message);

  final String message;

  @override
  String toString() => 'SocketExceptionLike: $message';
}
