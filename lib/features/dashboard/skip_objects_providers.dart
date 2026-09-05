import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/action_outcome.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/models/printable_object.dart';
import '../../providers.dart';
import 'object_pick_mask.dart';
import 'ws_providers.dart';

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

  /// Skip one or more objects in a single request, then refresh so their
  /// `skipped` flags reflect immediately.
  Future<ActionOutcome> skip(List<int> objectIds) => runAction(
        () => ref.read(skipObjectsRepositoryProvider).skip(arg, objectIds),
        logId: 'skip_objects.skip',
        onSuccess: _poll,
      );
}

/// The current print's object-ID mask, decoded once per job. Null whenever the
/// plate has to fall back to positional badges: nothing printing, a server or
/// 3MF without the `pick` view, or a fetch that failed — none of which is worth
/// an error on a screen that still works without it.
///
/// Re-runs when the job changes, since the mask describes one plate only.
final objectPickMaskProvider =
    FutureProvider.autoDispose.family<ObjectPickMask?, int>(
        (ref, printerId) async {
  final coverUrl =
      ref.watch(printerStatusesProvider.select((m) => m[printerId]?.coverUrl));
  // Watched narrowly on purpose: a status frame lands every second or two, and
  // the mask only ever changes with the job behind it.
  ref.watch(printerStatusesProvider.select((m) {
    final status = m[printerId];
    return status?.gcodeFile ?? status?.currentPrint;
  }));
  if (coverUrl == null) return null;

  final repo = ref.read(skipObjectsRepositoryProvider);
  final tokens = ref.read(cameraTokenServiceProvider);
  Future<Uint8List?> load({bool freshToken = false}) async =>
      repo.fetchPickMask(printerId, await tokens.token(forceRefresh: freshToken));

  try {
    Uint8List? png;
    try {
      png = await load();
    } on AuthException catch (e) {
      // Same recovery as CameraTokenImageRecovery does for <img>-style loads:
      // an expired token is indistinguishable from a broken one until a fresh
      // one is tried.
      if (e.code != AppErrorCode.unauthorized) rethrow;
      png = await load(freshToken: true);
    }
    return png == null ? null : await ObjectPickMask.decode(png);
  } on Object {
    return null;
  }
});
