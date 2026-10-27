import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/makerworld.dart';
import '../../providers.dart';

/// State of "resolve URL" action on MakerWorld screen. `null` (data) = nothing
/// resolved yet (initial state); loading during request; error with exception.
final makerworldResolveProvider =
    AsyncNotifierProvider<MakerWorldResolveNotifier, MakerWorldResolvedModel?>(
      MakerWorldResolveNotifier.new,
    );

class MakerWorldResolveNotifier
    extends AsyncNotifier<MakerWorldResolvedModel?> {
  @override
  Future<MakerWorldResolvedModel?> build() async => null;

  /// Resolves [url]; empty URL clears result. Result lands in [state].
  Future<void> resolve(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      state = const AsyncValue.data(null);
      return;
    }
    state = const AsyncValue.loading();
    final next = await AsyncValue.guard(
      () => ref.read(makerworldRepositoryProvider).resolve(trimmed),
    );
    if (!ref.mounted) return;
    state = next;
  }

  /// Clears resolved model (e.g. after import/URL change).
  void clear() => state = const AsyncValue.data(null);
}
