import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/makerworld.dart';
import '../../providers.dart';

/// Stan akcji „rozwiąż URL" na ekranie MakerWorld. `null` (dane) = nic jeszcze
/// nie rozwiązano (stan startowy); loading w trakcie żądania; error z wyjątkiem.
final makerworldResolveProvider = AutoDisposeAsyncNotifierProvider<
    MakerWorldResolveNotifier, MakerWorldResolvedModel?>(
  MakerWorldResolveNotifier.new,
);

class MakerWorldResolveNotifier
    extends AutoDisposeAsyncNotifier<MakerWorldResolvedModel?> {
  @override
  Future<MakerWorldResolvedModel?> build() async => null;

  /// Rozwiązuje [url]; pusty URL czyści wynik. Wynik trafia do [state].
  Future<void> resolve(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      state = const AsyncValue.data(null);
      return;
    }
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(makerworldRepositoryProvider).resolve(trimmed),
    );
  }

  /// Czyści rozwiązany model (np. po imporcie/zmianie URL-a).
  void clear() => state = const AsyncValue.data(null);
}
