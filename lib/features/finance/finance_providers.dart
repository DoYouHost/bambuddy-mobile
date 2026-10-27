import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/cost_center.dart';
import '../../core/models/wallet.dart';
import '../../providers.dart';

/// How many ledger rows a request asks for; the web's own page size.
const financePageSize = 50;

/// Every center the session may see (`GET /finance/cost-centers/mine`), those it
/// may not print with included — the list the personal view shows, where
/// [printableCostCentersProvider] keeps only what the print form can offer.
final myCostCentersProvider = FutureProvider.autoDispose<List<CostCenter>>(
  (ref) => ref.watch(financeRepositoryProvider).myCostCenters(),
);

final walletBalanceProvider = FutureProvider.autoDispose<WalletBalance>(
  (ref) => ref.watch(financeRepositoryProvider).balance(),
);

/// The ledger rows loaded so far, how many there are in all, and whether another
/// page is on its way.
@immutable
class FinanceTransactions {
  const FinanceTransactions({
    required this.items,
    required this.total,
    this.loadingMore = false,
  });

  final List<WalletTransaction> items;
  final int total;
  final bool loadingMore;

  bool get hasMore => items.length < total;
}

final financeTransactionsProvider =
    AsyncNotifierProvider<FinanceTransactionsNotifier, FinanceTransactions>(
      FinanceTransactionsNotifier.new,
    );

/// Every user's ledger — the administrator's view.
final adminTransactionsProvider =
    AsyncNotifierProvider<AdminTransactionsNotifier, FinanceTransactions>(
      AdminTransactionsNotifier.new,
    );

/// Every center, private ones and closed ones included (the administrator's list).
final allCostCentersProvider = FutureProvider.autoDispose<List<CostCenter>>(
  (ref) => ref.watch(financeRepositoryProvider).allCostCenters(),
);

class FinanceTransactionsNotifier extends LedgerNotifier {
  @override
  Future<WalletTransactionPage> fetchPage({
    required int limit,
    required int offset,
  }) => ref
      .read(financeRepositoryProvider)
      .myTransactions(limit: limit, offset: offset);
}

class AdminTransactionsNotifier extends LedgerNotifier {
  @override
  Future<WalletTransactionPage> fetchPage({
    required int limit,
    required int offset,
  }) => ref
      .read(financeRepositoryProvider)
      .transactions(limit: limit, offset: offset);
}

/// A ledger, one page at a time. What the page is *of* — one user's rows or
/// everyone's — is the subclass's.
abstract class LedgerNotifier extends AsyncNotifier<FinanceTransactions> {
  Future<WalletTransactionPage> fetchPage({
    required int limit,
    required int offset,
  });

  /// Bumped by every rebuild and by teardown, so an answer for a state that is
  /// gone is dropped instead of written over the current one
  /// (`PrintLogNotifier._epoch` explains why a flag cannot do this).
  var _epoch = 0;

  @override
  Future<FinanceTransactions> build() {
    ref.watch(serverProfileProvider);
    _epoch++;
    ref.onDispose(() => _epoch++);
    return _page(offset: 0);
  }

  Future<FinanceTransactions> _page({
    required int offset,
    List<WalletTransaction> before = const [],
  }) async {
    final page = await fetchPage(limit: financePageSize, offset: offset);
    return FinanceTransactions(
      items: [...before, ...page.items],
      total: page.total,
    );
  }

  /// Pull-to-refresh: back to the first page.
  Future<void> refresh() async {
    // Bumped here too: a page still in flight belongs to the list this replaces.
    final epoch = ++_epoch;
    state = const AsyncLoading<FinanceTransactions>();
    final next = await AsyncValue.guard(() => _page(offset: 0));
    if (epoch != _epoch) return;
    state = next;
  }

  /// Append the next page. A refusal leaves what is on screen alone, and the
  /// user asks again by scrolling; anything else is left to the app's
  /// uncaught-error probe, with the list freed on the way past.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null ||
        state.isLoading ||
        current.loadingMore ||
        !current.hasMore) {
      return;
    }
    final epoch = _epoch;
    state = AsyncValue.data(
      FinanceTransactions(
        items: current.items,
        total: current.total,
        loadingMore: true,
      ),
    );
    try {
      final next = await _page(
        offset: current.items.length,
        before: current.items,
      );
      if (epoch != _epoch) return;
      state = AsyncValue.data(next);
    } on AppApiException {
      // See above.
    } finally {
      final now = state.value;
      if (epoch == _epoch && now != null && now.loadingMore) {
        state = AsyncValue.data(
          FinanceTransactions(items: now.items, total: now.total),
        );
      }
    }
  }
}
