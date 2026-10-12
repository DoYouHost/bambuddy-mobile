import 'package:bambuddy_mobile/core/api/api_client.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/api_key.dart';
import 'package:bambuddy_mobile/core/models/cost_center.dart';
import 'package:bambuddy_mobile/core/models/library_file.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/core/models/wallet.dart';
import 'package:bambuddy_mobile/data/api_keys_repository.dart';
import 'package:bambuddy_mobile/data/finance_repository.dart';
import 'package:bambuddy_mobile/data/library_repository.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:bambuddy_mobile/data/server_settings_repository.dart';
import 'package:bambuddy_mobile/features/queue/queue_removal.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';
import '../helpers.dart';

/// A billing server, as the app's stop-gap reads it: the flag it detects
/// billing by, and the refusal it words when a new item has no cost center
/// (maziggy/bambuddy #3256).
///
/// Named `ws_…` to run last: billing on refuses every other test's queue
/// write, so it is switched off again afterwards.
void main() {
  group('billing', skip: contractSkipReason, () {
    test('the flag is readable and a new item is refused in words', () async {
      final dio = await authenticatedDio();
      final settings = ServerSettingsRepository(dio);
      final queue = QueueRepository(dio);
      final file = (await LibraryRepository(
        dio,
      ).listFiles()).firstWhere((f) => f.filename == 'contract-probe.3mf');

      // Billing came in 1.2.5.3; an older server's settings do not list it.
      // The app then reads billing as off, so a file queues as it always did
      // and nothing is refused.
      if (!(await settings.fetch()).containsKey('billing_enabled')) {
        expect((await settings.fetchUiFlags())['billing_enabled'], isNull);
        final known = {for (final i in await queue.fetch()) i.id};
        await queue.addFromLibraryFile(
          file.id,
          options: const QueueCreateOptions(manualStart: true),
        );
        final added = (await queue.fetch()).firstWhere(
          (i) => !known.contains(i.id),
        );
        addTearDown(() => queue.delete(added.id));
        expect(added.costCenterId, isNull);
        return;
      }

      // Queued before billing was switched on: no cost center.
      final before = {for (final i in await queue.fetch()) i.id};
      await queue.addFromLibraryFile(
        file.id,
        options: const QueueCreateOptions(manualStart: true),
      );
      final plain = (await queue.fetch()).firstWhere(
        (i) => !before.contains(i.id),
      );
      addTearDown(() => queue.delete(plain.id));

      await settings.update({'billing_enabled': true});
      addTearDown(() => settings.update({'billing_enabled': false}));

      final flags = await settings.fetchUiFlags();
      // 1.2.6+ has the flags; an older server only the full settings.
      expect(
        flags['billing_enabled'] ?? (await settings.fetch())['billing_enabled'],
        isTrue,
      );

      Future<String> refusal(Future<void> Function() write) async {
        try {
          await write();
        } on AppApiException catch (e) {
          return queueRefusal(en, e);
        }
        fail('a billing server must refuse a job with no cost center');
      }

      expect(
        await refusal(
          () => queue.addFromLibraryFile(
            file.id,
            options: const QueueCreateOptions(manualStart: true),
          ),
        ),
        en.queueBillingUseWeb,
      );
      // Every PATCH checks the budget, so the item queued before is stuck too.
      expect(
        await refusal(() => queue.updateItem(plain.id, manualStart: true)),
        en.queueBillingUseWeb,
      );

      // One queued in the web with a cost center reads back with it, and edits.
      final center =
          (await dio.post<Map<String, dynamic>>(
                '/api/v1/finance/cost-centers',
                data: {'name': 'Contract', 'total_budget': 1000},
              )).data!['id']
              as int;
      final created = (await dio.post<Map<String, dynamic>>(
        '/api/v1/queue/',
        data: {
          'library_file_id': file.id,
          'manual_start': true,
          'cost_center_id': center,
        },
      )).data!;
      final charged = QueueItem.fromJson(created);
      addTearDown(() => queue.delete(charged.id));
      expect(charged.costCenterId, center);
      await queue.updateItem(charged.id, manualStart: true);
    });

    group('cost centers and the wallet', () {
      late Dio dio;
      late ServerSettingsRepository settings;
      late QueueRepository queue;
      late FinanceRepository finance;
      late LibraryFile file;

      /// A shared cost center holding [members], so `mine` lists it for them.
      Future<int> center(
        String name, {
        double? budget,
        List<int> members = const [],
        bool active = true,
      }) async {
        final id =
            (await dio.post<Map<String, dynamic>>(
                  '/api/v1/finance/cost-centers',
                  data: {
                    'name': '$name ${DateTime.now().microsecondsSinceEpoch}',
                    'total_budget': ?budget,
                  },
                )).data!['id']
                as int;
        addTearDown(
          () => dio.delete<dynamic>(
            '/api/v1/finance/cost-centers/$id',
            options: Options(validateStatus: (_) => true),
          ),
        );
        for (final user in members) {
          await dio.post<dynamic>(
            '/api/v1/finance/cost-centers/$id/members',
            data: {'user_id': user, 'can_print': true},
          );
        }
        if (!active) {
          await dio.patch<dynamic>(
            '/api/v1/finance/cost-centers/$id',
            data: {'is_active': false},
          );
        }
        return id;
      }

      Future<String> refusal(Future<void> Function() write) async {
        try {
          await write();
        } on AppApiException catch (e) {
          return queueRefusal(en, e);
        }
        fail('the server must refuse this job');
      }

      setUp(() async {
        dio = await authenticatedDio();
        settings = ServerSettingsRepository(dio);
        queue = QueueRepository(dio);
        finance = FinanceRepository(dio);
        file = (await LibraryRepository(
          dio,
        ).listFiles()).firstWhere((f) => f.filename == 'contract-probe.3mf');
      });

      /// Billing arrived in 1.2.5.3; before it there is nothing to pick.
      Future<bool> billingOn() async {
        if (!(await settings.fetch()).containsKey('billing_enabled')) {
          return false;
        }
        await settings.update({'billing_enabled': true});
        addTearDown(() => settings.update({'billing_enabled': false}));
        return true;
      }

      test(
        'lists a center with its budget, and a job is booked to it',
        () async {
          if (!await billingOn()) return;
          final me =
              (await dio.get<Map<String, dynamic>>(
                    '/api/v1/auth/me',
                  )).data!['id']
                  as int;
          final id = await center('Contract', budget: 1000, members: [me]);

          final mine = await finance.myCostCenters();
          final listed = mine.firstWhere((c) => c.id == id);
          expect(listed.budget, CostCenterBudget.total);
          expect(listed.budgetLimit, 1000);
          expect(listed.budgetAvailable, closeTo(1000, 1));
          expect(listed.canPrint && listed.isActive, isTrue);
          expect(printableCostCenters(mine).map((c) => c.id), contains(id));

          await queue.addFromLibraryFile(
            file.id,
            options: QueueCreateOptions(manualStart: true, costCenterId: id),
          );
          final item = (await queue.fetch()).lastWhere(
            (i) => i.costCenterId == id,
          );
          addTearDown(() => queue.delete(item.id));

          // The picker sends it on an edit too, and the server accepts that.
          await queue.updateItem(item.id, costCenterId: id);
          expect(
            (await queue.fetch())
                .firstWhere((i) => i.id == item.id)
                .costCenterId,
            id,
          );
        },
      );

      test(
        'a job the budget cannot cover, or a closed center, is worded',
        () async {
          if (!await billingOn()) return;
          final tiny = await center('Tiny', budget: 0.01);
          final closed = await center('Closed', budget: 1000, active: false);

          Future<void> add(int id) => queue.addFromLibraryFile(
            file.id,
            options: QueueCreateOptions(manualStart: true, costCenterId: id),
          );

          expect(await refusal(() => add(tiny)), en.queueBillingBudgetExceeded);
          expect(
            await refusal(() => add(closed)),
            en.queueBillingCostCenterInactive,
          );
        },
      );

      test('the ledger and the balance agree, and need the permission', () async {
        if (!await billingOn()) return;
        final me =
            (await dio.get<Map<String, dynamic>>('/api/v1/auth/me')).data!['id']
                as int;
        final before = await finance.balance();
        final rowsBefore = (await finance.myTransactions(
          limit: 1,
          offset: 0,
        )).total;

        await dio.post<dynamic>(
          '/api/v1/finance/users/$me/deposit',
          data: {'amount': 5, 'description': 'contract probe'},
        );

        final after = await finance.balance();
        final page = await finance.myTransactions(limit: 1, offset: 0);
        expect(after.balance, closeTo(before.balance + 5, 1e-6));
        expect(page.total, rowsBefore + 1);
        final top = page.items.single;
        expect(top.type, WalletTransactionType.deposit);
        expect(top.amount, 5);
        expect(top.balanceAfter, closeTo(after.balance, 1e-6));
        expect(top.createdAt, isNotNull);

        // A user whose groups grant nothing is refused, not shown an empty ledger.
        final nobody = await contractUser(dio, ['printers:read']);
        await expectLater(
          FinanceRepository(nobody.dio).balance(),
          throwsA(isA<AuthException>()),
        );
      });

      test(
        'an administrator creates, budgets, shares and deletes a center',
        () async {
          if (!await billingOn()) return;
          final me =
              (await dio.get<Map<String, dynamic>>(
                    '/api/v1/auth/me',
                  )).data!['id']
                  as int;
          final name = 'Admin probe ${DateTime.now().microsecondsSinceEpoch}';
          final made = await finance.createCostCenter(
            name: name,
            budget: const BudgetInput(CostCenterBudget.monthly, 50),
          );
          addTearDown(() async {
            try {
              await finance.deleteCostCenter(made.id);
            } on AppApiException {
              // Deleted by the test, or still named by a row it did not reach.
            }
          });

          Future<CostCenter> read() async => (await finance.allCostCenters())
              .firstWhere((c) => c.id == made.id);
          expect((await read()).budget, CostCenterBudget.monthly);
          expect((await read()).budgetLimit, 50);

          // A budget replaces the old one whole, and none removes it.
          await finance.setBudget(
            made.id,
            const BudgetInput(CostCenterBudget.total, 9),
          );
          expect((await read()).budget, CostCenterBudget.total);
          expect((await read()).budgetLimit, 9);
          await finance.setBudget(made.id, BudgetInput.none);
          expect((await read()).budget, CostCenterBudget.none);

          await finance.updateCostCenter(made.id, name: '$name!');
          expect((await read()).name, '$name!');

          // Members come and go.
          await finance.setMember(made.id, me, canPrint: false);
          var detail = await finance.costCenter(made.id);
          expect(detail.members.single.userId, me);
          expect(detail.members.single.canPrint, isFalse);
          await finance.setMember(made.id, me, canPrint: true);
          expect(
            (await finance.costCenter(made.id)).members.single.canPrint,
            isTrue,
          );
          await finance.removeMember(made.id, me);
          expect((await finance.costCenter(made.id)).members, isEmpty);

          // A personal center takes a budget and nothing else; the refusals say so
          // in the words the app matches on.
          // A user made through the API has a personal center from the start; the
          // admin who set the server up has none.
          final someone = await contractUser(dio, ['printers:read']);
          final private = (await finance.allCostCenters()).firstWhere(
            (c) => c.isPrivate && c.ownerUserId == someone.me.id,
          );
          await expectLater(
            finance.setMember(private.id, me, canPrint: true),
            throwsA(
              isA<AppApiException>().having(
                (e) => e.detail?.toLowerCase(),
                'detail',
                contains('private cost center memberships'),
              ),
            ),
          );
          await expectLater(
            finance.deleteCostCenter(private.id),
            throwsA(isA<AppApiException>()),
          );

          // The ledger: a charge to the center, edited, then removed — after which
          // the center can go. While a row names it, it cannot.
          await finance.adjustWallet(
            me,
            amount: 7,
            deposit: true,
            description: 'admin probe',
            costCenterId: made.id,
          );
          final refusal = await finance
              .deleteCostCenter(made.id)
              .then<AppApiException?>((_) => null)
              .onError<AppApiException>((e, _) => e);
          expect(
            refusal?.detail?.toLowerCase(),
            contains('cannot be deleted while transactions reference'),
            reason: 'the sentence `_refusals` in finance_forms.dart matches',
          );
          final mine = (await finance.transactions(
            limit: 5,
            offset: 0,
            userId: me,
          )).items;
          final row = mine.firstWhere((t) => t.costCenterId == made.id);
          expect(row.type, WalletTransactionType.deposit);
          await finance.editTransaction(row.id, amount: 8);
          expect(
            (await finance.transactions(
              limit: 5,
              offset: 0,
              userId: me,
            )).items.firstWhere((t) => t.id == row.id).amount,
            8,
          );
          await finance.deleteTransaction(row.id);

          await finance.addManualPrint(
            userId: me,
            costCenterId: made.id,
            amount: 3,
          );
          final manual = (await finance.transactions(
            limit: 5,
            offset: 0,
            userId: me,
          )).items.firstWhere((t) => t.costCenterId == made.id);
          expect(
            manual.amount,
            -3,
            reason: 'a manual charge is stored negative',
          );
          await finance.deleteTransaction(manual.id);

          await finance.deleteCostCenter(made.id);
          expect(
            (await finance.allCostCenters()).where((c) => c.id == made.id),
            isEmpty,
          );
        },
      );

      test('a member lists their own, and may not book to another', () async {
        if (!await billingOn()) return;
        final other = await center('Elsewhere', budget: 1000);
        final user = await contractUser(dio, [
          'queue:create',
          'queue:read_all',
          'library:read_all',
        ]);

        final mine = await FinanceRepository(user.dio).myCostCenters();
        final own = defaultCostCenter(printableCostCenters(mine))!;
        expect(own.isPrivate, isTrue);
        expect(own.name, user.me.username);
        expect(own.budget, CostCenterBudget.none);
        expect(mine.map((c) => c.id), isNot(contains(other)));

        final theirs = QueueRepository(user.dio);
        await theirs.addFromLibraryFile(
          file.id,
          options: QueueCreateOptions(manualStart: true, costCenterId: own.id),
        );
        addTearDown(() async {
          for (final i in await theirs.fetch()) {
            if (i.costCenterId == own.id) await queue.delete(i.id);
          }
        });
        expect(
          await refusal(
            () => theirs.addFromLibraryFile(
              file.id,
              options: QueueCreateOptions(
                manualStart: true,
                costCenterId: other,
              ),
            ),
          ),
          en.queueBillingCostCenterNoAccess,
        );
      });

      test('a key lists its owner\'s centers where the server lets it', () async {
        if (!await billingOn()) return;
        final user = await contractUser(dio, [
          'queue:create',
          'queue:read_all',
          'library:read_all',
          'api_keys:create',
          'api_keys:delete',
          'api_keys:read',
        ]);
        final minted = await ApiKeysRepository(user.dio).create(
          const ApiKeyCreateInput(
            name: 'contract probe: cost centers',
            scopes: {ApiKeyScope.queue, ApiKeyScope.readStatus},
          ),
        );
        addTearDown(() => ApiKeysRepository(user.dio).delete(minted.apiKey.id));
        final keyDio = createBareDio()
          ..options.baseUrl = contractBaseUrl
          ..options.headers['X-API-Key'] = minted.key;
        await pollUntil(
          'the key to be committed',
          () async {
            try {
              await keyDio.get<dynamic>('/api/v1/updates/version');
              return true;
            } on DioException {
              return null;
            }
          },
          within: const Duration(seconds: 10),
          every: const Duration(milliseconds: 100),
        );

        // The wallet needs `cost_centers:read_own`, which no key can hold.
        await expectLater(
          FinanceRepository(keyDio).balance(),
          throwsA(isA<AuthException>()),
        );

        // #3256: a key that may queue gets its owner's centers; before it, 401.
        // The app reads a refusal as "this session cannot list them", never as
        // an empty list — the two need different words.
        final listing = FinanceRepository(keyDio).myCostCenters();
        try {
          final mine = await listing;
          expect(printableCostCenters(mine).single.name, user.me.username);
        } on AuthException catch (e) {
          expect(e.code, AppErrorCode.unauthorized);
        }
      });
    });
  });
}
