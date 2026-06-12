import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../data/printer_commands_repository.dart';
import '../../providers.dart';

/// Akcje sterowania — klucz do oznaczania, co jest „w locie" (spinner +
/// blokada konkretnego przycisku).
enum ControlAction { pause, resume, stop, light, speed }

/// Wynik komendy zwracany do widżetu, który zainicjował akcję — to on
/// pokazuje SnackBar (notifier nie ma [BuildContext]).
enum ControlResult { ok, forbidden, error }

/// Optymistyczne nadpisania i stan „w locie" dla jednej drukarki.
/// Nadpisania ([light]/[speedLevel]) UI nakłada na żywy status, więc tapnięcie
/// daje natychmiastowy efekt; po sukcesie znikają, gdy dogoni je realny status
/// (timer bezpieczeństwa), po błędzie — natychmiast (rollback).
class PendingControls {
  const PendingControls({
    this.light,
    this.speedLevel,
    this.inFlight = const {},
  });

  /// Optymistyczny stan światła komory (null = brak nadpisania → bierz z status).
  final bool? light;

  /// Optymistyczny poziom prędkości 1–4 (null = brak nadpisania).
  final int? speedLevel;

  /// Akcje aktualnie wysyłane do serwera.
  final Set<ControlAction> inFlight;

  bool isBusy(ControlAction a) => inFlight.contains(a);

  bool get isEmpty =>
      light == null && speedLevel == null && inFlight.isEmpty;

  PendingControls setLight(bool? v) =>
      PendingControls(light: v, speedLevel: speedLevel, inFlight: inFlight);

  PendingControls setSpeed(int? v) =>
      PendingControls(light: light, speedLevel: v, inFlight: inFlight);

  PendingControls setInFlight(Set<ControlAction> v) =>
      PendingControls(light: light, speedLevel: speedLevel, inFlight: v);
}

class ControlsState {
  const ControlsState({this.pending = const {}, this.forbidden = false});

  final Map<int, PendingControls> pending;

  /// Lepkie: którakolwiek komenda zwróciła 403 (klucz bez
  /// `can_control_printer`) → blokujemy sterowanie do zmiany profilu.
  final bool forbidden;

  PendingControls pendingFor(int id) =>
      pending[id] ?? const PendingControls();

  ControlsState copyWith({Map<int, PendingControls>? pending, bool? forbidden}) =>
      ControlsState(
        pending: pending ?? this.pending,
        forbidden: forbidden ?? this.forbidden,
      );
}

final controlsProvider =
    NotifierProvider<ControlsNotifier, ControlsState>(ControlsNotifier.new);

/// Wysyła komendy sterujące i trzyma optymistyczny stan UI. Bez nawigacji i
/// SnackBarów — zwraca [ControlResult], a widżet decyduje co pokazać.
class ControlsNotifier extends Notifier<ControlsState> {
  /// Ile trzymać optymistyczne nadpisanie po sukcesie, zanim je porzucimy
  /// (do tego czasu realny status z WS/pollingu powinien już dogonić zmianę —
  /// bez tego chip mrugnąłby na starą wartość na ~sekundę).
  static const optimisticHold = Duration(seconds: 8);

  final Map<String, Timer> _clearTimers = {};

  @override
  ControlsState build() {
    // Zmiana profilu serwera → świeży stan i porzucone timery (inny klucz API
    // może mieć inne uprawnienia, więc i lepka blokada `forbidden` znika).
    ref.watch(serverProfileProvider);
    _cancelTimers();
    ref.onDispose(_cancelTimers);
    return const ControlsState();
  }

  PrinterCommandsRepository get _repo =>
      ref.read(printerCommandsRepositoryProvider);

  Future<ControlResult> pause(int id) =>
      _run(id, ControlAction.pause, () => _repo.pause(id));

  Future<ControlResult> resume(int id) =>
      _run(id, ControlAction.resume, () => _repo.resume(id));

  Future<ControlResult> stop(int id) =>
      _run(id, ControlAction.stop, () => _repo.stop(id));

  Future<ControlResult> setLight(int id, {required bool on}) => _run(
        id,
        ControlAction.light,
        () => _repo.setChamberLight(id, on: on),
        optimistic: 'light',
        applyLight: on,
      );

  Future<ControlResult> setSpeed(int id, int mode) => _run(
        id,
        ControlAction.speed,
        () => _repo.setPrintSpeed(id, mode),
        optimistic: 'speed',
        applySpeed: mode,
      );

  Future<ControlResult> _run(
    int id,
    ControlAction action,
    Future<void> Function() send, {
    String? optimistic,
    bool? applyLight,
    int? applySpeed,
  }) async {
    final before = state.pendingFor(id);

    // Optymistycznie: oznacz „w locie" i nałóż nadpisanie (jeśli akcja je ma).
    var next = before.setInFlight({...before.inFlight, action});
    if (optimistic == 'light') next = next.setLight(applyLight);
    if (optimistic == 'speed') next = next.setSpeed(applySpeed);
    _setPending(id, next);

    try {
      await send();
      // Sukces: zdejmij „w locie", nadpisanie zostaw i zaplanuj jego sprzątnięcie.
      _setPending(id, _withoutInFlight(state.pendingFor(id), action));
      if (optimistic != null) _scheduleClear(id, optimistic);
      return ControlResult.ok;
    } on AppApiException catch (e) {
      // Rollback: zdejmij „w locie" i przywróć nadpisanie do stanu sprzed akcji
      // (chirurgicznie — żeby nie skasować równoległej, innej akcji).
      var rolled = _withoutInFlight(state.pendingFor(id), action);
      if (optimistic == 'light') rolled = rolled.setLight(before.light);
      if (optimistic == 'speed') rolled = rolled.setSpeed(before.speedLevel);
      _setPending(id, rolled);

      if (e is AuthException && e.code == AppErrorCode.forbidden) {
        state = state.copyWith(forbidden: true);
        return ControlResult.forbidden;
      }
      return ControlResult.error;
    }
  }

  PendingControls _withoutInFlight(PendingControls p, ControlAction a) =>
      p.setInFlight({...p.inFlight}..remove(a));

  void _setPending(int id, PendingControls p) {
    final m = {...state.pending};
    if (p.isEmpty) {
      m.remove(id);
    } else {
      m[id] = p;
    }
    state = state.copyWith(pending: m);
  }

  void _scheduleClear(int id, String field) {
    final key = '$id:$field';
    _clearTimers[key]?.cancel();
    _clearTimers[key] = Timer(optimisticHold, () {
      _clearTimers.remove(key);
      final cur = state.pending[id];
      if (cur == null) return;
      _setPending(id, field == 'light' ? cur.setLight(null) : cur.setSpeed(null));
    });
  }

  void _cancelTimers() {
    for (final t in _clearTimers.values) {
      t.cancel();
    }
    _clearTimers.clear();
  }
}
