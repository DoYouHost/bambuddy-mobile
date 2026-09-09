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

      expect(await container.read(gate.future), isTrue);
    });

    test('a server that says nothing is a real "off", not a pending one', () {
      // `fetch` degrades every failure to an empty map, so the gate always
      // settles — "off" here means answered, and the caller may act on it.
      final container = containerWith();
      answer.complete(const {});

      expect(container.read(gate.future), completion(isFalse));
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
}
