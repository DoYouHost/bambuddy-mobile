import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/print_batch.dart';
import '../../core/models/project.dart';
import '../../providers.dart';

/// Whether the server lists batches to this session — the entry to the orders
/// screen.
final batchListingProvider = capabilityGate(
  (ref) => ref.watch(batchRepositoryProvider).listCapability,
);

/// Whether batches can be orders here — targets, editing, dispatch (#342).
final batchOrdersProvider = capabilityGate(
  (ref) => ref.watch(batchRepositoryProvider).ordersCapability,
);

/// Batches with [status], newest first; null lists every status.
final batchesProvider = FutureProvider.autoDispose
    .family<List<PrintBatch>, PrintBatchStatus?>((ref, status) {
      // Mid server-change there is no client to ask.
      if (ref.watch(serverProfileProvider) == null) return const [];
      return ref.watch(batchRepositoryProvider).list(status: status);
    });

/// One batch, fresh — the edit form seeds from it.
final batchDetailProvider = FutureProvider.autoDispose.family<PrintBatch, int>(
  (ref, id) => ref.watch(batchRepositoryProvider).get(id),
);

/// Projects an order can be filed under. Empty when the list is refused: the
/// field is then left out rather than failing the form.
final orderProjectsProvider =
    FutureProvider.autoDispose<List<ProjectListResponse>>((ref) async {
      try {
        return await ref.watch(projectsRepositoryProvider).list();
      } on AppApiException {
        return const [];
      }
    });

/// Batches with a write in flight, app-wide rather than per card: a filter
/// switch or a reopened screen builds a new card, and a second dispatch sent
/// before the first commits counts the same owed runs — and queues them twice.
/// The edit form takes its batch too, so nothing races its save.
final ordersInFlightProvider = StateProvider<Set<int>>((_) => const {});

/// Grouping by hand and ungrouping (v0.2.4.8).
final batchGroupingProvider = capabilityGate(
  (ref) => ref.watch(batchRepositoryProvider).groupingCapability,
);
