import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reloads an [AsyncNotifier]'s state in place: the loading state keeps the
/// previous value (Riverpod attaches it), so the screen does not blank while
/// the request is out. A result that lands after disposal is dropped.
mixin ReloadInPlace<T> on AsyncNotifier<T> {
  Future<void> reloadInPlace(Future<T> Function() load) async {
    state = AsyncLoading<T>();
    final next = await AsyncValue.guard(load);
    if (!ref.mounted) return;
    state = next;
  }
}
