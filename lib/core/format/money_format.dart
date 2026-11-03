import 'package:app_util/app_util.dart';

/// [amount] to two decimals with [symbol] placed as the currency puts it.
String formatMoneyValue(String symbol, double amount) =>
    formatMoney(symbol, amount.toStringAsFixed(2));
