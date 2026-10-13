import 'package:app_util/app_util.dart';
import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/cost_center.dart';
import '../core/models/wallet.dart';

/// REST data source for the server's billing: the cost centers a print is booked
/// to. Maps [DioException] to [AppApiException].
class FinanceRepository {
  FinanceRepository(this._dio);

  final Dio _dio;

  /// GET /finance/cost-centers/mine — every active center this session may see,
  /// whether or not it may print there ([CostCenter.canPrint]).
  ///
  /// A 401 or 403 is [AuthException]: an API key on a server before #3256, or a
  /// key without the queue scope. The caller must not read it as an empty list.
  Future<List<CostCenter>> myCostCenters() => guard(() async {
    final res = await _dio.get<List<dynamic>>(Endpoints.financeCostCentersMine);
    return parseJsonList(res.data, CostCenter.fromJson);
  });

  /// GET /finance/me/balance. A 403 is a user without `cost_centers:read_own`,
  /// and every API key.
  Future<WalletBalance> balance() => guard(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      Endpoints.financeMeBalance,
    );
    return WalletBalance.fromJson(res.data ?? const {});
  });

  /// GET /finance/me/transactions — one page of the user's own ledger.
  Future<WalletTransactionPage> myTransactions({
    required int limit,
    required int offset,
  }) => guard(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      Endpoints.financeMeTransactions,
      queryParameters: {'limit': limit, 'offset': offset},
    );
    return WalletTransactionPage.fromJson(res.data ?? const {});
  });

  // --- The administrator's half. Everything below needs a password login. ---

  /// GET /finance/cost-centers — every center, private ones included.
  Future<List<CostCenter>> allCostCenters({bool includeInactive = true}) =>
      guard(() async {
        final res = await _dio.get<List<dynamic>>(
          Endpoints.financeCostCenters,
          queryParameters: {'include_inactive': includeInactive},
        );
        return parseJsonList(res.data, CostCenter.fromJson);
      });

  /// GET /finance/cost-centers/{id}.
  Future<CostCenterDetail> costCenter(int id) => guard(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      Endpoints.financeCostCenter(id),
    );
    return CostCenterDetail.fromJson(res.data ?? const {});
  });

  /// POST /finance/cost-centers — a shared center. Keeps the detail of a 400:
  /// only the server's text says why a name or an amount was refused.
  Future<CostCenter> createCostCenter({
    required String name,
    required BudgetInput budget,
    bool isActive = true,
  }) => guardKeepingDetail(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      Endpoints.financeCostCenters,
      data: {'name': name, 'is_active': isActive, ...budget.toJson()},
    );
    return CostCenter.fromJson(res.data ?? const {});
  });

  /// PATCH /finance/cost-centers/{id} — name and active flag, and a 400 for a
  /// private center.
  Future<void> updateCostCenter(int id, {String? name, bool? isActive}) =>
      guardKeepingDetail(
        () => _dio.patch<dynamic>(
          Endpoints.financeCostCenter(id),
          data: {'name': ?name, 'is_active': ?isActive},
        ),
      );

  /// PATCH /finance/cost-centers/{id}/budgets — replaces the budget whole.
  Future<void> setBudget(int id, BudgetInput budget) => guardKeepingDetail(
    () => _dio.patch<dynamic>(
      Endpoints.financeCostCenterBudgets(id),
      data: budget.toJson(),
    ),
  );

  /// DELETE /finance/cost-centers/{id}. A center a ledger row or an active
  /// budget hold still names is refused, in words only the 400 carries.
  Future<void> deleteCostCenter(int id) => guardKeepingDetail(
    () => _dio.delete<dynamic>(Endpoints.financeCostCenter(id)),
  );

  /// POST …/members — adds [userId], or changes whether it may print.
  Future<void> setMember(int id, int userId, {required bool canPrint}) =>
      guardKeepingDetail(
        () => _dio.post<dynamic>(
          Endpoints.financeCostCenterMembers(id),
          data: {'user_id': userId, 'can_print': canPrint},
        ),
      );

  /// DELETE …/members/{userId}.
  Future<void> removeMember(int id, int userId) => guardKeepingDetail(
    () => _dio.delete<dynamic>(Endpoints.financeCostCenterMember(id, userId)),
  );

  /// GET /finance/transactions — every user's ledger, or [userId]'s.
  Future<WalletTransactionPage> transactions({
    required int limit,
    required int offset,
    int? userId,
  }) => guard(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      Endpoints.financeTransactions,
      queryParameters: {'limit': limit, 'offset': offset, 'user_id': ?userId},
    );
    return WalletTransactionPage.fromJson(res.data ?? const {});
  });

  /// POST /finance/rebuild-balance-ledger — recomputes the running balance of
  /// every ledger row, to repair values an old bug left wrong. It answers after the
  /// work, with the number of rows rebuilt.
  Future<int> rebuildLedger() => guardKeepingDetail(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      Endpoints.financeRebuildLedger,
    );
    return toIntOrNull(res.data?['transactions_rebuilt']) ?? 0;
  });

  /// POST …/deposit or …/withdraw: [amount] is positive either way, and the
  /// kind of adjustment is the route.
  Future<void> adjustWallet(
    int userId, {
    required double amount,
    required bool deposit,
    String? description,
    int? costCenterId,
  }) => guardKeepingDetail(
    () => _dio.post<dynamic>(
      deposit
          ? Endpoints.financeUserDeposit(userId)
          : Endpoints.financeUserWithdraw(userId),
      data: {
        'amount': amount,
        'description': ?description,
        'cost_center_id': ?costCenterId,
      },
    ),
  );

  /// POST /finance/transactions/manual — a print the server never saw.
  Future<void> addManualPrint({
    required int userId,
    required int costCenterId,
    required double amount,
    String? description,
  }) => guardKeepingDetail(
    () => _dio.post<dynamic>(
      Endpoints.financeTransactionsManual,
      data: {
        'user_id': userId,
        'cost_center_id': costCenterId,
        'amount': amount,
        'description': ?description,
      },
    ),
  );

  /// PATCH /finance/transactions/{id}. A row can be moved to another center but
  /// not taken off its center: the web cannot either, and sends no key for it.
  Future<void> editTransaction(
    int id, {
    int? userId,
    double? amount,
    String? description,
    int? costCenterId,
  }) => guardKeepingDetail(
    () => _dio.patch<dynamic>(
      Endpoints.financeTransaction(id),
      data: {
        'user_id': ?userId,
        'amount': ?amount,
        'description': ?description,
        'cost_center_id': ?costCenterId,
      },
    ),
  );

  /// DELETE /finance/transactions/{id} — voids the row and rebuilds the ledger.
  Future<void> deleteTransaction(int id) => guardKeepingDetail(
    () => _dio.delete<dynamic>(Endpoints.financeTransaction(id)),
  );
}
