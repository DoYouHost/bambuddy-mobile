import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/archive_stats.dart';
import 'package:bambuddy_mobile/core/models/cost_center.dart';
import 'package:bambuddy_mobile/core/models/wallet.dart';
import 'package:bambuddy_mobile/data/finance_repository.dart';
import 'package:bambuddy_mobile/features/finance/finance_screen.dart';
import 'package:bambuddy_mobile/features/stats/stats_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// A finance server in memory that remembers every write as a line, so a test
/// reads what the forms sent off `calls` instead of off a mock handler.
class _Server extends FinanceRepository {
  _Server() : super(Dio());

  final List<String> calls = [];
  List<CostCenter> centers = const [
    CostCenter(id: 1, name: 'Alice', isPrivate: true, ownerUserId: 1),
    CostCenter(
      id: 2,
      name: 'Workshop',
      budget: CostCenterBudget.monthly,
      budgetLimit: 100,
      budgetAvailable: 62.5,
    ),
  ];
  List<WalletTransaction> ledger = [
    WalletTransaction(
      id: 10,
      userId: 2,
      type: WalletTransactionType.printCharge,
      typeWire: 'print_charge',
      amount: -3,
      costCenterId: 2,
      description: 'Cube',
    ),
  ];
  List<CostCenterMember> members = const [
    CostCenterMember(userId: 2, canPrint: true),
  ];

  /// The user's own ledger, which the personal view and a modify-only admin read.
  List<WalletTransaction> own = const [];

  /// When set, every write is refused with it.
  AppApiException? refuse;

  Future<void> _write(String line) async {
    calls.add(line);
    if (refuse != null) throw refuse!;
  }

  @override
  Future<WalletBalance> balance() async => const WalletBalance(balance: 1);

  @override
  Future<List<CostCenter>> myCostCenters() async => centers;

  @override
  Future<List<CostCenter>> allCostCenters({
    bool includeInactive = true,
  }) async => centers;

  @override
  Future<WalletTransactionPage> myTransactions({
    required int limit,
    required int offset,
  }) async {
    calls.add('read:mine');
    return WalletTransactionPage(items: own, total: own.length);
  }

  @override
  Future<WalletTransactionPage> transactions({
    required int limit,
    required int offset,
    int? userId,
  }) async {
    calls.add('read:all');
    return WalletTransactionPage(items: ledger, total: ledger.length);
  }

  @override
  Future<CostCenterDetail> costCenter(int id) async => CostCenterDetail(
    center: centers.firstWhere((c) => c.id == id),
    members: members,
  );

  @override
  Future<CostCenter> createCostCenter({
    required String name,
    required BudgetInput budget,
    bool isActive = true,
  }) async {
    await _write('create:$name:${budget.kind.name}:${budget.amount}');
    return CostCenter(id: 99, name: name);
  }

  @override
  Future<void> updateCostCenter(int id, {String? name, bool? isActive}) =>
      _write('update:$id:$name:$isActive');

  @override
  Future<void> setBudget(int id, BudgetInput budget) =>
      _write('budget:$id:${budget.kind.name}:${budget.amount}');

  @override
  Future<void> deleteCostCenter(int id) => _write('delete:$id');

  @override
  Future<void> setMember(int id, int userId, {required bool canPrint}) =>
      _write('member:$id:$userId:$canPrint');

  @override
  Future<void> removeMember(int id, int userId) =>
      _write('unmember:$id:$userId');

  @override
  Future<void> adjustWallet(
    int userId, {
    required double amount,
    required bool deposit,
    String? description,
    int? costCenterId,
  }) => _write(
    '${deposit ? 'deposit' : 'withdraw'}:$userId:$amount:$description:$costCenterId',
  );

  @override
  Future<void> addManualPrint({
    required int userId,
    required int costCenterId,
    required double amount,
    String? description,
  }) => _write('manual:$userId:$costCenterId:$amount:$description');

  @override
  Future<void> editTransaction(
    int id, {
    int? userId,
    double? amount,
    String? description,
    int? costCenterId,
  }) => _write('edit:$id:$userId:$amount:$description:$costCenterId');

  @override
  Future<void> deleteTransaction(int id) => _write('deltx:$id');
}

const _users = [
  UserSummary(id: 1, username: 'alice'),
  UserSummary(id: 2, username: 'bob'),
  UserSummary(id: 3, username: 'cara'),
];

const _all = {
  'cost_centers:read_all',
  'cost_centers:create',
  'cost_centers:modify',
};

/// What was written, without the reads a screen makes on the way.
List<String> _writes(_Server server) => [
  for (final c in server.calls)
    if (!c.startsWith('read')) c,
];

void main() {
  Future<void> pump(
    WidgetTester tester,
    _Server server, {
    Set<String> permissions = _all,
    bool admin = true,
  }) async {
    usePhoneWindow(tester, dp: 3000);
    await pumpPhone(
      tester,
      const FinanceScreen(),
      overrides: [
        noServerProfileOverride,
        financeRepositoryProvider.overrideWithValue(server),
        identifiedPermissionProvider.overrideWith(
          (ref, p) => permissions.contains(p),
        ),
        statsUsersProvider.overrideWith((ref) async => _users),
        serverSettingsOverride(const {'currency': 'USD'}),
      ],
    );
    await tester.pumpAndSettle();
    if (admin && permissions.isNotEmpty) {
      await tester.tap(find.text(pl.financeAdminView));
      await tester.pumpAndSettle();
    }
  }

  /// Picks the [index]th row of the select named [id].
  Future<void> pick(WidgetTester tester, String id, int index) async {
    await tester.ensureVisible(byLogId(id).first);
    await tester.tap(byLogId(id).first);
    await tester.pumpAndSettle();
    await tester.tap(byLogId('$id.option').at(index));
    await tester.pumpAndSettle();
  }

  /// Opens the select named [id] and taps the row tagged [option].
  Future<void> choose(WidgetTester tester, String id, String option) async {
    await tester.ensureVisible(byLogId(id).first);
    await tester.tap(byLogId(id).first);
    await tester.pumpAndSettle();
    await tester.tap(byLogId(option));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String id, String text) async {
    await tester.ensureVisible(byLogId(id));
    await tester.enterText(
      find.descendant(of: byLogId(id), matching: find.byType(TextFormField)),
      text,
    );
    await tester.pump();
  }

  Future<void> save(WidgetTester tester, String id) async {
    await tester.ensureVisible(byLogId(id));
    await tester.tap(byLogId(id));
    await tester.pumpAndSettle();
  }

  group('who sees the administrator\'s view', () {
    testWidgets('a user with no finance permission beyond their own does not', (
      tester,
    ) async {
      await pump(tester, _Server(), permissions: const {});

      expect(byLogId('finance.view_mode'), findsNothing);
    });

    for (final permission in _all) {
      testWidgets('$permission is enough', (tester) async {
        await pump(tester, _Server(), permissions: {permission}, admin: false);

        expect(byLogId('finance.view_mode'), findsOneWidget);
      });
    }

    testWidgets(
      'three buttons: the first takes the row, the others share the next',
      (tester) async {
        await pump(tester, _Server());

        final create = tester.getRect(byLogId('finance.create_center'));
        final wallet = tester.getRect(byLogId('finance.adjust_wallet'));
        final manual = tester.getRect(byLogId('finance.manual_print'));

        expect(tester.takeException(), isNull);
        expect(create.width, greaterThan(wallet.width));
        expect(create.left, wallet.left);
        expect(create.right, manual.right, reason: 'the edges line up');
        expect(wallet.top, manual.top);
        expect(wallet.width.round(), manual.width.round());
        expect(wallet.top, greaterThan(create.bottom));
        expect(manual.right, lessThanOrEqualTo(360));
        // No style of its own: the label takes what the button gives it.
        final label = tester.widget<Text>(
          find.descendant(
            of: byLogId('finance.create_center'),
            matching: find.text(pl.financeButtonNewCenter),
          ),
        );
        expect(label.style, isNull);
      },
    );

    testWidgets('two buttons split the row', (tester) async {
      await pump(tester, _Server(), permissions: {'cost_centers:modify'});
      final wallet = tester.getRect(byLogId('finance.adjust_wallet'));
      final manual = tester.getRect(byLogId('finance.manual_print'));

      expect(wallet.top, manual.top);
      expect(wallet.width.round(), manual.width.round());
    });

    testWidgets('one button takes the whole row', (tester) async {
      await pump(tester, _Server(), permissions: {'cost_centers:create'});

      expect(
        tester.getRect(byLogId('finance.create_center')).width,
        greaterThan(300),
      );
    });

    testWidgets('create alone offers a new center and nothing else', (
      tester,
    ) async {
      await pump(tester, _Server(), permissions: {'cost_centers:create'});

      expect(byLogId('finance.create_center'), findsOneWidget);
      expect(byLogId('finance.adjust_wallet'), findsNothing);
      expect(byLogId('finance.manual_print'), findsNothing);
    });

    testWidgets('modify alone offers the wallet and the manual charge', (
      tester,
    ) async {
      await pump(tester, _Server(), permissions: {'cost_centers:modify'});

      expect(byLogId('finance.create_center'), findsNothing);
      expect(byLogId('finance.adjust_wallet'), findsOneWidget);
      expect(byLogId('finance.manual_print'), findsOneWidget);
    });
  });

  group('the administrator\'s lists', () {
    testWidgets(
      'read every user\'s ledger, and say whose each row and center is',
      (tester) async {
        final server = _Server();
        await pump(tester, server);

        expect(server.calls, contains('read:all'));
        expect(find.text(pl.financeShared), findsOneWidget);
        expect(
          find.text('alice'),
          findsOneWidget,
          reason: 'the private center\'s owner',
        );
        expect(
          find.textContaining('bob'),
          findsOneWidget,
          reason: 'the row\'s user',
        );
      },
    );

    testWidgets('without read_all the ledger stays the user\'s own', (
      tester,
    ) async {
      final server = _Server();
      await pump(tester, server, permissions: {'cost_centers:create'});

      expect(server.calls, contains('read:mine'));
      expect(server.calls, isNot(contains('read:all')));
    });

    testWidgets(
      'a private center can only be edited; a shared one also deleted or opened',
      (tester) async {
        await pump(tester, _Server());
        final menus = byLogId('finance.center_menu');
        expect(menus, findsNWidgets(2));

        await tester.tap(menus.first);
        await tester.pumpAndSettle();
        expect(byLogId('finance.center_menu.edit'), findsOneWidget);
        expect(byLogId('finance.center_menu.members'), findsNothing);
        expect(byLogId('finance.center_menu.delete'), findsNothing);
        await tester.tapAt(Offset.zero);
        await tester.pumpAndSettle();

        await tester.tap(menus.last);
        await tester.pumpAndSettle();
        expect(byLogId('finance.center_menu.members'), findsOneWidget);
        expect(byLogId('finance.center_menu.delete'), findsOneWidget);
      },
    );

    testWidgets(
      'modify without read_all still edits the rows of its own ledger',
      (tester) async {
        // The ledger stays the user's own, but the writes need `modify` alone.
        final server = _Server()
          ..own = const [
            WalletTransaction(
              id: 5,
              userId: 1,
              type: WalletTransactionType.printCharge,
              typeWire: 'print_charge',
              amount: -2,
            ),
          ];
        await pump(tester, server, permissions: {'cost_centers:modify'});

        expect(server.calls, contains('read:mine'));
        expect(byLogId('finance.transaction_menu'), findsOneWidget);
      },
    );

    testWidgets('no menus without modify', (tester) async {
      await pump(tester, _Server(), permissions: {'cost_centers:read_all'});

      expect(byLogId('finance.center_menu'), findsNothing);
      expect(byLogId('finance.transaction_menu'), findsNothing);
    });
  });

  group('deleting', () {
    testWidgets('a center is asked about first, then deleted', (tester) async {
      final server = _Server();
      await pump(tester, server);

      await tester.tap(byLogId('finance.center_menu').last);
      await tester.pumpAndSettle();
      await tester.tap(byLogId('finance.center_menu.delete'));
      await tester.pumpAndSettle();
      expect(
        find.text(pl.financeConfirmDeleteCostCenter('Workshop')),
        findsOneWidget,
      );
      expect(server.calls.where((c) => c.startsWith('delete')), isEmpty);

      await tester.tap(byLogId('finance.delete_center.confirm'));
      await tester.pumpAndSettle();

      expect(server.calls, contains('delete:2'));
      expect(find.text(pl.financeCostCenterDeleted), findsOneWidget);
    });

    testWidgets('a center the ledger still names says why not, in words', (
      tester,
    ) async {
      final server = _Server()
        ..refuse = const ApiException(
          AppErrorCode.badResponse,
          statusCode: 400,
          detail:
              'Cost center cannot be deleted while transactions reference it',
        );
      await pump(tester, server);

      await tester.tap(byLogId('finance.center_menu').last);
      await tester.pumpAndSettle();
      await tester.tap(byLogId('finance.center_menu.delete'));
      await tester.pumpAndSettle();
      await tester.tap(byLogId('finance.delete_center.confirm'));
      await tester.pumpAndSettle();

      expect(find.text(pl.financeDeleteBlockedTransactions), findsOneWidget);
    });

    testWidgets('a row is asked about first, then deleted', (tester) async {
      final server = _Server();
      await pump(tester, server);

      await tester.tap(byLogId('finance.transaction_menu'));
      await tester.pumpAndSettle();
      await tester.tap(byLogId('finance.transaction_menu.delete'));
      await tester.pumpAndSettle();
      await tester.tap(byLogId('finance.delete_transaction.confirm'));
      await tester.pumpAndSettle();

      expect(server.calls, contains('deltx:10'));
    });
  });

  group('the cost center form', () {
    testWidgets('creates a shared one with a monthly budget', (tester) async {
      final server = _Server();
      await pump(tester, server);

      await tester.tap(byLogId('finance.create_center'));
      await tester.pumpAndSettle();
      await type(tester, 'finance_form.name', '  Club ');
      await type(tester, 'finance_form.budget', '80,5');
      await save(tester, 'finance_form.save_center');

      expect(_writes(server), ['create:Club:monthly:80.5']);
    });

    testWidgets('wants a name', (tester) async {
      final server = _Server();
      await pump(tester, server);

      await tester.tap(byLogId('finance.create_center'));
      await tester.pumpAndSettle();
      await save(tester, 'finance_form.save_center');

      expect(find.text(pl.financeCostCenterNameRequired), findsOneWidget);
      expect(server.calls.where((c) => c.startsWith('create')), isEmpty);
    });

    testWidgets('edits a shared one: the name, then the budget', (
      tester,
    ) async {
      final server = _Server();
      await pump(tester, server);

      await tester.tap(byLogId('finance.center_menu').last);
      await tester.pumpAndSettle();
      await tester.tap(byLogId('finance.center_menu.edit'));
      await tester.pumpAndSettle();
      await type(tester, 'finance_form.name', 'Shop');
      await type(tester, 'finance_form.budget', '120');
      await save(tester, 'finance_form.save_center');

      expect(server.calls.where((c) => !c.startsWith('read')), [
        'update:2:Shop:null',
        'budget:2:monthly:120.0',
      ]);
    });

    testWidgets('edits a personal one: its budget alone', (tester) async {
      final server = _Server();
      await pump(tester, server);

      await tester.tap(byLogId('finance.center_menu').first);
      await tester.pumpAndSettle();
      await tester.tap(byLogId('finance.center_menu.edit'));
      await tester.pumpAndSettle();
      // A personal center starts with no budget, so there is no amount to type.
      await choose(
        tester,
        'finance_form.budget_kind',
        'finance_form.budget_kind.monthly',
      );
      await type(tester, 'finance_form.budget', '0');
      await save(tester, 'finance_form.save_center');

      // The server answers a rename of a personal center with 400.
      expect(server.calls.where((c) => !c.startsWith('read')), [
        'budget:1:monthly:0.0',
      ]);
      expect(
        find.text(pl.financePrivateBudgetOnly),
        findsNothing,
        reason: 'the sheet is closed',
      );
    });

    testWidgets('a budget of none is sent as none', (tester) async {
      final server = _Server();
      await pump(tester, server);

      await tester.tap(byLogId('finance.center_menu').last);
      await tester.pumpAndSettle();
      await tester.tap(byLogId('finance.center_menu.edit'));
      await tester.pumpAndSettle();
      await choose(
        tester,
        'finance_form.budget_kind',
        'finance_form.budget_kind.none',
      );
      await save(tester, 'finance_form.save_center');

      expect(_writes(server).last, 'budget:2:none:null');
    });

    testWidgets('a refusal keeps the sheet open', (tester) async {
      final server = _Server()
        ..refuse = const ApiException(
          AppErrorCode.badResponse,
          statusCode: 400,
          detail: 'Name already used',
        );
      await pump(tester, server);

      await tester.tap(byLogId('finance.create_center'));
      await tester.pumpAndSettle();
      await type(tester, 'finance_form.name', 'Club');
      await save(tester, 'finance_form.save_center');

      expect(byLogId('sheet.cost_center_form'), findsOneWidget);
      expect(find.text('Name already used'), findsOneWidget);
    });
  });

  group('the wallet', () {
    testWidgets('is adjusted for a user, by an amount above zero', (
      tester,
    ) async {
      final server = _Server();
      await pump(tester, server);

      await tester.tap(byLogId('finance.adjust_wallet'));
      await tester.pumpAndSettle();
      await type(tester, 'finance_form.amount', '0');
      await save(tester, 'finance_form.save_adjust');
      expect(find.text(pl.financeUserRequired), findsOneWidget);
      expect(find.text(pl.financeAmountPositive), findsOneWidget);

      await pick(tester, 'finance_form.user', 1);
      await type(tester, 'finance_form.amount', '12,5');
      await type(tester, 'finance_form.description', 'top-up');
      await save(tester, 'finance_form.save_adjust');

      expect(_writes(server).last, 'deposit:2:12.5:top-up:null');
    });

    testWidgets('a withdrawal is the other kind', (tester) async {
      final server = _Server();
      await pump(tester, server);

      await tester.tap(byLogId('finance.adjust_wallet'));
      await tester.pumpAndSettle();
      await pick(tester, 'finance_form.user', 0);
      await choose(
        tester,
        'finance_form.adjust_kind',
        'finance_form.adjust_kind.withdraw',
      );
      await type(tester, 'finance_form.amount', '3');
      await save(tester, 'finance_form.save_adjust');

      expect(_writes(server).last, 'withdraw:1:3.0:null:null');
    });
  });

  group('a manual print', () {
    testWidgets('needs a user, a center and an amount', (tester) async {
      final server = _Server();
      await pump(tester, server);

      await tester.tap(byLogId('finance.manual_print'));
      await tester.pumpAndSettle();
      await save(tester, 'finance_form.save_manual');
      expect(find.text(pl.financeUserRequired), findsOneWidget);
      expect(find.text(pl.financeCostCenterRequired), findsOneWidget);

      await pick(tester, 'finance_form.user', 2);
      await pick(tester, 'finance_form.center', 1);
      await type(tester, 'finance_form.amount', '0');
      await save(tester, 'finance_form.save_manual');
      expect(find.text(pl.financeAmountPositive), findsOneWidget);
      expect(_writes(server), isEmpty);
      await type(tester, 'finance_form.amount', '4');
      await save(tester, 'finance_form.save_manual');

      expect(_writes(server).last, 'manual:3:2:4.0:null');
    });
  });

  group('editing a row', () {
    testWidgets('sends only what changed', (tester) async {
      final server = _Server();
      await pump(tester, server);

      await tester.tap(byLogId('finance.transaction_menu'));
      await tester.pumpAndSettle();
      await tester.tap(byLogId('finance.transaction_menu.edit'));
      await tester.pumpAndSettle();
      await type(tester, 'finance_form.amount', '-4,5');
      await save(tester, 'finance_form.save_transaction');

      expect(_writes(server).last, 'edit:10:null:-4.5:null:null');
    });
  });

  group('the members of a center', () {
    Future<void> open(WidgetTester tester, _Server server) async {
      await pump(tester, server);
      await tester.tap(byLogId('finance.center_menu').last);
      await tester.pumpAndSettle();
      await tester.tap(byLogId('finance.center_menu.members'));
      await tester.pumpAndSettle();
    }

    testWidgets('are listed by name, with whether they may print', (
      tester,
    ) async {
      await open(tester, _Server());

      expect(find.text('bob'), findsWidgets);
      expect(byLogId('finance_form.member_can_print'), findsOneWidget);
    });

    testWidgets('may be switched off, and removed', (tester) async {
      final server = _Server();
      await open(tester, server);

      await tester.tap(byLogId('finance_form.member_can_print'));
      await tester.pumpAndSettle();
      await tester.tap(byLogId('finance_form.member_remove'));
      await tester.pumpAndSettle();

      expect(
        server.calls,
        containsAllInOrder(['member:2:2:false', 'unmember:2:2']),
      );
    });

    testWidgets(
      'a user is added with whether they may print, and a member is not offered twice',
      (tester) async {
        final server = _Server();
        await open(tester, server);

        await tester.ensureVisible(byLogId('finance_form.member_user'));
        await tester.tap(byLogId('finance_form.member_user'));
        await tester.pumpAndSettle();
        // bob is a member already: alice and cara are what is left to add.
        expect(byLogId('finance_form.member_user.option'), findsNWidgets(2));
        await tester.tap(byLogId('finance_form.member_user.option').last);
        await tester.pumpAndSettle();
        await tester.tap(byLogId('finance_form.member_new_can_print'));
        await tester.pumpAndSettle();
        await save(tester, 'finance_form.member_add');

        expect(_writes(server).last, 'member:2:3:false');
      },
    );

    testWidgets('adding nobody says so', (tester) async {
      final server = _Server();
      await open(tester, server);

      await save(tester, 'finance_form.member_add');

      expect(find.text(pl.financeNoEligibleUsers), findsOneWidget);
      expect(server.calls.where((c) => c.startsWith('member')), isEmpty);
    });
  });
}
