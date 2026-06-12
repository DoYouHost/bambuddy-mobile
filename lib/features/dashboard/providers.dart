import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/api/ws_client.dart';
import '../../data/printers_repository.dart';
import '../../providers.dart';
import 'ws_providers.dart';

/// Szybki polling — fallback, gdy WS nie jest połączony (świeżość statusów).
const pollInterval = Duration(seconds: 5);

/// Wolny polling przy WS `connected` — WS niesie świeżość statusów, REST
/// dociąga już tylko skład drukarek (roster), który zmienia się rzadko.
const slowPollInterval = Duration(seconds: 60);

class DashboardState {
  const DashboardState({
    this.printers,
    this.error,
    this.authExpired = false,
  });

  /// Ostatnie dobrze pobrane dane — zostają widoczne, gdy kolejny
  /// poll padnie (baner zamiast pustego ekranu).
  final List<PrinterWithStatus>? printers;

  /// Błąd ostatniego pollingu (null = ostatni poll OK); tłumaczony w UI.
  final AppApiException? error;

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

    // Tempo pollingu zależy od WS: connected → wolno (60 s, tylko roster),
    // w innym razie → szybko (5 s, fallback). Reagujemy przez ref.listen, a
    // NIE watch — inaczej każdy flap WS przebudowałby notifier i zresetował
    // listę do spinnera. Stan zostaje, zmienia się tylko interwał timera.
    ref.listen(
      wsConnectionStateProvider
          .select((s) => s.valueOrNull == WsConnectionState.connected),
      (_, connected) => _retune(connected: connected, generation: generation),
    );

    _arm(connected: _wsConnectedNow(), generation: generation);
    ref.onDispose(() => _timer?.cancel());
    Future.microtask(() => _poll(generation));
    return const DashboardState();
  }

  bool _wsConnectedNow() =>
      ref.read(wsConnectionStateProvider).valueOrNull ==
      WsConnectionState.connected;

  void _arm({required bool connected, required int generation}) {
    _timer?.cancel();
    final interval = connected ? slowPollInterval : pollInterval;
    _timer = Timer.periodic(interval, (_) => _poll(generation));
  }

  /// Zmiana stanu WS: przy utracie połączenia natychmiast dociągnij REST
  /// (fallback wskakuje od razu) i przyspiesz; przy odzyskaniu zwolnij.
  void _retune({required bool connected, required int generation}) {
    if (generation != _generation) return;
    _arm(connected: connected, generation: generation);
    if (!connected) _poll(generation);
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
      state = DashboardState(printers: state.printers, error: e);
    }
  }
}
