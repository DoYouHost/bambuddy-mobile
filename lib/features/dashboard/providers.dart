import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../data/printers_repository.dart';
import '../../providers.dart';

const pollInterval = Duration(seconds: 5);

class DashboardState {
  const DashboardState({
    this.printers,
    this.error,
    this.authExpired = false,
  });

  /// Ostatnie dobrze pobrane dane — zostają widoczne, gdy kolejny
  /// poll padnie (baner zamiast pustego ekranu).
  final List<PrinterWithStatus>? printers;

  /// Błąd ostatniego pollingu (null = ostatni poll OK).
  final String? error;

  /// Sesja/klucz odrzucone i nieodnowialne — UI odsyła do /setup.
  final bool authExpired;

  bool get loading => printers == null && error == null;
  bool get stale => printers != null && error != null;
}

final dashboardProvider =
    AutoDisposeNotifierProvider<DashboardNotifier, DashboardState>(
  DashboardNotifier.new,
);

/// Polling REST co 5 s. Ten wzorzec zostaje po M2 jako backfill po
/// wznowieniu aplikacji i fallback przy padzie WebSocketa.
class DashboardNotifier extends AutoDisposeNotifier<DashboardState> {
  Timer? _timer;
  int _generation = 0;

  @override
  DashboardState build() {
    // Przebudowa przy zmianie profilu/klienta (np. zmiana serwera).
    ref.watch(printersRepositoryProvider);
    final generation = ++_generation;
    _timer?.cancel();
    _timer = Timer.periodic(pollInterval, (_) => _poll(generation));
    ref.onDispose(() => _timer?.cancel());
    Future.microtask(() => _poll(generation));
    return const DashboardState();
  }

  Future<void> refresh() => _poll(_generation);

  Future<void> _poll(int generation) async {
    final repo = ref.read(printersRepositoryProvider);
    try {
      final data = await repo.fetchAll();
      if (generation != _generation) return; // wynik z poprzedniego życia
      state = DashboardState(printers: data);
    } on AuthException {
      if (generation != _generation) return;
      _timer?.cancel();
      state = DashboardState(printers: state.printers, authExpired: true);
    } on AppApiException catch (e) {
      if (generation != _generation) return;
      state = DashboardState(printers: state.printers, error: e.message);
    }
  }
}
