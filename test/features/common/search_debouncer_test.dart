import 'package:bambuddy_mobile/features/common/search_debouncer.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const delay = Duration(milliseconds: 300);

  test('fires only the last of a burst, after the delay and not before', () {
    fakeAsync((async) {
      final debouncer = SearchDebouncer(delay);
      final received = <String>[];

      debouncer
        ..run('a', received.add)
        ..run('ab', received.add)
        ..run('abc', received.add);

      async.elapse(delay - const Duration(milliseconds: 1));
      expect(received, isEmpty);

      async.elapse(const Duration(milliseconds: 1));
      expect(received, ['abc']);

      async.elapse(delay * 2);
      expect(received, ['abc'], reason: 'a fired call must not repeat');
    });
  });

  test('a new call restarts the wait instead of firing on the first timer', () {
    fakeAsync((async) {
      final debouncer = SearchDebouncer(delay);
      final received = <String>[];

      debouncer.run('first', received.add);
      async.elapse(const Duration(milliseconds: 200));
      debouncer.run('second', received.add);

      async.elapse(const Duration(milliseconds: 200));
      expect(
        received,
        isEmpty,
        reason: '400 ms in, but only 200 ms since the restart',
      );

      async.elapse(const Duration(milliseconds: 100));
      expect(received, ['second']);
    });
  });

  test('the query arrives trimmed', () {
    fakeAsync((async) {
      final debouncer = SearchDebouncer(delay);
      final received = <String>[];

      debouncer.run('  benchy \t', received.add);
      async.elapse(delay);

      expect(received, ['benchy']);
    });
  });

  test('an empty or whitespace-only query still fires, as an empty string', () {
    fakeAsync((async) {
      final debouncer = SearchDebouncer(delay);
      final received = <String>[];

      debouncer.run('   ', received.add);
      async.elapse(delay);

      expect(received, ['']);
    });
  });

  test('cancel() prevents the pending call', () {
    fakeAsync((async) {
      final debouncer = SearchDebouncer(delay);
      final received = <String>[];

      debouncer.run('gone', received.add);
      debouncer.cancel();
      async.elapse(delay * 2);

      expect(received, isEmpty);
    });
  });

  test('dispose() prevents the pending call', () {
    fakeAsync((async) {
      final debouncer = SearchDebouncer(delay);
      final received = <String>[];

      debouncer.run('gone', received.add);
      debouncer.dispose();
      async.elapse(delay * 2);

      expect(received, isEmpty);
    });
  });

  test(
    'cancel() on an idle debouncer is harmless and later runs still fire',
    () {
      fakeAsync((async) {
        final debouncer = SearchDebouncer(delay)..cancel();
        final received = <String>[];

        debouncer.run('ok', received.add);
        async.elapse(delay);

        expect(received, ['ok']);
      });
    },
  );
}
