import 'dart:async';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/features/dashboard/controls_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

ProviderContainer _container(RecordingCommands fake) {
  final c = ProviderContainer(
    overrides: [
      fakeServerProfileOverride(),
      printerCommandsRepositoryProvider.overrideWithValue(fake),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test(
    'setLight: optimistically sets state and "in-flight", then success',
    () async {
      final fake = RecordingCommands()..gate = Completer<void>();
      final c = _container(fake);
      final notifier = c.read(controlsProvider.notifier);

      final future = notifier.setLight(1, on: true);
      await Future<void>.delayed(Duration.zero); // enter _run up to the gate

      final midFlight = c.read(controlsProvider).pendingFor(1);
      expect(midFlight.light, true, reason: 'optimistic overwrite right away');
      expect(midFlight.isBusy(ControlAction.light), true);

      fake.gate!.complete();
      final result = await future;

      expect(result.isOk, isTrue);
      final after = c.read(controlsProvider).pendingFor(1);
      expect(
        after.isBusy(ControlAction.light),
        false,
        reason: '"in-flight" cleared',
      );
      expect(after.light, true, reason: 'overwrite stays (sticky) for a while');
      expect(fake.calls, ['light:1:true']);
    },
  );

  test('error → rollback: overwrite disappears, no forbidden block', () async {
    final fake = RecordingCommands()
      ..error = const ApiException(AppErrorCode.badResponse);
    final c = _container(fake);

    final result = await c.read(controlsProvider.notifier).setSpeed(1, 3);

    expect(result.isOk, isFalse);
    expect(result.isForbidden, isFalse);
    final st = c.read(controlsProvider);
    expect(st.pendingFor(1).speedLevel, isNull, reason: 'overwrite rollback');
    expect(st.pendingFor(1).isBusy(ControlAction.speed), false);
    expect(st.isRefused(ControlPermission.control), false);
  });

  test('an unexpected failure still unlocks and rolls back', () async {
    final fake = RecordingCommands()..error = StateError('bug');
    final c = _container(fake);

    await expectLater(
      c.read(controlsProvider.notifier).setSpeed(1, 3),
      throwsStateError,
    );

    final pending = c.read(controlsProvider).pendingFor(1);
    expect(pending.speedLevel, isNull);
    expect(pending.isBusy(ControlAction.speed), isFalse);
  });

  test('403 → refusal and a sticky control block', () async {
    final fake = RecordingCommands()
      ..error = const AuthException(AppErrorCode.forbidden);
    final c = _container(fake);

    final result = await c.read(controlsProvider.notifier).pause(1);

    expect(result.isForbidden, isTrue);
    expect(c.read(controlsProvider).isRefused(ControlPermission.control), true);
    // Lifecycle has no overwrite, but "in-flight" must be cleared.
    expect(
      c.read(controlsProvider).pendingFor(1).isBusy(ControlAction.pause),
      false,
    );
  });

  test(
    'rollback is surgical: one action\'s error does not wipe out another',
    () async {
      final fake = RecordingCommands();
      final c = _container(fake);
      final notifier = c.read(controlsProvider.notifier);

      // First a successful light (sticky), then a speed that will fail.
      await notifier.setLight(1, on: true);
      fake.error = const ApiException(AppErrorCode.badResponse);
      await notifier.setSpeed(1, 4);

      final st = c.read(controlsProvider).pendingFor(1);
      expect(st.light, true, reason: 'sticky light survives the speed error');
      expect(st.speedLevel, isNull, reason: 'speed rolled back');
    },
  );

  test('an RFID refusal leaves the rest of the controls alone', () async {
    // The re-read has a permission of its own, so its 403 says nothing about
    // whether this key may drive the printer.
    final fake = RecordingCommands()
      ..error = const AuthException(AppErrorCode.forbidden);
    final c = _container(fake);

    final result = await c
        .read(controlsProvider.notifier)
        .refreshAmsSlot(1, amsId: 0, slotId: 2);

    expect(result.isForbidden, isTrue);
    final st = c.read(controlsProvider);
    expect(
      st.isRefused(ControlPermission.amsRfid),
      true,
      reason: 'the tag re-read itself stops being offered',
    );
    expect(
      st.isRefused(ControlPermission.control),
      false,
      reason: 'every other control is behind a different gate',
    );
    expect(st.pendingFor(1).isBusy(ControlAction.ams), false);
  });

  test('load and unload share one in-flight marker for the printer', () async {
    final fake = RecordingCommands()..gate = Completer<void>();
    final c = _container(fake);
    final notifier = c.read(controlsProvider.notifier);

    final loading = notifier.amsLoad(1, 6);
    await Future<void>.delayed(Duration.zero);
    expect(
      c.read(controlsProvider).pendingFor(1).isBusy(ControlAction.ams),
      true,
      reason: 'the whole slot sheet locks, not one button',
    );

    fake.gate!.complete();
    await loading;
    expect(
      c.read(controlsProvider).pendingFor(1).isBusy(ControlAction.ams),
      false,
    );
    expect(fake.calls, ['amsLoad:1:6:-']);
  });

  test(
    'after success the optimistic overwrite disappears after optimisticHold',
    () {
      fakeAsync((async) {
        final fake = RecordingCommands();
        final c = _container(fake);
        final notifier = c.read(controlsProvider.notifier);

        notifier.setLight(2, on: true);
        async.flushMicrotasks(); // resolve the repo future + success handling

        expect(c.read(controlsProvider).pendingFor(2).light, true);

        async.elapse(
          ControlsNotifier.optimisticHold + const Duration(seconds: 1),
        );
        expect(
          c.read(controlsProvider).pendingFor(2).light,
          isNull,
          reason: 'overwrite swept away after the timer',
        );
      });
    },
  );
}
