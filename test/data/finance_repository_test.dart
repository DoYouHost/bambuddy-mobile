import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/cost_center.dart';
import 'package:bambuddy_mobile/data/finance_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

/// One row as `CostCenterSummaryResponse` serialises it.
Map<String, dynamic> _row({
  int id = 1,
  String name = 'Alice',
  bool isPrivate = false,
  bool isActive = true,
  bool canPrint = true,
  String budgetMode = 'none',
  double? limit,
  double? available,
}) => {
  'id': id,
  'name': name,
  'is_private': isPrivate,
  'owner_user_id': isPrivate ? 7 : null,
  'is_active': isActive,
  'total_balance': 0.0,
  'total_budget': null,
  'monthly_budget': budgetMode == 'monthly' ? limit : null,
  'budget_mode': budgetMode,
  'budget_limit': limit,
  'budget_used': limit == null ? null : limit - (available ?? 0),
  'budget_available': available,
  'can_print': canPrint,
};

void main() {
  const path = '/api/v1/finance/cost-centers/mine';

  test('parses the listing, budget included', () async {
    final dio = testDio();
    mockServer(dio).onGet(
      path,
      (s) => s.reply(200, [
        _row(isPrivate: true),
        _row(
          id: 2,
          name: 'Workshop',
          budgetMode: 'monthly',
          limit: 100,
          available: 62.5,
        ),
      ]),
    );

    final centers = await FinanceRepository(dio).myCostCenters();

    expect(centers.map((c) => c.name), ['Alice', 'Workshop']);
    expect(centers.first.isPrivate, isTrue);
    expect(centers.first.budget, CostCenterBudget.none);
    expect(centers.first.budgetAvailable, isNull);
    expect(centers.last.budget, CostCenterBudget.monthly);
    expect(centers.last.budgetLimit, 100);
    expect(centers.last.budgetAvailable, 62.5);
  });

  test('a row the server would not send whole is still usable', () async {
    final dio = testDio();
    mockServer(dio).onGet(
      path,
      (s) => s.reply(200, [
        {'id': 3, 'name': 'Bare', 'budget_mode': 'a-mode-from-the-future'},
      ]),
    );

    final center = (await FinanceRepository(dio).myCostCenters()).single;

    expect(center.isActive && center.canPrint, isTrue);
    expect(center.budget, CostCenterBudget.none);
  });

  test('a 401 is an AuthException, not an empty list', () async {
    // An API key on a server before #3256: `finance.py` hands a key no user.
    final dio = testDio();
    mockServer(
      dio,
    ).onGet(path, (s) => s.reply(401, {'detail': 'Authentication required'}));

    await expectLater(
      FinanceRepository(dio).myCostCenters(),
      throwsA(isA<AuthException>()),
    );
  });

  test('a 403 is an AuthException too', () async {
    final dio = testDio();
    mockServer(dio).onGet(
      path,
      (s) => s.reply(403, {'detail': 'API key cannot queue prints'}),
    );

    await expectLater(
      FinanceRepository(dio).myCostCenters(),
      throwsA(
        isA<AuthException>().having(
          (e) => e.detail,
          'detail',
          'API key cannot queue prints',
        ),
      ),
    );
  });

  test(
    'the balance and a page of the ledger, asked by limit and offset',
    () async {
      final dio = testDio();
      final log = captureRequests(dio);
      mockServer(dio)
        ..onGet(
          '/api/v1/finance/me/balance',
          (s) =>
              s.reply(200, {'user_id': 1, 'balance': -4.5, 'currency': 'USD'}),
        )
        ..onGet(
          '/api/v1/finance/me/transactions',
          (s) => s.reply(200, {
            'items': [
              {
                'id': 1,
                'user_id': 1,
                'transaction_type': 'deposit',
                'amount': 5,
              },
            ],
            'total': 51,
            'limit': 50,
            'offset': 50,
          }),
          queryParameters: {'limit': 50, 'offset': 50},
        );
      final repo = FinanceRepository(dio);

      expect((await repo.balance()).balance, -4.5);
      final page = await repo.myTransactions(limit: 50, offset: 50);

      expect(page.total, 51);
      expect(page.items.single.amount, 5);
      expect(log.last.queryParameters, {'limit': 50, 'offset': 50});
    },
  );

  test('a user without the permission, and every key, is refused', () async {
    final dio = testDio();
    mockServer(dio).onGet(
      '/api/v1/finance/me/balance',
      (s) => s.reply(403, {
        'detail': 'API keys cannot be used for administrative operations',
      }),
    );

    await expectLater(
      FinanceRepository(dio).balance(),
      throwsA(isA<AuthException>()),
    );
  });

  group('the administrator\'s half', () {
    late RequestLog log;
    late FinanceRepository repo;
    late DioAdapter server;

    setUp(() {
      final dio = testDio();
      log = captureRequests(dio);
      server = mockServer(dio);
      repo = FinanceRepository(dio);
    });

    test(
      'lists every center, closed ones included, and reads one with its members',
      () async {
        server
          ..onGet(
            '/api/v1/finance/cost-centers',
            (s) => s.reply(200, [_row(), _row(id: 7, isActive: false)]),
            queryParameters: {'include_inactive': true},
          )
          ..onGet(
            '/api/v1/finance/cost-centers/2',
            (s) => s.reply(200, {
              ..._row(id: 2),
              'members': [
                {
                  'id': 1,
                  'cost_center_id': 2,
                  'user_id': 9,
                  'can_print': false,
                },
              ],
            }),
          );

        expect(await repo.allCostCenters(), hasLength(2));
        final detail = await repo.costCenter(2);

        expect(detail.center.id, 2);
        expect(detail.members.single.userId, 9);
        expect(detail.members.single.canPrint, isFalse);
      },
    );

    test('a create carries the one budget figure that applies', () async {
      server
        ..onPost(
          '/api/v1/finance/cost-centers',
          (s) => s.reply(200, _row(id: 8, name: 'Shop')),
          data: {'name': 'Shop', 'is_active': true, 'monthly_budget': 100.0},
        )
        ..onPost(
          '/api/v1/finance/cost-centers',
          (s) => s.reply(200, _row(id: 9, name: 'Lab')),
          data: {'name': 'Lab', 'is_active': true},
        );

      await repo.createCostCenter(
        name: 'Shop',
        budget: const BudgetInput(CostCenterBudget.monthly, 100),
      );
      await repo.createCostCenter(name: 'Lab', budget: BudgetInput.none);

      expect(log.calls, [
        'POST /api/v1/finance/cost-centers',
        'POST /api/v1/finance/cost-centers',
      ]);
    });

    test('a budget replaces the old one whole, and none removes it', () async {
      server
        ..onPatch(
          '/api/v1/finance/cost-centers/2/budgets',
          (s) => s.reply(200, _row()),
          data: {'total_budget': 5.5},
        )
        ..onPatch(
          '/api/v1/finance/cost-centers/3/budgets',
          (s) => s.reply(200, _row()),
          data: <String, dynamic>{},
        );

      await repo.setBudget(2, const BudgetInput(CostCenterBudget.total, 5.5));
      await repo.setBudget(3, BudgetInput.none);

      expect(log.requests.map((r) => r.data), [
        {'total_budget': 5.5},
        <String, dynamic>{},
      ]);
    });

    test('a rename sends only what was named', () async {
      server
        ..onPatch(
          '/api/v1/finance/cost-centers/2',
          (s) => s.reply(200, _row()),
          data: {'name': 'Shop'},
        )
        ..onPatch(
          '/api/v1/finance/cost-centers/3',
          (s) => s.reply(200, _row()),
          data: {'is_active': false},
        );

      await repo.updateCostCenter(2, name: 'Shop');
      await repo.updateCostCenter(3, isActive: false);
    });

    test('members are set and taken away by user', () async {
      server
        ..onPost(
          '/api/v1/finance/cost-centers/2/members',
          (s) => s.reply(200, {'user_id': 9, 'can_print': false}),
          data: {'user_id': 9, 'can_print': false},
        )
        ..onDelete(
          '/api/v1/finance/cost-centers/2/members/9',
          (s) => s.reply(200, {'status': 'success'}),
        );

      await repo.setMember(2, 9, canPrint: false);
      await repo.removeMember(2, 9);

      expect(log.calls, [
        'POST /api/v1/finance/cost-centers/2/members',
        'DELETE /api/v1/finance/cost-centers/2/members/9',
      ]);
    });

    test('a delete the server refuses keeps its reason', () async {
      server.onDelete(
        '/api/v1/finance/cost-centers/2',
        (s) => s.reply(400, {
          'detail':
              'Cost center cannot be deleted while transactions reference it',
        }),
      );

      await expectLater(
        repo.deleteCostCenter(2),
        throwsA(
          isA<AppApiException>().having(
            (e) => e.detail,
            'detail',
            contains('while transactions reference it'),
          ),
        ),
      );
    });

    test('every user\'s ledger can be narrowed to one', () async {
      server.onGet(
        '/api/v1/finance/transactions',
        (s) => s.reply(200, {'items': [], 'total': 0}),
        queryParameters: {'limit': 50, 'offset': 0, 'user_id': 4},
      );

      await repo.transactions(limit: 50, offset: 0, userId: 4);

      expect(log.last.queryParameters['user_id'], 4);
    });

    test(
      'a deposit and a withdrawal are two routes with one positive amount',
      () async {
        server
          ..onPost(
            '/api/v1/finance/users/4/deposit',
            (s) => s.reply(200, {}),
            data: {'amount': 5.0, 'description': 'top-up', 'cost_center_id': 2},
          )
          ..onPost(
            '/api/v1/finance/users/4/withdraw',
            (s) => s.reply(200, {}),
            data: {'amount': 1.5},
          );

        await repo.adjustWallet(
          4,
          amount: 5,
          deposit: true,
          description: 'top-up',
          costCenterId: 2,
        );
        await repo.adjustWallet(4, amount: 1.5, deposit: false);

        expect(log.calls, [
          'POST /api/v1/finance/users/4/deposit',
          'POST /api/v1/finance/users/4/withdraw',
        ]);
      },
    );

    test(
      'a manual print and a ledger edit send what they were given',
      () async {
        server
          ..onPost(
            '/api/v1/finance/transactions/manual',
            (s) => s.reply(200, {}),
            data: {'user_id': 4, 'cost_center_id': 2, 'amount': 3.0},
          )
          ..onPatch(
            '/api/v1/finance/transactions/11',
            (s) => s.reply(200, {}),
            data: {'amount': -2.5},
          )
          ..onDelete(
            '/api/v1/finance/transactions/11',
            (s) => s.reply(200, {'status': 'success'}),
          );

        await repo.addManualPrint(userId: 4, costCenterId: 2, amount: 3);
        await repo.editTransaction(11, amount: -2.5);
        await repo.deleteTransaction(11);

        expect(log.requests.map((r) => r.method), ['POST', 'PATCH', 'DELETE']);
      },
    );
  });

  group('printableCostCenters', () {
    test('drops an inactive center and one the user may not print with', () {
      const own = CostCenter(id: 1, name: 'Alice', isPrivate: true);
      const viewOnly = CostCenter(id: 2, name: 'Classroom', canPrint: false);
      const closed = CostCenter(id: 3, name: 'Old', isActive: false);
      const shared = CostCenter(id: 4, name: 'Workshop');

      expect(printableCostCenters([own, viewOnly, closed, shared]), [
        own,
        shared,
      ]);
    });

    test(
      'the default is the private one wherever it stands, else the first',
      () {
        const own = CostCenter(id: 1, name: 'Alice', isPrivate: true);
        const a = CostCenter(id: 2, name: 'A');
        const b = CostCenter(id: 3, name: 'B');

        expect(defaultCostCenter([a, own, b]), own);
        expect(defaultCostCenter([a, b]), a);
        expect(defaultCostCenter(const []), isNull);
      },
    );
  });
}
