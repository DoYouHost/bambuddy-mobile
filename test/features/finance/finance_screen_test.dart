import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/l10n/error_messages.dart';
import 'package:bambuddy_mobile/core/models/cost_center.dart';
import 'package:bambuddy_mobile/core/models/wallet.dart';
import 'package:bambuddy_mobile/data/finance_repository.dart';
import 'package:bambuddy_mobile/features/common/dash_progress_bar.dart';
import 'package:bambuddy_mobile/features/finance/finance_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// A finance repository that answers from memory and remembers what it was
/// asked, so a test reads the paging off `asked` instead of off a mock handler.
class _Ledger extends FinanceRepository {
  _Ledger({
    this.balanceValue = 12.5,
    this.centers = const [],
    required this.rows,
    this.failBalance = false,
  }) : super(Dio());

  final double balanceValue;
  final List<CostCenter> centers;
  final List<WalletTransaction> rows;
  final bool failBalance;
  final List<int> asked = [];

  @override
  Future<WalletBalance> balance() async {
    if (failBalance) {
      throw const NetworkException(AppErrorCode.serverUnreachable);
    }
    return WalletBalance(balance: balanceValue);
  }

  @override
  Future<List<CostCenter>> myCostCenters() async => centers;

  @override
  Future<WalletTransactionPage> myTransactions({
    required int limit,
    required int offset,
  }) async {
    asked.add(offset);
    return WalletTransactionPage(
      items: rows.skip(offset).take(limit).toList(),
      total: rows.length,
    );
  }
}

WalletTransaction _tx(
  int id, {
  WalletTransactionType type = WalletTransactionType.printCharge,
  double amount = -1.5,
  int? center = 1,
  String? description = 'Cube',
  double? after = 10,
}) => WalletTransaction(
  id: id,
  userId: 1,
  type: type,
  typeWire: type.wire,
  amount: amount,
  costCenterId: center,
  description: description,
  balanceAfter: after,
  createdAt: DateTime.utc(2026, 10, 1, 12),
);

const _own = CostCenter(
  id: 1,
  name: 'Alice',
  isPrivate: true,
  totalBalance: -3,
);
const _shop = CostCenter(
  id: 2,
  name: 'Workshop',
  budget: CostCenterBudget.monthly,
  budgetLimit: 100,
  budgetUsed: 37.5,
  budgetAvailable: 62.5,
  totalBalance: 40,
);

void main() {
  Future<void> pump(
    WidgetTester tester,
    _Ledger ledger, {
    double dp = 2400,
  }) async {
    usePhoneWindow(tester, dp: dp);
    await pumpPhone(
      tester,
      const FinanceScreen(),
      overrides: [
        noServerProfileOverride,
        financeRepositoryProvider.overrideWithValue(ledger),
        serverSettingsOverride(const {'currency': 'USD'}),
      ],
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the balance, the centers with their budgets, the ledger', (
    tester,
  ) async {
    await pump(
      tester,
      _Ledger(
        balanceValue: -4.25,
        centers: const [_own, _shop],
        rows: [
          _tx(1, amount: -1.5, after: -4.25),
          _tx(
            2,
            type: WalletTransactionType.deposit,
            amount: 50,
            center: 2,
            description: 'Top-up',
          ),
        ],
      ),
    );

    expect(find.text(r'-$4.25'), findsOneWidget, reason: 'the balance');
    // An own center is labelled so; a budgeted one reads left / limit.
    expect(find.text(pl.queueCostCenterPersonal('Alice')), findsOneWidget);
    expect(find.text(pl.financeUnlimited), findsOneWidget);
    expect(find.text(r'$62.50 / $100.00'), findsOneWidget);
    expect(find.text(pl.financeBudgetMonthly), findsOneWidget);
    expect(find.text(pl.financeBudgetNone), findsOneWidget);
    expect(find.text(pl.financeAccountBalance(r'-$3.00')), findsOneWidget);
    // Signed amounts, and what the balance came to afterwards.
    expect(find.text(r'-$1.50'), findsOneWidget);
    expect(find.text(r'+$50.00'), findsOneWidget);
    expect(find.text(pl.financeBalanceAfter(r'-$4.25')), findsOneWidget);
    expect(find.text('Top-up'), findsOneWidget);
  });

  testWidgets('a partial charge is badged and its tag lifted out of the text', (
    tester,
  ) async {
    await pump(
      tester,
      _Ledger(rows: [_tx(1, description: 'Cube [aborted: bed adhesion]')]),
    );

    expect(find.text(pl.financePartialAborted), findsOneWidget);
    expect(find.text('Cube'), findsOneWidget);
    expect(find.textContaining('bed adhesion'), findsNothing);
  });

  testWidgets('a kind this app has no word for is shown by the server\'s own', (
    tester,
  ) async {
    await pump(
      tester,
      _Ledger(
        rows: [
          const WalletTransaction(
            id: 1,
            userId: 1,
            type: WalletTransactionType.other,
            typeWire: 'refund',
            amount: 2,
          ),
        ],
      ),
    );

    expect(find.text('refund'), findsOneWidget);
  });

  testWidgets('both filters narrow the rows already loaded', (tester) async {
    await pump(
      tester,
      _Ledger(
        centers: const [_own, _shop],
        rows: [
          _tx(1, description: 'Cube'),
          _tx(2, description: 'Bin', center: 2),
          _tx(
            3,
            type: WalletTransactionType.deposit,
            amount: 9,
            center: 2,
            description: 'Top-up',
          ),
        ],
      ),
    );
    expect(find.text('Cube'), findsOneWidget);

    await tester.tap(find.byType(DropdownMenu<WalletTransactionType?>));
    await tester.pumpAndSettle();
    // The second kind offered: print charge, then deposit.
    await tester.tap(byLogId('finance.type.option').at(1));
    await tester.pumpAndSettle();
    expect(find.text('Top-up'), findsOneWidget);
    expect(find.text('Cube'), findsNothing);
    expect(find.text('Bin'), findsNothing);

    await tester.tap(find.byType(DropdownMenu<int?>));
    await tester.pumpAndSettle();
    // The first center offered is the user's own, which holds no deposit.
    await tester.tap(byLogId('finance.cost_center.option').first);
    await tester.pumpAndSettle();
    expect(find.text(pl.financeNoTransactionsForFilter), findsOneWidget);
  });

  testWidgets('another page is fetched on demand, from where the last ended', (
    tester,
  ) async {
    final ledger = _Ledger(rows: [for (var i = 1; i <= 60; i++) _tx(i)]);
    // Tall enough to lay out all fifty rows, so nothing scrolls: scrolling near
    // the end fetches the next page by itself, which is not what is tested here.
    await pump(tester, ledger, dp: 12000);

    expect(ledger.asked, [0]);
    expect(
      find.textContaining(pl.financeShowing(50, 60)),
      findsOneWidget,
      reason: 'the footer says how far the ledger has been read',
    );

    await tester.tap(byLogId('finance.load_more'));
    await tester.pumpAndSettle();

    expect(ledger.asked, [0, 50]);
    expect(byLogId('finance.load_more'), findsNothing);
    expect(find.text(pl.financeShowing(60, 60)), findsOneWidget);
  });

  testWidgets('scrolling towards the end fetches the next page by itself', (
    tester,
  ) async {
    final ledger = _Ledger(rows: [for (var i = 1; i <= 60; i++) _tx(i)]);
    await pump(tester, ledger, dp: 800);

    await tester.drag(find.byType(ListView), const Offset(0, -20000));
    await tester.pumpAndSettle();

    expect(ledger.asked, [0, 50]);
  });

  testWidgets('an empty ledger and no centers say so', (tester) async {
    await pump(tester, _Ledger(rows: const []));

    expect(find.text(pl.financeNoCostCenters), findsOneWidget);
    expect(find.text(pl.financeNoTransactions), findsOneWidget);
  });

  testWidgets('a budget of zero reads as spent, not as untouched', (
    tester,
  ) async {
    // An administrator stops a center printing by giving it a limit of 0.
    await pump(
      tester,
      _Ledger(
        centers: const [
          CostCenter(
            id: 2,
            name: 'Frozen',
            budget: CostCenterBudget.total,
            budgetLimit: 0,
            budgetUsed: 0,
            budgetAvailable: 0,
          ),
        ],
        rows: const [],
      ),
    );

    final bar = tester.widget<DashProgressBar>(find.byType(DashProgressBar));
    expect(bar.value, 1);
    expect(bar.color, isNotNull, reason: 'the exhausted colour');
  });

  testWidgets('a charge of nothing is neither income nor a cost', (
    tester,
  ) async {
    await pump(tester, _Ledger(rows: [_tx(1, amount: 0, after: 5)]));

    expect(find.text(r'$0.00'), findsOneWidget);
    expect(find.text(r'+$0.00'), findsNothing);
  });

  testWidgets('a part that cannot be read does not take the rest down', (
    tester,
  ) async {
    await pump(
      tester,
      _Ledger(failBalance: true, rows: [_tx(1, description: 'Cube')]),
    );

    expect(
      find.text(
        const NetworkException(AppErrorCode.serverUnreachable).localized(pl),
      ),
      findsOneWidget,
    );
    expect(find.text('Cube'), findsOneWidget);
  });
}
