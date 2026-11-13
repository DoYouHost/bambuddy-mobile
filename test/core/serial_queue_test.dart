import 'dart:async';

import 'package:bambuddy_mobile/core/serial_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runs tasks one after another, in order', () async {
    final queue = SerialQueue();
    final log = <String>[];
    final gate = Completer<void>();
    final first = queue.run(() async {
      log.add('first starts');
      await gate.future;
      log.add('first ends');
    });
    final second = queue.run(() async => log.add('second'));
    await Future<void>.delayed(Duration.zero);
    expect(log, ['first starts'], reason: 'the second waits for the first');

    gate.complete();
    await Future.wait([first, second]);
    expect(log, ['first starts', 'first ends', 'second']);
  });

  test('a failed task reaches its caller and does not stop the next', () async {
    final queue = SerialQueue();
    final failed = queue.run<void>(() async => throw StateError('boom'));
    final next = queue.run(() async => 42);
    await expectLater(failed, throwsStateError);
    expect(await next, 42);
  });
}
