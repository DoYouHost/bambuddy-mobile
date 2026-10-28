import 'package:bambuddy_mobile/core/models/wallet.dart';
import 'package:bambuddy_mobile/core/models/cost_center.dart';
import 'package:bambuddy_mobile/data/finance_repository.dart';
import 'package:bambuddy_mobile/features/finance/finance_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers.dart';
import 'a11y_harness.dart';

/// Rendered contrast and touch targets for `lib/features/finance/`: the
/// personal half (balance, centers, ledger with its two filters, a filter that
/// matches nothing, paging, an empty account, a failed load) and the admin half
/// (the view switch, the three shortcuts, the app-bar menu and its
/// confirmation, both row menus, the delete confirmations, and every sheet:
/// cost center create, edit and private edit, members, wallet adjustment,
/// manual charge and ledger row edit, each also with its validation messages
/// or an open select). The demo backend serves billing as state (see
/// docs/billing.md); the empty and failed states come from a repository that
/// answers nothing or refuses.
void main() {
  group('personal view', () {
    final personal = [
      identifiedPermissionProvider.overrideWith((ref, p) => false),
    ];

    a11ySurface(
      'finance, personal',
      home: () => const FinanceScreen(),
      overrides: personal,
      shows: find.text(pl.financeMyCostCenters),
    );

    a11ySurface(
      'finance, personal, type select open',
      home: () => const FinanceScreen(),
      overrides: personal,
      arrange: (tester) async {
        await tester.tap(byLogId('finance.type'));
      },
      shows: byLogId('finance.type.any'),
    );

    a11ySurface(
      'finance, personal, cost center select open',
      home: () => const FinanceScreen(),
      overrides: personal,
      arrange: (tester) async {
        await tester.tap(byLogId('finance.cost_center'));
      },
      shows: byLogId('finance.cost_center.any'),
    );

    // The demo's own ledger holds no withdrawal, so this filter matches nothing.
    a11ySurface(
      'finance, personal, filter matches nothing',
      home: () => const FinanceScreen(),
      overrides: personal,
      arrange: (tester) async {
        await tester.tap(byLogId('finance.type'));
        await tester.pumpAndSettle();
        await tester.tap(byLogId('finance.type.option').at(2));
      },
      shows: find.text(pl.financeNoTransactionsForFilter),
    );

    a11ySurface(
      'finance, personal, paged ledger',
      home: () => const FinanceScreen(),
      overrides: personal,
      shows: byLogId('finance.load_more'),
    );

    a11ySurface(
      'finance, personal, nothing yet',
      demo: false,
      home: () => const FinanceScreen(),
      overrides: [
        fakeServerProfileOverride(),
        ...personal,
        financeRepositoryProvider.overrideWithValue(_Empty()),
      ],
      shows: find.text(pl.financeNoTransactions),
    );

    a11ySurface(
      'finance, personal, load failed',
      demo: false,
      home: () => const FinanceScreen(),
      overrides: [
        fakeServerProfileOverride(),
        ...personal,
        financeRepositoryProvider.overrideWithValue(_Broken()),
      ],
      shows: find.text(pl.financeLoadFailed),
    );
  });

  group('admin view', () {
    a11ySurface(
      'finance, admin',
      home: () => const FinanceScreen(),
      arrange: _adminView,
      shows: find.text(pl.financeCostCenters),
    );

    a11ySurface(
      'finance, admin, load failed',
      demo: false,
      home: () => const FinanceScreen(),
      overrides: [
        fakeServerProfileOverride(),
        identifiedPermissionProvider.overrideWith((ref, p) => true),
        financeRepositoryProvider.overrideWithValue(_Broken()),
      ],
      arrange: _adminView,
      shows: find.text(pl.financeLoadFailed),
    );

    a11ySurface(
      'finance, admin, app-bar menu',
      home: () => const FinanceScreen(),
      arrange: (tester) async {
        await _adminView(tester);
        await tester.tap(byLogId('finance.more_menu'));
      },
      shows: byLogId('finance.more_menu.rebuild_ledger'),
    );

    a11ySurface(
      'finance, admin, rebuild confirmation',
      home: () => const FinanceScreen(),
      arrange: (tester) async {
        await _adminView(tester);
        await tester.tap(byLogId('finance.more_menu'));
        await tester.pumpAndSettle();
        await tester.tap(byLogId('finance.more_menu.rebuild_ledger'));
      },
      shows: find.text(pl.financeRebuildLedgerConfirm),
    );

    a11ySurface(
      'finance, admin, shared center menu',
      home: () => const FinanceScreen(),
      arrange: (tester) async {
        await _adminView(tester);
        await tester.tap(_centerMenu('Workshop'));
      },
      shows: byLogId('finance.center_menu.members'),
    );

    a11ySurface(
      'finance, admin, private center menu',
      home: () => const FinanceScreen(),
      arrange: (tester) async {
        await _adminView(tester);
        await tester.tap(byLogId('finance.center_menu').first);
      },
      shows: byLogId('finance.center_menu.edit'),
    );

    a11ySurface(
      'finance, admin, delete center confirmation',
      home: () => const FinanceScreen(),
      arrange: (tester) async {
        await _adminView(tester);
        await tester.tap(_centerMenu('Workshop'));
        await tester.pumpAndSettle();
        await tester.tap(byLogId('finance.center_menu.delete'));
      },
      shows: find.text(pl.financeDeleteCostCenter),
    );

    a11ySurface(
      'finance, admin, transaction menu',
      home: () => const FinanceScreen(),
      arrange: (tester) async {
        await _adminView(tester);
        await a11yTap(tester, byLogId('finance.transaction_menu').first);
      },
      shows: byLogId('finance.transaction_menu.edit'),
    );

    a11ySurface(
      'finance, admin, delete transaction confirmation',
      home: () => const FinanceScreen(),
      arrange: (tester) async {
        await _adminView(tester);
        await a11yTap(tester, byLogId('finance.transaction_menu').first);
        await tester.pumpAndSettle();
        await a11yTap(tester, byLogId('finance.transaction_menu.delete'));
      },
      shows: find.text(pl.financeDeleteTransaction),
    );
  });

  group('admin sheets', () {
    a11ySurface(
      'finance sheet, new cost center',
      home: () => const FinanceScreen(),
      arrange: (tester) async {
        await _adminView(tester);
        await tester.tap(byLogId('finance.create_center'));
      },
      shows: byLogId('sheet.cost_center_form'),
    );

    a11ySurface(
      'finance sheet, new cost center, name missing',
      home: () => const FinanceScreen(),
      arrange: (tester) async {
        await _adminView(tester);
        await tester.tap(byLogId('finance.create_center'));
        await tester.pumpAndSettle();
        await tester.tap(byLogId('finance_form.save_center'));
      },
      shows: find.text(pl.financeCostCenterNameRequired),
    );

    a11ySurface(
      'finance sheet, new cost center, budget kind select open',
      home: () => const FinanceScreen(),
      arrange: (tester) async {
        await _adminView(tester);
        await tester.tap(byLogId('finance.create_center'));
        await tester.pumpAndSettle();
        await tester.tap(byLogId('finance_form.budget_kind'));
      },
      shows: byLogId('finance_form.budget_kind.total'),
    );

    a11ySurface(
      'finance sheet, edit shared cost center',
      home: () => const FinanceScreen(),
      arrange: (tester) async {
        await _adminView(tester);
        await tester.tap(_centerMenu('Workshop'));
        await tester.pumpAndSettle();
        await tester.tap(byLogId('finance.center_menu.edit'));
      },
      shows: byLogId('sheet.cost_center_form'),
    );

    a11ySurface(
      'finance sheet, edit private cost center',
      home: () => const FinanceScreen(),
      arrange: (tester) async {
        await _adminView(tester);
        await tester.tap(byLogId('finance.center_menu').first);
        await tester.pumpAndSettle();
        await tester.tap(byLogId('finance.center_menu.edit'));
      },
      shows: find.text(pl.financePrivateBudgetOnly),
    );

    a11ySurface(
      'finance sheet, members',
      home: () => const FinanceScreen(),
      arrange: (tester) async {
        await _adminView(tester);
        await tester.tap(_centerMenu('Workshop'));
        await tester.pumpAndSettle();
        await tester.tap(byLogId('finance.center_menu.members'));
      },
      shows: byLogId('finance_form.member_add'),
    );

    a11ySurface(
      'finance sheet, members, user select open',
      home: () => const FinanceScreen(),
      arrange: (tester) async {
        await _adminView(tester);
        await tester.tap(_centerMenu('Workshop'));
        await tester.pumpAndSettle();
        await tester.tap(byLogId('finance.center_menu.members'));
        await tester.pumpAndSettle();
        await tester.tap(byLogId('finance_form.member_user'));
      },
      shows: byLogId('finance_form.member_user.option'),
    );

    a11ySurface(
      'finance sheet, wallet adjustment',
      home: () => const FinanceScreen(),
      arrange: (tester) async {
        await _adminView(tester);
        await tester.tap(byLogId('finance.adjust_wallet'));
      },
      shows: byLogId('sheet.wallet_adjust'),
    );

    a11ySurface(
      'finance sheet, wallet adjustment, nothing filled in',
      home: () => const FinanceScreen(),
      arrange: (tester) async {
        await _adminView(tester);
        await tester.tap(byLogId('finance.adjust_wallet'));
        await tester.pumpAndSettle();
        await tester.tap(byLogId('finance_form.save_adjust'));
      },
      shows: find.text(pl.financeUserRequired),
    );

    a11ySurface(
      'finance sheet, wallet adjustment, user select open',
      home: () => const FinanceScreen(),
      arrange: (tester) async {
        await _adminView(tester);
        await tester.tap(byLogId('finance.adjust_wallet'));
        await tester.pumpAndSettle();
        await tester.tap(byLogId('finance_form.user'));
      },
      shows: byLogId('finance_form.user.option'),
    );

    a11ySurface(
      'finance sheet, wallet adjustment, kind select open',
      home: () => const FinanceScreen(),
      arrange: (tester) async {
        await _adminView(tester);
        await tester.tap(byLogId('finance.adjust_wallet'));
        await tester.pumpAndSettle();
        await tester.tap(byLogId('finance_form.adjust_kind'));
      },
      shows: byLogId('finance_form.adjust_kind.withdraw'),
    );

    a11ySurface(
      'finance sheet, wallet adjustment, cost center select open',
      home: () => const FinanceScreen(),
      arrange: (tester) async {
        await _adminView(tester);
        await tester.tap(byLogId('finance.adjust_wallet'));
        await tester.pumpAndSettle();
        await tester.tap(byLogId('finance_form.center'));
      },
      shows: byLogId('finance_form.center.any'),
    );

    a11ySurface(
      'finance sheet, manual charge',
      home: () => const FinanceScreen(),
      arrange: (tester) async {
        await _adminView(tester);
        await tester.tap(byLogId('finance.manual_print'));
      },
      shows: byLogId('sheet.manual_print'),
    );

    a11ySurface(
      'finance sheet, manual charge, nothing filled in',
      home: () => const FinanceScreen(),
      arrange: (tester) async {
        await _adminView(tester);
        await tester.tap(byLogId('finance.manual_print'));
        await tester.pumpAndSettle();
        await tester.tap(byLogId('finance_form.save_manual'));
      },
      shows: find.text(pl.financeCostCenterRequired),
    );

    a11ySurface(
      'finance sheet, manual charge, cost center select open',
      home: () => const FinanceScreen(),
      arrange: (tester) async {
        await _adminView(tester);
        await tester.tap(byLogId('finance.manual_print'));
        await tester.pumpAndSettle();
        await tester.tap(byLogId('finance_form.center'));
      },
      shows: byLogId('finance_form.center.option'),
    );

    a11ySurface(
      'finance sheet, edit transaction',
      home: () => const FinanceScreen(),
      arrange: (tester) async {
        await _adminView(tester);
        await a11yTap(tester, byLogId('finance.transaction_menu').first);
        await tester.pumpAndSettle();
        await a11yTap(tester, byLogId('finance.transaction_menu.edit'));
      },
      shows: byLogId('sheet.transaction_edit'),
    );

    a11ySurface(
      'finance sheet, edit transaction, amount not a number',
      home: () => const FinanceScreen(),
      arrange: (tester) async {
        await _adminView(tester);
        await a11yTap(tester, byLogId('finance.transaction_menu').first);
        await tester.pumpAndSettle();
        await a11yTap(tester, byLogId('finance.transaction_menu.edit'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(
            of: byLogId('finance_form.amount'),
            matching: find.byType(TextFormField),
          ),
          'abc',
        );
        await a11yTap(tester, byLogId('finance_form.save_transaction'));
      },
      shows: find.text(pl.financeAmountInvalid),
    );
  });
}

/// Switches the screen to the administrator's half and lets its lists land.
Future<void> _adminView(WidgetTester tester) async {
  await tester.tap(find.text(pl.financeAdminView));
  await a11ySettle(tester, const Duration(seconds: 1));
}

/// The row menu of the cost center called [name]. The row is the column that
/// holds both its name and its menu.
Finder _centerMenu(String name) => find.descendant(
  of: find.ancestor(of: find.text(name), matching: find.byType(Column)).first,
  matching: byLogId('finance.center_menu'),
);

/// A billing account with nothing in it.
class _Empty extends FinanceRepository {
  _Empty() : super(Dio());

  @override
  Future<WalletBalance> balance() async => const WalletBalance(balance: 0);

  @override
  Future<List<CostCenter>> myCostCenters() async => const [];

  @override
  Future<WalletTransactionPage> myTransactions({
    required int limit,
    required int offset,
  }) async => const WalletTransactionPage(items: [], total: 0);
}

/// A billing server that refuses every read.
class _Broken extends FinanceRepository {
  _Broken() : super(Dio());

  // Not an `AppApiException`, so the screen words the failure itself.
  static final _refusal = StateError('refused');

  @override
  Future<WalletBalance> balance() async => throw _refusal;

  @override
  Future<List<CostCenter>> myCostCenters() async => throw _refusal;

  @override
  Future<List<CostCenter>> allCostCenters({
    bool includeInactive = true,
  }) async => throw _refusal;

  @override
  Future<WalletTransactionPage> myTransactions({
    required int limit,
    required int offset,
  }) async => throw _refusal;

  @override
  Future<WalletTransactionPage> transactions({
    required int limit,
    required int offset,
    int? userId,
  }) async => throw _refusal;
}
