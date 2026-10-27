import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/current_user.dart';
import '../../core/models/queue_item.dart';
import '../../providers.dart';
import 'queue_providers.dart';

/// Whether [item] can be picked for a bulk edit: the route changes `pending`
/// rows only and counts every other one as skipped
/// (`print_queue.py::bulk_update_queue_items`), and the web puts its checkbox on
/// the same rows.
bool queueItemSelectable(QueueItem item) =>
    item.statusKind == QueueItemStatusKind.pending;

/// The queue items picked for a bulk edit; non-empty means the screen is in
/// selection mode. Held in a provider rather than the screen's state because the
/// cards that show it are rebuilt by every poll.
final queueSelectionProvider =
    NotifierProvider.autoDispose<QueueSelectionNotifier, Set<int>>(
      QueueSelectionNotifier.new,
    );

class QueueSelectionNotifier extends Notifier<Set<int>> {
  @override
  Set<int> build() {
    // A picked item that starts printing, is removed or is cancelled elsewhere
    // leaves the selection: it could not be edited any more, and the count in
    // the bar would promise more than the edit can touch.
    ref.listen(queueProvider, (_, next) {
      final items = next.value;
      if (items == null || state.isEmpty) return;
      final live = {
        for (final item in items)
          if (queueItemSelectable(item)) item.id,
      };
      final kept = state.intersection(live);
      if (kept.length != state.length) state = kept;
    });
    return const {};
  }

  void toggle(int id) =>
      state = state.contains(id) ? ({...state}..remove(id)) : {...state, id};

  void selectAll(Iterable<int> ids) => state = {...state, ...ids};

  void clear() => state = const {};
}

/// Whether to offer picking items for a bulk edit: the web's rule for its Edit
/// Selected button, `queue:update_own` or `queue:update_all`. The route then
/// skips what the user may not change, and says how many.
final mayBulkEditQueueProvider = Provider<bool>(
  (ref) =>
      ref.watch(permissionProvider(Permissions.queueUpdateOwn)) ||
      ref.watch(permissionProvider(Permissions.queueUpdateAll)),
);
