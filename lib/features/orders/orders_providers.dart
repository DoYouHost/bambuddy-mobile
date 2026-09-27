import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/print_batch.dart';
import '../../providers.dart';

/// Whether the server lists batches to this session. Unknown reads as yes: the
/// route is older than the servers this app mostly meets, and the list's own
/// 404 or 403 is what takes the entry away.
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
