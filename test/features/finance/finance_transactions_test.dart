import 'dart:async';

import 'package:bambuddy_mobile/core/models/wallet.dart';
import 'package:bambuddy_mobile/data/finance_repository.dart';
import 'package:bambuddy_mobile/features/finance/finance_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

WalletTransaction _tx(int id) => WalletTransaction(
  id: id,
  userId: 1,
  type: WalletTransactionType.deposit,
  amount: 1,
);

/// A ledger whose every page is held until the test lets it go, so the order in
/// which answers arrive is the test's to choose.
class _HeldLedger extends FinanceRepository {
  _HeldLedger() : super(Dio());

  final Map<int, List<Completer<WalletTransactionPage>>> pending = {};

  @override
  Future<WalletTransactionPage> myTransactions({
    required int limit,
    required int offset,
  }) {
    final c = Completer<WalletTransactionPage>();
    pending.putIfAbsent(offset, () => []).add(c);
    return c.future;
  }
}

void main() {
  late _HeldLedger ledger;
  late ProviderContainer container;

  setUp(() {
    ledger = _HeldLedger();
    container = ProviderContainer(
      overrides: [
        noServerProfileOverride,
        financeRepositoryProvider.overrideWithValue(ledger),
      ],
    );
    addTearDown(container.dispose);
    container.listen(financeTransactionsProvider, (_, _) {});
  });

  WalletTransactionPage page(Iterable<int> ids, {int total = 60}) =>
      WalletTransactionPage(items: [for (final i in ids) _tx(i)], total: total);

  Future<void> firstPage() async {
    ledger.pending[0]!.single.complete(page(List.generate(50, (i) => i + 1)));
    await container.read(financeTransactionsProvider.future);
  }

  List<int> ids() => [
    for (final t in container.read(financeTransactionsProvider).value!.items)
      t.id,
  ];

  test('a refresh outranks a page that was still on its way', () async {
    final notifier = container.read(financeTransactionsProvider.notifier);
    await firstPage();

    final more = notifier.loadMore();
    final refreshed = notifier.refresh();
    // The refresh answers first, with a ledger that has since changed.
    ledger.pending[0]![1].complete(page([101, 102], total: 2));
    await refreshed;
    // The page for the old list arrives late and must not be written over it.
    ledger.pending[50]!.single.complete(page(List.generate(10, (i) => 51 + i)));
    await more;

    expect(ids(), [101, 102]);
  });

  test(
    'no second page is asked for while the first is being refreshed',
    () async {
      final notifier = container.read(financeTransactionsProvider.notifier);
      await firstPage();

      unawaited(notifier.refresh());
      await notifier.loadMore();

      expect(ledger.pending.containsKey(50), isFalse);
    },
  );

  test('a page asked twice in a row is fetched once', () async {
    final notifier = container.read(financeTransactionsProvider.notifier);
    await firstPage();

    final a = notifier.loadMore();
    final b = notifier.loadMore();
    ledger.pending[50]!.single.complete(page(List.generate(10, (i) => 51 + i)));
    await Future.wait([a, b]);

    expect(ledger.pending[50], hasLength(1));
    expect(ids(), hasLength(60));
  });
}
