import 'package:bambuddy_mobile/features/dashboard/card_collapse_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container([
  Map<String, Object> initial = const {},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    retry: neverRetry,
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an install that never chose keeps its cards expanded', () async {
    final container = await _container();

    expect(container.read(printerCardCollapseProvider).isCollapsed(1), isFalse);
  });

  test('the setting is read from the key it is written to', () async {
    final container = await _container({'printer_cards_collapsed': true});

    expect(container.read(printerCardCollapseProvider).isCollapsed(1), isTrue);
  });

  test('toggling one card leaves the others on the setting', () async {
    final container = await _container({'printer_cards_collapsed': true});

    container.read(printerCardCollapseProvider.notifier).set(1, false);

    final collapse = container.read(printerCardCollapseProvider);
    expect(collapse.isCollapsed(1), isFalse);
    expect(collapse.isCollapsed(2), isTrue);
  });

  test('changing the setting puts every card back on it', () async {
    final container = await _container();
    container.read(printerCardCollapseProvider.notifier).set(1, false);
    container.read(printerCardCollapseProvider.notifier).set(2, true);

    await container
        .read(printerCardsCollapsedByDefaultProvider.notifier)
        .set(true);

    final collapse = container.read(printerCardCollapseProvider);
    expect(collapse.isCollapsed(1), isTrue);
    expect(collapse.isCollapsed(2), isTrue);
    expect(
      container.read(settingsRepositoryProvider).loadPrinterCardsCollapsed(),
      isTrue,
    );
  });

  test('a hand toggle is not written down', () async {
    final container = await _container();

    container.read(printerCardCollapseProvider.notifier).set(1, true);

    final prefs = container.read(sharedPreferencesProvider);
    expect(prefs.getKeys(), isEmpty);
  });

  group('compact AMS tiles', () {
    test('an install that never chose keeps the detailed rows', () async {
      final container = await _container();

      expect(container.read(compactAmsLayoutProvider), isFalse);
      expect(container.read(printerCompactAmsProvider).isCompact(1), isFalse);
    });

    test('the setting is read from the key it is written to', () async {
      final container = await _container({'compact_ams_layout': true});

      expect(container.read(printerCompactAmsProvider).isCompact(1), isTrue);
    });

    test('switching one card leaves the others on the setting', () async {
      final container = await _container({'compact_ams_layout': true});

      container.read(printerCompactAmsProvider.notifier).set(1, false);

      final compact = container.read(printerCompactAmsProvider);
      expect(compact.isCompact(1), isFalse);
      expect(compact.isCompact(2), isTrue);
    });

    test('changing the setting puts every card back on it', () async {
      final container = await _container();
      container.read(printerCompactAmsProvider.notifier).set(1, true);
      container.read(printerCompactAmsProvider.notifier).set(2, false);

      await container.read(compactAmsLayoutProvider.notifier).set(true);

      final compact = container.read(printerCompactAmsProvider);
      expect(compact.isCompact(1), isTrue);
      expect(compact.isCompact(2), isTrue);
      expect(
        container.read(settingsRepositoryProvider).loadCompactAmsLayout(),
        isTrue,
      );
    });

    test('a hand switch is not written down', () async {
      final container = await _container();

      container.read(printerCompactAmsProvider.notifier).set(1, true);

      expect(container.read(sharedPreferencesProvider).getKeys(), isEmpty);
    });

    test('a switch that outlives its container does not throw', () async {
      final container = await _container();

      final pending = container
          .read(compactAmsLayoutProvider.notifier)
          .set(true);
      container.dispose();

      await expectLater(pending, completes);
    });

    test('the two settings do not share a key', () async {
      final container = await _container({'printer_cards_collapsed': true});

      expect(container.read(compactAmsLayoutProvider), isFalse);
    });
  });
}
