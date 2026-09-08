import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/action_outcome.dart';
import '../../core/models/current_user.dart';
import '../../core/models/queue_settings.dart';
import '../../core/settings/server_profile.dart';
import '../../providers.dart';

/// Why the queue settings are on screen but cannot be changed. The rows stay
/// visible either way — reading the configuration is a smaller function, not a
/// blocked one — so each answer is a sentence the user can act on.
enum QueueSettingsLock {
  none,

  /// `SETTINGS_UPDATE` is outside the API-key scope allowlist and on the
  /// explicit denylist (`core/auth.py`): a 403 on every server version.
  apiKey,

  /// A named account without `settings:update`, or one refused by the route.
  permission,
}

/// Whether this session may write `PUT /settings/`, and why not when it may
/// not. Cannot reuse [identifiedPermissionProvider]: that answers `false` for
/// an unknown identity, and with authentication off server-side the route is
/// **open** — the one session with full rights would be the one locked out.
final queueSettingsLockProvider = FutureProvider<QueueSettingsLock>((
  ref,
) async {
  switch (ref.watch(serverProfileProvider)?.authMode) {
    case AuthMode.apiKey:
      return QueueSettingsLock.apiKey;
    case AuthMode.none:
      return QueueSettingsLock.none;
    case AuthMode.jwt:
    case null:
      // The route outranks `/auth/me`, which has been wrong about this before.
      final refused = !await ref
          .watch(serverSettingsRepositoryProvider)
          .writable();
      final granted = ref.watch(permissionProvider(Permissions.settingsUpdate));
      return refused || !granted
          ? QueueSettingsLock.permission
          : QueueSettingsLock.none;
  }
});

/// The queue / preheat / keep-warm block, and the writes to it. One key per
/// write: the body is partial, and saving the whole block would rewrite rows
/// the user never touched.
final queueSettingsProvider =
    AsyncNotifierProvider<QueueSettingsController, QueueSettings>(
      QueueSettingsController.new,
    );

class QueueSettingsController extends AsyncNotifier<QueueSettings> {
  /// The last block the server confirmed. [state] runs ahead of it during a
  /// drag and during a write, so a revert cannot read the value off [state].
  QueueSettings? _confirmed;

  @override
  Future<QueueSettings> build() async {
    final settings = QueueSettings.fromSettings(
      await ref.watch(serverSettingsProvider.future),
    );
    _confirmed = settings;
    return settings;
  }

  /// Shows [value] without writing it, for a thumb that is still moving: a
  /// request per pixel is not a save.
  void preview(QueueSetting setting, Object value) {
    if (state.valueOrNull case final current?) {
      state = AsyncValue.data(current.withValue(setting, value));
    }
  }

  /// Writes one setting, optimistically. A refusal puts the row back rather
  /// than leaving it reading "on" against a server where it is off; a success
  /// re-reads the map, which `require_plate_clear` and other gates derive from.
  Future<ActionOutcome> set(QueueSetting setting, Object value) async {
    final confirmed = _confirmed;
    if (confirmed == null || !confirmed.known.contains(setting)) {
      return ActionOutcome.ok;
    }
    preview(setting, value);
    final outcome = await runAction(
      () => ref
          .read(serverSettingsRepositoryProvider)
          .update(QueueSettings.patch(setting, value)),
      logId: 'queue_settings.${setting.key}',
      onSuccess: () async => ref.invalidate(serverSettingsProvider),
    );
    if (!outcome.isOk) {
      state = AsyncValue.data(confirmed);
      // Only a refusal moves the write latch — so the verdict is re-read here,
      // not on the success path, and a 403 closes the form.
      ref.invalidate(queueSettingsLockProvider);
    }
    return outcome;
  }
}
