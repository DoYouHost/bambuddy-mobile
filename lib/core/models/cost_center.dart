import 'package:app_util/app_util.dart';

/// What a cost center's budget counts, from `budget_mode`: spend since the
/// monthly reset, spend ever, or nothing (`finance.py::_budget_mode_and_limit`).
/// A mode a newer server adds reads as [none]: no limit shown, none enforced here.
enum CostCenterBudget {
  none,
  monthly,
  total;

  static CostCenterBudget parse(Object? wire) => switch (wire) {
    'monthly' => monthly,
    'total' => total,
    _ => none,
  };
}

/// One cost center as `GET /finance/cost-centers/mine` lists it
/// (`CostCenterSummaryResponse`): where a print job's cost is booked while the
/// server has billing on.
class CostCenter {
  const CostCenter({
    required this.id,
    required this.name,
    this.isPrivate = false,
    this.isActive = true,
    this.canPrint = true,
    this.budget = CostCenterBudget.none,
    this.budgetLimit,
    this.budgetUsed,
    this.budgetAvailable,
    this.totalBalance = 0,
    this.ownerUserId,
  });

  factory CostCenter.fromJson(Map<String, dynamic> json) => CostCenter(
    id: toInt(json['id']),
    name: toStringOrNull(json['name']) ?? '',
    isPrivate: json['is_private'] == true,
    // Defaults are the schema's: a row that omits them is a usable one.
    isActive: json['is_active'] != false,
    canPrint: json['can_print'] != false,
    budget: CostCenterBudget.parse(json['budget_mode']),
    budgetLimit: toDoubleOrNull(json['budget_limit']),
    budgetUsed: toDoubleOrNull(json['budget_used']),
    budgetAvailable: toDoubleOrNull(json['budget_available']),
    totalBalance: toDouble(json['total_balance']),
    ownerUserId: toIntOrNull(json['owner_user_id']),
  );

  final int id;
  final String name;

  /// The signed-in user's own center, which the web picks first.
  final bool isPrivate;
  final bool isActive;

  /// Whether this user may book prints here. A member without it still sees the
  /// center in the list.
  final bool canPrint;

  final CostCenterBudget budget;

  /// The cap for [budget], null with [CostCenterBudget.none].
  final double? budgetLimit;

  /// What [budgetLimit] has already spent in the budget's window (since the monthly
  /// reset, or ever). Null where there is no limit.
  final double? budgetUsed;

  /// What is left of [budgetLimit] after spend and the holds queued jobs have
  /// placed, never below zero (`finance.py::_to_cost_center_summary`). Null where
  /// there is no limit.
  final double? budgetAvailable;

  /// The account balance the center's ledger adds up to — not a budget; printing
  /// is limited by the budget alone.
  final double totalBalance;

  /// The user a private center belongs to; null for a shared one.
  final int? ownerUserId;

  /// What the web offers in the print form: active, and printable by this user.
  bool get usableForPrinting => isActive && canPrint;
}

/// The centers a print can be booked to, in the order the server lists them —
/// private first, then by name — which is also the order the web shows.
List<CostCenter> printableCostCenters(Iterable<CostCenter> all) => [
  for (final c in all)
    if (c.usableForPrinting) c,
];

/// The center a form selects when it has no choice of its own: the web takes the
/// user's private one, else the first (`PrintModal/index.tsx`).
CostCenter? defaultCostCenter(List<CostCenter> printable) {
  for (final c in printable) {
    if (c.isPrivate) return c;
  }
  return printable.isEmpty ? null : printable.first;
}

/// One user's standing in a shared center (`CostCenterMemberResponse`).
class CostCenterMember {
  const CostCenterMember({required this.userId, required this.canPrint});

  factory CostCenterMember.fromJson(Map<String, dynamic> json) =>
      CostCenterMember(
        userId: toInt(json['user_id']),
        canPrint: json['can_print'] != false,
      );

  final int userId;
  final bool canPrint;
}

/// `GET /finance/cost-centers/{id}`: a center and who may print with it.
class CostCenterDetail {
  const CostCenterDetail({required this.center, required this.members});

  factory CostCenterDetail.fromJson(Map<String, dynamic> json) =>
      CostCenterDetail(
        center: CostCenter.fromJson(json),
        members: parseJsonList(json['members'], CostCenterMember.fromJson),
      );

  final CostCenter center;
  final List<CostCenterMember> members;
}

/// A budget as an administrator sets it: a kind and, unless there is none, the
/// amount. The server stores at most one of the two figures.
class BudgetInput {
  const BudgetInput(this.kind, [this.amount]);

  static const none = BudgetInput(CostCenterBudget.none);

  final CostCenterBudget kind;
  final double? amount;

  /// Body for `PATCH …/budgets`: only the figure that applies. A body with
  /// neither is how the server is told to drop the budget.
  Map<String, dynamic> toJson() => switch (kind) {
    CostCenterBudget.monthly => {'monthly_budget': amount},
    CostCenterBudget.total => {'total_budget': amount},
    CostCenterBudget.none => const {},
  };
}
