import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/action_outcome.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/models/printable_object.dart';
import '../../providers.dart';

/// Refresh cadence while the skip screen is open. Objects flip to `skipped`
/// server-side (and the printer may finish/skip on its own), so poll to keep the
/// list live — mirrors the web client's 5 s interval.
const skipObjectsPollInterval = Duration(seconds: 5);

/// Printable objects for one printer, kept fresh while the skip screen is open.
/// Auto-disposes when the screen closes (timer cancelled with it).
final skipObjectsProvider = AutoDisposeAsyncNotifierProviderFamily<
    SkipObjectsNotifier, PrintableObjects, int>(SkipObjectsNotifier.new);

class SkipObjectsNotifier
    extends AutoDisposeFamilyAsyncNotifier<PrintableObjects, int> {
  Timer? _timer;

  @override
  Future<PrintableObjects> build(int arg) async {
    ref.watch(serverProfileProvider);
    _timer = Timer.periodic(skipObjectsPollInterval, (_) => _poll());
    ref.onDispose(() => _timer?.cancel());
    return ref.read(skipObjectsRepositoryProvider).fetchObjects(arg);
  }

  /// Silent background refresh — keep the last good list on a transient failure
  /// so a dropped poll doesn't blank the screen mid-print.
  Future<void> _poll() async {
    try {
      final data =
          await ref.read(skipObjectsRepositoryProvider).fetchObjects(arg);
      state = AsyncData(data);
    } on Object {
      // Ignore: next tick retries.
    }
  }

  /// Manual refresh (pull-to-refresh / after a skip). [reload] re-reads objects
  /// from the 3MF, used when the list is empty after a restart.
  Future<void> refresh({bool reload = false}) async {
    state = await AsyncValue.guard(
      () => ref.read(skipObjectsRepositoryProvider).fetchObjects(arg, reload: reload),
    );
  }

  /// Skip one object, then refresh so its `skipped` flag reflects immediately.
  Future<ActionOutcome> skip(int objectId) async {
    try {
      await ref.read(skipObjectsRepositoryProvider).skip(arg, [objectId]);
      await _poll();
      return ActionOutcome.ok;
    } on AppApiException catch (e) {
      return ActionOutcome.failed(e, action: 'printer.skip_object');
    }
  }
}
