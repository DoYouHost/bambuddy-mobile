import 'dart:async';

import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where the server-wide low-stock number comes from: the settings, and the
/// flags only for a session whose settings answered without it.
class _Settings extends ServerSettingsNotifier {
  _Settings(this._answer);

  final Future<Map<String, dynamic>> _answer;

  @override
  Future<Map<String, dynamic>> build() => _answer;
}

void main() {
  late int flagReads;

  ProviderContainer container(
    Future<Map<String, dynamic>> settings, {
    Map<String, dynamic> flags = const {},
  }) {
    flagReads = 0;
    final c = ProviderContainer(
      overrides: [
        serverSettingsProvider.overrideWith(() => _Settings(settings)),
        serverUiFlagsProvider.overrideWith((ref) async {
          flagReads++;
          return flags;
        }),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('the settings answer is used, and the flags are never asked', () async {
    final c = container(
      Future.value({'low_stock_threshold': 12.5}),
      flags: {'low_stock_threshold': 3},
    );
    await c.read(serverSettingsProvider.future);
    expect(c.read(lowStockThresholdProvider), 12.5);
    expect(c.read(serverHasLowStockProvider), isTrue);
    expect(flagReads, 0);
  });

  test('the flags are not asked while the settings are still on their way', () {
    final c = container(Completer<Map<String, dynamic>>().future);
    expect(c.read(lowStockThresholdProvider), 20);
    expect(c.read(serverHasLowStockProvider), isFalse);
    expect(flagReads, 0);
  });

  test('a settings answer without the key falls back to the flags', () async {
    final c = container(
      Future.value(const <String, dynamic>{}),
      flags: {'low_stock_threshold': 7},
    );
    await c.read(serverSettingsProvider.future);
    c.listen(lowStockThresholdProvider, (_, _) {});
    await pumpEventQueue();
    expect(c.read(lowStockThresholdProvider), 7);
    expect(c.read(serverHasLowStockProvider), isTrue);
    expect(flagReads, 1);
  });

  test('and to 20, with no threshold stated, when neither has it', () async {
    final c = container(Future.value(const <String, dynamic>{}));
    await c.read(serverSettingsProvider.future);
    c.listen(lowStockThresholdProvider, (_, _) {});
    await pumpEventQueue();
    expect(c.read(lowStockThresholdProvider), 20);
    expect(c.read(serverHasLowStockProvider), isFalse);
  });
}
