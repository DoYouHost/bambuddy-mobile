import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/firmware.dart';
import '../../providers.dart';

/// Firmware for entire farm mapped by `printerId` — source for printer card
/// (version + "update available" flag). Firmware changes rarely and checking
/// hits cloud, so we DON'T poll: fetch once on entry and refresh explicitly
/// ([FirmwareNotifier.refresh], pull-to-refresh / after future update execution).
///
/// Error (cloud unreachable etc.) stays in `AsyncError` — card simply doesn't
/// show firmware (`valueOrNull == null`), never crashes dashboard.
final firmwareProvider =
    AsyncNotifierProvider<FirmwareNotifier, Map<int, FirmwareUpdateInfo>>(
  FirmwareNotifier.new,
);

class FirmwareNotifier extends AsyncNotifier<Map<int, FirmwareUpdateInfo>> {
  @override
  Future<Map<int, FirmwareUpdateInfo>> build() {
    // Rebuild on server profile change (different server → different firmware).
    ref.watch(serverProfileProvider);
    return _load();
  }

  Future<Map<int, FirmwareUpdateInfo>> _load() async {
    final resp = await ref.read(firmwareRepositoryProvider).fetchUpdates();
    return {
      for (final u in resp.updates)
        if (u.printerId != null) u.printerId!: u,
    };
  }

  /// Re-check firmware (preserves previous data underneath so UI doesn't flicker).
  /// Auth flows as [AuthException] — dashboard redirects to /setup.
  Future<void> refresh() async {
    state = const AsyncValue<Map<int, FirmwareUpdateInfo>>.loading()
        .copyWithPrevious(state);
    state = await AsyncValue.guard(_load);
  }
}

/// Single printer firmware (or `null` when no data/still loading).
/// Thin selector over [firmwareProvider] — card doesn't need to know map shape.
final printerFirmwareProvider =
    Provider.family<FirmwareUpdateInfo?, int>((ref, printerId) {
  return ref.watch(firmwareProvider).valueOrNull?[printerId];
});

/// Whether to expose firmware auth error externally. Kept here for future
/// UI flows to hook into (currently unused).
bool isFirmwareAuthError(Object? error) =>
    error is AuthException && error.code == AppErrorCode.unauthorized;
