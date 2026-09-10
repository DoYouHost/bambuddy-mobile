import 'dart:async';

import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two shapes every flag derived from `/settings` now takes, and the
/// difference between them, which is the whole reason there are two.
///
/// A **gate** decides whether a control exists. Reading it as `false` while the
/// settings are still in flight shows the user a screen missing a button the
/// server does offer, so it stays unresolved until it has an answer.
///
/// A **value** picks a number, a symbol or a set of presets. There the server's
/// own default is a better thing to show than nothing, so it resolves at once.
/// Answers a fresh [Completer] on every build, so a test can hold the second
/// read open and look at what the readers report meanwhile.
class _RefetchingSettings extends ServerSettingsNotifier {
  final answers = <Completer<Map<String, dynamic>>>[];

  @override
  Future<Map<String, dynamic>> build() {
    final next = Completer<Map<String, dynamic>>();
    answers.add(next);
    return next.future;
  }

  @override
  Future<void> refresh() async {}
}

class _FailingSettings extends ServerSettingsNotifier {
  @override
  Future<Map<String, dynamic>> build() async => throw StateError('unreadable');

  @override
  Future<void> refresh() async {}
}

class _SlowSettings extends ServerSettingsNotifier {
  _SlowSettings(this._answer);

  final Completer<Map<String, dynamic>> _answer;

  @override
  Future<Map<String, dynamic>> build() => _answer.future;

  @override
  Future<void> refresh() async {}
}

void main() {
  late Completer<Map<String, dynamic>> answer;

  ProviderContainer containerWith() {
    answer = Completer<Map<String, dynamic>>();
    final container = ProviderContainer(
      overrides: [
        serverSettingsProvider.overrideWith(() => _SlowSettings(answer)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('serverGate', () {
    final gate = serverGate<bool>((s) => s['flag'] == true);

    test('does not settle to "off" while the settings are in flight', () async {
      // The bug this shape exists to stop: a slice button absent from a screen
      // the server would have allowed it on, because the fetch had not landed.
      //
      // Draining the event loop first is the point — a gate that read the
      // settings without awaiting them would also look loading for one frame,
      // and then quietly settle to false with nothing having answered.
      final container = containerWith();
      container.listen(gate, (_, _) {});

      await Future<void>.delayed(Duration.zero);

      expect(container.read(gate).isLoading, isTrue);
      expect(container.read(gate).valueOrNull, isNull);
    });

    test('answers what the server said, once it has said it', () async {
      final container = containerWith();
      answer.complete({'flag': true});

      await container.read(serverSettingsProvider.future);

      expect(container.read(gate).valueOrNull, isTrue);
    });

    test('answers in the same build once the settings are known', () async {
      // The screen that opens second, when `/settings` is long since in. An
      // `async` body would still report one loading frame here, and a caller
      // collapsing that with `.orFalse` would blink the control out — the gate
      // inventing the "don't know" it exists to prevent.
      final container = containerWith();
      answer.complete({'flag': true});
      await container.read(serverSettingsProvider.future);

      final first = container.read(gate);

      expect(first.isLoading, isFalse);
      expect(first.valueOrNull, isTrue);
    });

    test('keeps the answer it has while a fresh read is in flight', () async {
      // "Change server" and a settings write both re-run the fetch. Dropping
      // back to "don't know" for its duration would withdraw a control the
      // user is looking at.
      final settings = _RefetchingSettings();
      final container = ProviderContainer(
        overrides: [serverSettingsProvider.overrideWith(() => settings)],
      );
      addTearDown(container.dispose);
      container.listen(gate, (_, _) {});
      settings.answers.first.complete({'flag': true});
      await container.read(serverSettingsProvider.future);

      container.invalidate(serverSettingsProvider);
      await Future<void>.delayed(Duration.zero);

      expect(settings.answers, hasLength(2), reason: 'the refetch has started');
      expect(container.read(gate).valueOrNull, isTrue);
    });

    test(
      'a read that throws reaches the caller as an error, not as off',
      () async {
        // `fetch` degrades network failures itself, so only a real defect gets
        // here — and it must not look like a server that answered "no".
        final container = ProviderContainer(
          overrides: [
            serverSettingsProvider.overrideWith(_FailingSettings.new),
          ],
        );
        addTearDown(container.dispose);

        expect(container.read(serverSettingsProvider.future), throwsStateError);
        await pumpEventQueue();
        expect(container.read(gate).hasError, isTrue);
        expect(container.read(gate).valueOrNull, isNull);
      },
    );

    test('a server that says nothing is a real "off", not a pending one', () {
      // `fetch` degrades every failure to an empty map, so the gate always
      // settles — "off" here means answered, and the caller may act on it.
      final container = containerWith();
      answer.complete(const {});

      expect(
        container
            .read(serverSettingsProvider.future)
            .then((_) => container.read(gate).valueOrNull),
        completion(isFalse),
      );
    });
  });

  group('serverValue', () {
    final value = serverValue<int>((s) => (s['limit'] as num?)?.toInt() ?? 50);

    test('resolves to the fallback immediately, without waiting', () {
      // A spinner in the middle of a price column or a stepper would be worse
      // than the default it replaces, and the default is the server's own.
      final container = containerWith();

      expect(container.read(value), 50);
    });

    test('swaps in the real answer when the settings land', () async {
      final container = containerWith();
      expect(container.read(value), 50);

      answer.complete({'limit': 7});
      await container.read(serverSettingsProvider.future);

      expect(container.read(value), 7);
    });
  });

  test('a settings write reaches both shapes at once', () async {
    // `adopt` takes the map a `PUT /settings/` answered with instead of asking
    // again, so it is the write path every flag in the app updates through.
    final container = containerWith();
    final gate = serverGate<bool>((s) => s['flag'] == true);
    final value = serverValue<int>((s) => (s['limit'] as num?)?.toInt() ?? 50);
    answer.complete(const {});
    await container.read(serverSettingsProvider.future);

    container.read(serverSettingsProvider.notifier).adopt({
      'flag': true,
      'limit': 7,
    });
    await Future<void>.delayed(Duration.zero);

    expect(container.read(gate).valueOrNull, isTrue);
    expect(container.read(value), 7);
  });
}
