import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/smart_plug.dart';
import '../../data/smart_plugs_repository.dart';
import '../../providers.dart';
import 'controls_providers.dart' show ControlResult;

/// Tempo odpytywania gniazdek. Status leci tylko REST (nie WS), więc trzymamy
/// własny, stały interwał — niezależny od tego, czy WS drukarek żyje.
const smartPlugPollInterval = Duration(seconds: 5);

/// Migawka gniazdek dla dashboardu: konfiguracja (z przypisaniem do drukarek),
/// żywe statusy (moc/stan) oraz stan optymistyczny/`w locie` sterowania.
class SmartPlugsState {
  const SmartPlugsState({
    this.plugs = const [],
    this.statuses = const {},
    this.optimistic = const {},
    this.inFlight = const {},
    this.forbidden = false,
  });

  /// Konfiguracja wszystkich gniazdek (każde niesie `printerId`).
  final List<SmartPlug> plugs;

  /// Żywy status per `plugId` (null-wpis = nieosiągalne/padło).
  final Map<int, SmartPlugStatus> statuses;

  /// Optymistyczne nadpisanie stanu on/off per `plugId` — natychmiastowy efekt
  /// tapnięcia, zanim dogoni je realny status (potem sprzątane).
  final Map<int, bool> optimistic;

  /// Gniazdka z komendą aktualnie w locie (spinner + blokada przełącznika).
  final Set<int> inFlight;

  /// Lepkie: komenda zwróciła 403 (klucz bez uprawnień) → blokujemy sterowanie.
  final bool forbidden;

  /// Gniazdko do pokazania na karcie danej drukarki: przypisane, włączone i
  /// oznaczone do wyświetlenia. Pierwsze pasujące (zwykle jest jedno).
  SmartPlug? plugForPrinterCard(int printerId) {
    for (final p in plugs) {
      if (p.printerId == printerId && p.visibleOnCard) return p;
    }
    return null;
  }

  SmartPlugStatus? statusFor(int plugId) => statuses[plugId];

  bool isBusy(int plugId) => inFlight.contains(plugId);

  /// Efektywny stan on/off: optymistyczne nadpisanie ma pierwszeństwo nad
  /// statusem, ten nad ostatnim znanym z konfiguracji.
  bool? effectiveOn(SmartPlug plug) =>
      optimistic[plug.id] ?? statusFor(plug.id)?.isOn ?? plug.lastIsOn;

  /// Suma mocy czynnej [W] po wszystkich osiągalnych gniazdkach (cała farma).
  double get totalPowerW {
    var sum = 0.0;
    for (final s in statuses.values) {
      sum += s.powerW ?? 0;
    }
    return sum;
  }

  /// Czy jest cokolwiek do pokazania w kontekście mocy (≥1 gniazdko w ogóle).
  bool get hasAnyPlug => plugs.isNotEmpty;

  SmartPlugsState copyWith({
    List<SmartPlug>? plugs,
    Map<int, SmartPlugStatus>? statuses,
    Map<int, bool>? optimistic,
    Set<int>? inFlight,
    bool? forbidden,
  }) =>
      SmartPlugsState(
        plugs: plugs ?? this.plugs,
        statuses: statuses ?? this.statuses,
        optimistic: optimistic ?? this.optimistic,
        inFlight: inFlight ?? this.inFlight,
        forbidden: forbidden ?? this.forbidden,
      );
}

final smartPlugsProvider =
    AutoDisposeNotifierProvider<SmartPlugsNotifier, SmartPlugsState>(
  SmartPlugsNotifier.new,
);

/// Pobiera listę gniazdek i odpytuje ich status w pętli (5 s), a także wysyła
/// komendy on/off z optymistycznym nadpisaniem i rollbackiem (wzorzec jak
/// [ControlsNotifier]). Auto-dispose: żyje tylko gdy dashboard go obserwuje.
class SmartPlugsNotifier extends AutoDisposeNotifier<SmartPlugsState> {
  Timer? _timer;
  int _generation = 0;

  /// Ile trzymać optymistyczne nadpisanie po sukcesie, zanim je porzucimy
  /// (realny status zdąży dogonić zmianę — inaczej przełącznik mrugnąłby wstecz).
  static const _optimisticHold = Duration(seconds: 8);
  final Map<int, Timer> _clearTimers = {};

  @override
  SmartPlugsState build() {
    // Przebudowa przy zmianie profilu (inny serwer/klucz → inne gniazdka,
    // a lepka blokada `forbidden` znika).
    ref.watch(serverProfileProvider);
    ref.watch(smartPlugsRepositoryProvider);
    final generation = ++_generation;

    _arm(generation);
    ref.onDispose(() {
      _timer?.cancel();
      for (final t in _clearTimers.values) {
        t.cancel();
      }
      _clearTimers.clear();
    });
    Future.microtask(() => _poll(generation));
    return const SmartPlugsState();
  }

  void _arm(int generation) {
    _timer?.cancel();
    _timer =
        Timer.periodic(smartPlugPollInterval, (_) => _poll(generation));
  }

  /// Tło → cisza (FGS nie potrzebuje danych gniazdek; nie bijemy po serwerze).
  void pausePolling() {
    _timer?.cancel();
    _timer = null;
  }

  /// Powrót z tła → wznów pętlę i natychmiast dociągnij stan.
  void resumePolling() {
    _arm(_generation);
    _poll(_generation);
  }

  Future<void> refresh() => _poll(_generation);

  Future<void> _poll(int generation) async {
    final repo = ref.read(smartPlugsRepositoryProvider);
    final List<SmartPlug> plugs;
    try {
      plugs = await repo.fetchPlugs();
    } on AuthException {
      return; // dashboardProvider już odeśle do /setup
    } on AppApiException {
      return; // przejściowy błąd sieci — zostawiamy ostatnie dane
    }
    if (generation != _generation) return;

    // Status odpytujemy dla włączonych gniazdek (moc do sumy całej farmy),
    // równolegle. Nieosiągalne zwracają null → pomijamy w mapie. [fetchStatus]
    // rethrowuje AuthException (per-endpoint 401/403, gdy lista przeszła) — łapiemy
    // ją tu, bo dashboardProvider i tak odeśle do /setup; bez tego byłby to
    // nieobsłużony async error w ticku Timera.
    final enabled = plugs.where((p) => p.enabled ?? true).toList();
    final List<SmartPlugStatus?> results;
    try {
      results = await Future.wait(enabled.map((p) => repo.fetchStatus(p.id)));
    } on AppApiException {
      return;
    }
    if (generation != _generation) return;

    final statuses = <int, SmartPlugStatus>{};
    for (var i = 0; i < enabled.length; i++) {
      final s = results[i];
      if (s != null) statuses[enabled[i].id] = s;
    }
    state = state.copyWith(plugs: plugs, statuses: statuses);
  }

  /// Przełącza gniazdko (on/off/toggle) z optymistycznym nadpisaniem.
  /// Zwraca [ControlResult] — widżet decyduje, co pokazać.
  Future<ControlResult> control(int plugId, SmartPlugAction action) async {
    final plug = state.plugs.firstWhere(
      (p) => p.id == plugId,
      orElse: () => SmartPlug(id: plugId),
    );
    final desiredOn = switch (action) {
      SmartPlugAction.on => true,
      SmartPlugAction.off => false,
      SmartPlugAction.toggle => !(state.effectiveOn(plug) ?? false),
    };

    final before = state.optimistic[plugId];
    state = state.copyWith(
      optimistic: {...state.optimistic, plugId: desiredOn},
      inFlight: {...state.inFlight, plugId},
    );

    try {
      await ref.read(smartPlugsRepositoryProvider).control(plugId, action);
      _clearInFlight(plugId);
      _scheduleClearOptimistic(plugId);
      unawaited(_poll(_generation)); // dociągnij realny stan + moc
      return ControlResult.ok;
    } on AppApiException catch (e) {
      // Rollback nadpisania do stanu sprzed akcji.
      final opt = {...state.optimistic};
      if (before == null) {
        opt.remove(plugId);
      } else {
        opt[plugId] = before;
      }
      state = state.copyWith(
        optimistic: opt,
        inFlight: {...state.inFlight}..remove(plugId),
      );
      if (e is AuthException && e.code == AppErrorCode.forbidden) {
        state = state.copyWith(forbidden: true);
        return ControlResult.forbidden;
      }
      return ControlResult.error;
    }
  }

  void _clearInFlight(int plugId) {
    state = state.copyWith(inFlight: {...state.inFlight}..remove(plugId));
  }

  void _scheduleClearOptimistic(int plugId) {
    _clearTimers[plugId]?.cancel();
    _clearTimers[plugId] = Timer(_optimisticHold, () {
      _clearTimers.remove(plugId);
      if (!state.optimistic.containsKey(plugId)) return;
      state = state.copyWith(
        optimistic: {...state.optimistic}..remove(plugId),
      );
    });
  }
}
