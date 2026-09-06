import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/api_key.dart';
import '../../core/models/current_user.dart';
import '../../core/models/printer.dart';
import '../../providers.dart';

/// The keys issued on this server.
final apiKeysListProvider =
    AutoDisposeAsyncNotifierProvider<ApiKeysListNotifier, List<ApiKey>>(
      ApiKeysListNotifier.new,
    );

class ApiKeysListNotifier extends AutoDisposeAsyncNotifier<List<ApiKey>> {
  @override
  Future<List<ApiKey>> build() async {
    ref.watch(serverProfileProvider);
    return ref.read(apiKeysRepositoryProvider).list();
  }

  Future<void> refresh() async {
    state = const AsyncValue<List<ApiKey>>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard(
      () => ref.read(apiKeysRepositoryProvider).list(),
    );
  }
}

/// Printers a key can be confined to. Failure degrades to an empty list: the
/// restriction picker disappears and the key is simply issued for all
/// printers, which is the server's own default.
final apiKeyPrinterOptionsProvider = FutureProvider.autoDispose<List<Printer>>((
  ref,
) async {
  ref.watch(serverProfileProvider);
  try {
    return await ref.read(printersRepositoryProvider).fetchPrinters();
  } on AppApiException {
    return const [];
  }
});

/// Whether the signed-in identity may see the keys.
final canReadApiKeysProvider = Provider<bool>(
  (ref) => ref.watch(identifiedPermissionProvider(Permissions.apiKeysRead)),
);

/// Whether it may issue a new one. Unlike users and groups these routes have no
/// admin gate — the permission is the whole check
/// (`backend/app/api/routes/api_keys.py::create_api_key`), so a custom group
/// granting `api_keys:create` really can.
final canCreateApiKeysProvider = Provider<bool>(
  (ref) => ref.watch(identifiedPermissionProvider(Permissions.apiKeysCreate)),
);

final canUpdateApiKeysProvider = Provider<bool>(
  (ref) => ref.watch(identifiedPermissionProvider(Permissions.apiKeysUpdate)),
);

final canRevokeApiKeysProvider = Provider<bool>(
  (ref) => ref.watch(identifiedPermissionProvider(Permissions.apiKeysDelete)),
);
