import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/controller_prefs.dart';
import '../../providers.dart';

/// The controller's settings on this device.
final controllerPrefsProvider =
    NotifierProvider<ControllerPrefsNotifier, ControllerPrefs>(
      ControllerPrefsNotifier.new,
    );

class ControllerPrefsNotifier extends Notifier<ControllerPrefs> {
  @override
  ControllerPrefs build() =>
      ref.watch(settingsRepositoryProvider).loadControllerPrefs();

  /// State first, then disk: two settings changed in quick succession must each
  /// start from the other's result, not from what was on disk before either.
  Future<void> update(ControllerPrefs Function(ControllerPrefs) change) async {
    state = change(state);
    await ref.read(settingsRepositoryProvider).saveControllerPrefs(state);
  }
}
