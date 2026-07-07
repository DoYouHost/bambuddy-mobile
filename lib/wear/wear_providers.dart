import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/queue_item.dart';
import '../data/printers_repository.dart';
import '../providers.dart';

/// Fleet of printers with status, polled over REST. The watch has no WebSocket
/// or background service (deliberate — battery), so this is a plain periodic
/// poll that runs only while a screen watching it is mounted (autoDispose).
final wearFleetProvider =
    AsyncNotifierProvider.autoDispose<WearFleetNotifier, List<PrinterWithStatus>>(
  WearFleetNotifier.new,
);

class WearFleetNotifier
    extends AutoDisposeAsyncNotifier<List<PrinterWithStatus>> {
  Timer? _timer;
  bool _disposed = false;

  @override
  Future<List<PrinterWithStatus>> build() async {
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
    });
    // Silent periodic refresh — doesn't flip the UI back to a spinner each tick.
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => refresh());
    return _fetch();
  }

  Future<List<PrinterWithStatus>> _fetch() =>
      ref.read(printersRepositoryProvider).fetchAll();

  /// Re-fetch in the background; keeps the last good data visible on transient
  /// errors instead of blanking the screen.
  Future<void> refresh() async {
    final next = await AsyncValue.guard(_fetch);
    if (_disposed) return;
    // Only surface an error if we have nothing to show; otherwise keep old data.
    if (next.hasError && state.hasValue) return;
    state = next;
  }
}

/// Controller for the four watch actions. Stateless facade over the shared
/// repositories; callers manage their own in-flight/error UI.
final wearActionsProvider = Provider.autoDispose<WearActions>(
  (ref) => WearActions(ref),
);

class WearActions {
  WearActions(this._ref);

  final Ref _ref;

  Future<void> pause(int printerId) =>
      _ref.read(printerCommandsRepositoryProvider).pause(printerId);

  Future<void> resume(int printerId) =>
      _ref.read(printerCommandsRepositoryProvider).resume(printerId);

  Future<void> stop(int printerId) =>
      _ref.read(printerCommandsRepositoryProvider).stop(printerId);

  Future<void> clearPlate(int printerId) =>
      _ref.read(printerCommandsRepositoryProvider).clearPlate(printerId);

  /// Start the next pending queue item on [printerId]. Assigns the printer first
  /// if the item isn't already bound to it (server requires the printer set
  /// before start). Throws [StateError] when the queue has nothing pending.
  Future<void> startNext(int printerId) async {
    final repo = _ref.read(queueRepositoryProvider);
    final items = await repo.fetch();
    // Queue positions frequently all default to 1 (see queue notes), so sort by
    // position then id for a stable "first" pick.
    final pending = items
        .where((q) => q.statusKind == QueueItemStatusKind.pending)
        .toList()
      ..sort((a, b) {
        final byPos = a.position.compareTo(b.position);
        return byPos != 0 ? byPos : a.id.compareTo(b.id);
      });
    if (pending.isEmpty) {
      throw StateError('empty-queue');
    }
    final item = pending.first;
    if (item.printerId != printerId) {
      await repo.assignPrinter(item.id, printerId);
    }
    await repo.start(item.id);
  }
}
