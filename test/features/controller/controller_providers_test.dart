import 'package:bambuddy_mobile/features/controller/controller_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
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

  test('a fresh install reads the defaults', () async {
    final container = await _container();

    expect(container.read(controllerPrefsProvider).liveCamera, isTrue);
  });

  test('a change reaches the state and the disk', () async {
    final container = await _container();

    await container
        .read(controllerPrefsProvider.notifier)
        .update((p) => p.copyWith(liveCamera: false));

    expect(container.read(controllerPrefsProvider).liveCamera, isFalse);
    expect(
      container
          .read(settingsRepositoryProvider)
          .loadControllerPrefs()
          .liveCamera,
      isFalse,
    );
  });

  test('two changes in a row both survive', () async {
    final container = await _container();
    final notifier = container.read(controllerPrefsProvider.notifier);

    // Not awaited between them: the second must build on the first.
    final first = notifier.update((p) => p.copyWith(keepAwake: false));
    final second = notifier.update((p) => p.copyWith(saverAfterMinutes: 15));
    await Future.wait([first, second]);

    final saved = container
        .read(settingsRepositoryProvider)
        .loadControllerPrefs();
    expect(saved.keepAwake, isFalse);
    expect(saved.saverAfterMinutes, 15);
    expect(container.read(controllerPrefsProvider).saverAfterMinutes, 15);
  });
}
