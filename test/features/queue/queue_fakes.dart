import 'package:bambuddy_mobile/core/api/action_outcome.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A queue a test drives instead of a server: a list it can change under the
/// screen, and a record of every write the screen asked for. Nothing it is
/// asked reaches the network.
class FakeQueue extends QueueNotifier {
  FakeQueue([this._items = const []]);

  List<QueueItem> _items;

  /// Jobs started on a printer: assigned to it, mapped, then started.
  final List<({int item, int printer})> started = [];

  /// Jobs started straight through `/start`, with no assignment or mapping.
  final List<int> startedAsIs = [];

  final List<int> stopped = [];
  final List<int> cancelled = [];
  final List<int> deleted = [];

  /// What `/stop` comes back with, when a test wants it refused.
  AppApiException? stopFailure;

  @override
  Future<List<QueueItem>> build() async => _items;

  /// The queue as a refresh would bring it.
  void replace(List<QueueItem> items) {
    _items = items;
    state = AsyncData(items);
  }

  @override
  Future<ActionOutcome> start(int itemId) async {
    startedAsIs.add(itemId);
    return ActionOutcome.ok;
  }

  @override
  Future<ActionOutcome> startOnPrinter(
    QueueItem item,
    int printerId, {
    List<int>? amsMapping,
  }) async {
    started.add((item: item.id, printer: printerId));
    return ActionOutcome.ok;
  }

  @override
  Future<ActionOutcome> stop(int itemId) async {
    stopped.add(itemId);
    final failure = stopFailure;
    return failure == null ? ActionOutcome.ok : ActionOutcome.failed(failure);
  }

  @override
  Future<ActionOutcome> cancel(int itemId) async {
    cancelled.add(itemId);
    return ActionOutcome.ok;
  }

  @override
  Future<ActionOutcome> delete(int itemId, {String logId = ''}) async {
    deleted.add(itemId);
    return ActionOutcome.ok;
  }
}
