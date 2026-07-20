import 'dart:async';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/data/printer_commands_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/controls_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Profil bez auth — `controlsProvider.build` tylko go obserwuje (reset przy
/// zmianie), więc wartość jest nieistotna, ale provider musi się zbudować.
class _FakeProfileNotifier extends ServerProfileNotifier {
  @override
  ServerProfile? build() =>
      const ServerProfile(baseUrl: 'http://s.local:8000', authMode: AuthMode.none);
}

/// Atrapa repozytorium komend: zapisuje wywołania, opcjonalnie czeka na bramkę
/// i/lub rzuca skonfigurowany wyjątek.
class _FakeCommands implements PrinterCommandsRepository {
  final List<String> calls = [];
  Object? error;
  Completer<void>? gate;

  Future<void> _do(String tag) async {
    calls.add(tag);
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
  }

  @override
  Future<void> pause(int id) => _do('pause:$id');
  @override
  Future<void> resume(int id) => _do('resume:$id');
  @override
  Future<void> stop(int id) => _do('stop:$id');
  @override
  Future<void> clearPlate(int id) => _do('clearPlate:$id');
  @override
  Future<void> setChamberLight(int id, {required bool on}) =>
      _do('light:$id:$on');
  @override
  Future<void> setPrintSpeed(int id, int mode) => _do('speed:$id:$mode');
  @override
  Future<void> setNozzleTemperature(int id, int target, {int nozzle = 0}) =>
      _do('nozzle:$id:$target:$nozzle');
  @override
  Future<void> setBedTemperature(int id, int target) => _do('bed:$id:$target');
  @override
  Future<void> setChamberTemperature(int id, int target) =>
      _do('chamber:$id:$target');
  @override
  Future<void> setAirductMode(int id, {required bool heating}) =>
      _do('airduct:$id:$heating');
  @override
  Future<void> setFanSpeed(int id, String fan, int speed) =>
      _do('fan:$id:$fan:$speed');
  @override
  Future<void> selectExtruder(int id, int extruder) =>
      _do('extruder:$id:$extruder');
  @override
  Future<void> startDrying(int id,
          {required int amsId,
          required int temp,
          required int duration,
          String filament = ''}) =>
      _do('dryStart:$id:$amsId:$temp:$duration:$filament');
  @override
  Future<void> stopDrying(int id, {required int amsId}) =>
      _do('dryStop:$id:$amsId');
  @override
  Future<void> bedJog(int id, double distance, {bool force = false}) =>
      _do('bedJog:$id:$distance:$force');
  @override
  Future<void> xyJog(int id, {double x = 0, double y = 0}) =>
      _do('xyJog:$id:$x:$y');
  @override
  Future<void> extruderJog(int id, double distance) =>
      _do('extruderJog:$id:$distance');
  @override
  Future<void> homeAxes(int id) => _do('homeAxes:$id');
}

ProviderContainer _container(_FakeCommands fake) {
  final c = ProviderContainer(
    overrides: [
      serverProfileProvider.overrideWith(_FakeProfileNotifier.new),
      printerCommandsRepositoryProvider.overrideWithValue(fake),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('setLight: optymistycznie ustawia stan i „w locie", potem sukces',
      () async {
    final fake = _FakeCommands()..gate = Completer<void>();
    final c = _container(fake);
    final notifier = c.read(controlsProvider.notifier);

    final future = notifier.setLight(1, on: true);
    await Future<void>.delayed(Duration.zero); // wejdź w _run aż do bramki

    final midFlight = c.read(controlsProvider).pendingFor(1);
    expect(midFlight.light, true, reason: 'optymistyczne nadpisanie od razu');
    expect(midFlight.isBusy(ControlAction.light), true);

    fake.gate!.complete();
    final result = await future;

    expect(result, ControlResult.ok);
    final after = c.read(controlsProvider).pendingFor(1);
    expect(after.isBusy(ControlAction.light), false, reason: 'zdjęte „w locie"');
    expect(after.light, true, reason: 'nadpisanie zostaje (sticky) do czasu');
    expect(fake.calls, ['light:1:true']);
  });

  test('błąd → rollback: nadpisanie znika, brak blokady forbidden', () async {
    final fake = _FakeCommands()..error = const ApiException(AppErrorCode.badResponse);
    final c = _container(fake);

    final result = await c.read(controlsProvider.notifier).setSpeed(1, 3);

    expect(result, ControlResult.error);
    final st = c.read(controlsProvider);
    expect(st.pendingFor(1).speedLevel, isNull, reason: 'rollback nadpisania');
    expect(st.pendingFor(1).isBusy(ControlAction.speed), false);
    expect(st.forbidden, false);
  });

  test('403 → ControlResult.forbidden i lepka blokada sterowania', () async {
    final fake = _FakeCommands()..error = const AuthException(AppErrorCode.forbidden);
    final c = _container(fake);

    final result = await c.read(controlsProvider.notifier).pause(1);

    expect(result, ControlResult.forbidden);
    expect(c.read(controlsProvider).forbidden, true);
    // Lifecycle nie ma nadpisania, ale „w locie" musi być zdjęte.
    expect(c.read(controlsProvider).pendingFor(1).isBusy(ControlAction.pause),
        false);
  });

  test('rollback jest chirurgiczny: błąd jednej akcji nie kasuje drugiej',
      () async {
    final fake = _FakeCommands();
    final c = _container(fake);
    final notifier = c.read(controlsProvider.notifier);

    // Najpierw udane światło (sticky), potem prędkość która padnie.
    await notifier.setLight(1, on: true);
    fake.error = const ApiException(AppErrorCode.badResponse);
    await notifier.setSpeed(1, 4);

    final st = c.read(controlsProvider).pendingFor(1);
    expect(st.light, true, reason: 'sticky światło przeżywa błąd prędkości');
    expect(st.speedLevel, isNull, reason: 'prędkość wycofana');
  });

  test('po sukcesie optymistyczne nadpisanie znika po optimisticHold', () {
    fakeAsync((async) {
      final fake = _FakeCommands();
      final c = _container(fake);
      final notifier = c.read(controlsProvider.notifier);

      notifier.setLight(2, on: true);
      async.flushMicrotasks(); // rozwiąż future repo + obsługę sukcesu

      expect(c.read(controlsProvider).pendingFor(2).light, true);

      async.elapse(ControlsNotifier.optimisticHold + const Duration(seconds: 1));
      expect(c.read(controlsProvider).pendingFor(2).light, isNull,
          reason: 'nadpisanie sprzątnięte po czasie');
    });
  });
}
