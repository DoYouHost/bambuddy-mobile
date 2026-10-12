import 'package:app_util/app_util.dart';

import 'json_utils.dart';

/// `GET /finance/me/balance` (`WalletBalanceResponse`): what the account's
/// ledger adds up to. Informational — a print is limited by the cost center's
/// budget, never by this.
class WalletBalance {
  const WalletBalance({required this.balance, this.currency});

  factory WalletBalance.fromJson(Map<String, dynamic> json) => WalletBalance(
    balance: toDouble(json['balance']),
    currency: toStringOrNull(json['currency']),
  );

  final double balance;

  /// The server's code, which the screen does not use: money is shown in the
  /// currency of the server's settings, as everywhere else in the app.
  final String? currency;
}

/// What a ledger row records (`WalletTransactionResponse.transaction_type`). A kind a
/// newer server adds reads as [other] and is shown by its wire name.
enum WalletTransactionType {
  printCharge('print_charge'),
  deposit('deposit'),
  withdraw('withdraw'),
  manualAdjustment('manual_adjustment'),
  other('');

  const WalletTransactionType(this.wire);

  final String wire;

  static WalletTransactionType parse(Object? wire) => values.firstWhere(
    (t) => t.wire.isNotEmpty && t.wire == wire,
    orElse: () => other,
  );
}

/// How a print charge ended when it was not a clean finish — the server appends
/// `[aborted: …]`, `[failed: …]` or `[cancelled: …]` to the description of a
/// partial charge.
enum PartialPrint { aborted, failed, cancelled }

final _partialTag = RegExp(
  r'\[(aborted|failed|cancelled):\s*([^\]]*)\]',
  caseSensitive: false,
);

/// A print charge's description with the partial-print tag lifted out, as the web
/// does (`FinancePage.tsx::parsePrintChargeDescription`).
({PartialPrint? partial, String? text}) parsePrintCharge(String? description) {
  if (description == null) return (partial: null, text: null);
  final match = _partialTag.firstMatch(description);
  if (match == null) return (partial: null, text: description);
  final kind = PartialPrint.values.firstWhere(
    (p) => p.name == match.group(1)!.toLowerCase(),
  );
  final rest = description.replaceFirst(match.group(0)!, '').trim();
  return (partial: kind, text: rest.isEmpty ? null : rest);
}

/// One ledger row (`WalletTransactionResponse`). Amounts are signed: a charge
/// is negative, a deposit positive.
class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.amount,
    this.typeWire = '',
    this.costCenterId,
    this.balanceAfter,
    this.description,
    this.createdAt,
  });

  factory WalletTransaction.fromJson(Map<String, dynamic> json) =>
      WalletTransaction(
        id: toInt(json['id']),
        userId: toInt(json['user_id']),
        type: WalletTransactionType.parse(json['transaction_type']),
        typeWire: toStringOrNull(json['transaction_type']) ?? '',
        amount: toDouble(json['amount']),
        costCenterId: toIntOrNull(json['cost_center_id']),
        balanceAfter: toDoubleOrNull(json['balance_after']),
        description: toStringOrNull(json['description']),
        createdAt: dateTimeFromJson(json['created_at']),
      );

  final int id;
  final int userId;
  final WalletTransactionType type;

  /// The server's own name for the kind, which is all there is to show for one
  /// this app has no word for.
  final String typeWire;
  final double amount;
  final int? costCenterId;

  /// The balance once this row was applied; null when the server cannot say.
  final double? balanceAfter;
  final String? description;
  final DateTime? createdAt;
}

/// `WalletTransactionListResponse`: one page, and how many rows there are in all.
class WalletTransactionPage {
  const WalletTransactionPage({required this.items, required this.total});

  factory WalletTransactionPage.fromJson(Map<String, dynamic> json) =>
      WalletTransactionPage(
        items: parseJsonList(json['items'], WalletTransaction.fromJson),
        total: toInt(json['total']),
      );

  final List<WalletTransaction> items;
  final int total;
}
