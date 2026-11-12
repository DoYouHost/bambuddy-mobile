import 'dart:async';

import 'package:bambuddy_mobile/core/auth/credentials_store.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A repository whose profile removal is still out when the test says so.
class _SlowClear extends SettingsRepository {
  _SlowClear(super.prefs);

  final gate = Completer<void>();

  @override
  Future<void> clearProfile() async {
    await gate.future;
    await super.clearProfile();
  }
}

void main() {
  test(
    'logging out clears the secrets even when the provider is gone first',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = _SlowClear(prefs);
      final store = InMemoryCredentialsStore()
        ..jwt = 'token'
        ..apiKey = 'key'
        ..username = 'user'
        ..password = 'pass';
      final container = ProviderContainer(
        retry: neverRetry,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          settingsRepositoryProvider.overrideWithValue(repo),
          credentialsStoreProvider.overrideWithValue(store),
        ],
      );

      final done = container.read(serverProfileProvider.notifier).clear();
      // The tour's container, a teardown: the write is still out when it goes.
      container.dispose();
      repo.gate.complete();
      await done;

      expect(store.jwt, isNull);
      expect(store.apiKey, isNull);
      expect(await store.readRememberedLogin(), isNull);
    },
  );
}
