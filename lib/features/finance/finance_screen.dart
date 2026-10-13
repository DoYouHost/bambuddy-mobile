import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/datetime_format.dart';
import '../../core/models/cost_center.dart';
import '../../core/models/current_user.dart' show Permissions;
import '../../core/models/wallet.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/currency_symbol.dart';
import '../common/dash_async.dart';
import '../common/dash_input.dart';
import '../common/dash_progress_bar.dart';
import '../stats/stats_providers.dart' show statsUsersProvider;
import 'finance_forms.dart';
import 'finance_providers.dart';

/// The web's Finance page, personal view: the account balance, the cost centers
/// the user may book prints to with what is left of each budget, and their own
/// ledger. Read-only — everything that changes money is an administrator's.
class FinanceScreen extends ConsumerStatefulWidget {
  const FinanceScreen({super.key});

  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends ConsumerState<FinanceScreen> {
  /// Both filters narrow the rows already loaded, as on the web: the ledger
  /// endpoint filters on neither.
  WalletTransactionType? _type;
  int? _costCenterId;

  /// The administrator's view, which the web offers beside the personal one to
  /// whoever holds any of the finance permissions.
  bool _admin = false;

  Future<void> _refresh(LedgerNotifier ledger) async {
    ref
      ..invalidate(walletBalanceProvider)
      ..invalidate(myCostCentersProvider)
      ..invalidate(allCostCentersProvider);
    await ledger.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    bool may(String permission) =>
        ref.watch(identifiedPermissionProvider(permission));
    final canReadAll = may(Permissions.costCentersReadAll);
    final canCreate = may(Permissions.costCentersCreate);
    final canModify = may(Permissions.costCentersModify);
    final hasAdmin = canReadAll || canCreate || canModify;
    final admin = _admin && hasAdmin;
    // Every user's ledger needs `read_all` of its own; without it the admin view
    // keeps the user's own, as the web does.
    final allLedger = admin && canReadAll;
    final LedgerNotifier ledger = allLedger
        ? ref.watch(adminTransactionsProvider.notifier)
        : ref.watch(financeTransactionsProvider.notifier);
    final transactions = allLedger
        ? ref.watch(adminTransactionsProvider)
        : ref.watch(financeTransactionsProvider);
    final centers = admin
        ? ref.watch(allCostCentersProvider)
        : ref.watch(myCostCentersProvider);
    final Map<int, String> names = {
      if (admin)
        for (final u in ref.watch(statsUsersProvider).valueOrNull ?? const [])
          u.id: u.username,
    };
    final canPickUsers = names.isNotEmpty;

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(context, title: l10n.financeTitle),
        body: RefreshIndicator(
          onRefresh: () => _refresh(ledger),
          child: NotificationListener<ScrollNotification>(
            // The next page is fetched before the user reaches the end.
            onNotification: (n) {
              if (n.metrics.pixels > n.metrics.maxScrollExtent - 400) {
                ledger.loadMore();
              }
              return false;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: screenListPadding(context),
              children: [
                if (hasAdmin) ...[
                  logTag(
                    'finance.view_mode',
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                          value: false,
                          label: Text(l10n.financePersonalView),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text(l10n.financeAdminView),
                        ),
                      ],
                      selected: {admin},
                      onSelectionChanged: (v) => setState(() {
                        _admin = v.single;
                        _costCenterId = null;
                      }),
                    ),
                  ),
                  const SizedBox(height: DashSpace.lg),
                ],
                if (admin) ...[
                  Row(
                    spacing: DashSpace.md,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (canCreate)
                        _AdminAction(
                          id: 'finance.create_center',
                          icon: Icons.add,
                          label: l10n.financeButtonNewCenter,
                          onPressed: () => openCostCenterForm(context),
                        ),
                      if (canModify && canPickUsers) ...[
                        _AdminAction(
                          id: 'finance.adjust_wallet',
                          icon: Icons.swap_vert,
                          label: l10n.financeButtonWallet,
                          onPressed: () => openWalletAdjust(context),
                        ),
                        _AdminAction(
                          id: 'finance.manual_print',
                          icon: Icons.receipt_long_outlined,
                          label: l10n.financeButtonManualPrint,
                          onPressed: () => openManualPrint(context),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: DashSpace.xl),
                ],
                const _BalanceCard(),
                const SizedBox(height: DashSpace.xl),
                _SectionHeader(
                  title: admin
                      ? l10n.financeCostCenters
                      : l10n.financeMyCostCenters,
                ),
                dashAsyncStrip(
                  context,
                  centers,
                  failureMessage: l10n.financeLoadFailed,
                  data: (list) => list.isEmpty
                      ? Text(l10n.financeNoCostCenters, style: t.labelSoft)
                      : Column(
                          children: [
                            for (final c in list)
                              _CostCenterTile(
                                center: c,
                                owner: admin
                                    ? (c.isPrivate
                                          ? names[c.ownerUserId] ??
                                                l10n.financeUserWithId(
                                                  c.ownerUserId ?? 0,
                                                )
                                          : l10n.financeShared)
                                    : null,
                                canModify: admin && canModify,
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: DashSpace.xl),
                _SectionHeader(
                  title: allLedger
                      ? l10n.financeTransactions
                      : l10n.financeRecentTransactions,
                ),
                _filters(l10n, centers.valueOrNull ?? const []),
                const SizedBox(height: DashSpace.md),
                dashAsyncStrip(
                  context,
                  transactions,
                  failureMessage: l10n.financeLoadFailed,
                  data: (state) => _ledger(
                    l10n,
                    t,
                    state,
                    ledger,
                    {for (final c in centers.valueOrNull ?? const []) c.id: c},
                    userNames: allLedger ? names : null,
                    canModify: admin && canModify,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filters(AppLocalizations l10n, List<CostCenter> centers) {
    return Column(
      children: [
        dashAnyOrOne<WalletTransactionType>(
          context,
          id: 'finance.type',
          label: Text(l10n.financeType),
          anyLabel: l10n.financeAllTypes,
          selected: _type,
          options: [
            (WalletTransactionType.printCharge, l10n.financeTypePrintCharge),
            (WalletTransactionType.deposit, l10n.financeTypeDeposit),
            (WalletTransactionType.withdraw, l10n.financeTypeWithdraw),
            (
              WalletTransactionType.manualAdjustment,
              l10n.financeTypeAdjustment,
            ),
          ],
          onPick: (v) => setState(() => _type = v),
        ),
        const SizedBox(height: DashSpace.md),
        dashAnyOrOne<int>(
          context,
          id: 'finance.cost_center',
          label: Text(l10n.financeCostCenter),
          anyLabel: l10n.financeAllCostCenters,
          selected: _costCenterId,
          options: [for (final c in centers) (c.id, c.name)],
          onPick: (v) => setState(() => _costCenterId = v),
        ),
      ],
    );
  }

  Widget _ledger(
    AppLocalizations l10n,
    DashTokens t,
    FinanceTransactions state,
    LedgerNotifier ledger,
    Map<int, CostCenter> centers, {
    Map<int, String>? userNames,
    bool canModify = false,
  }) {
    if (state.items.isEmpty) {
      return Text(l10n.financeNoTransactions, style: t.labelSoft);
    }
    final shown = [
      for (final tx in state.items)
        if ((_type == null || tx.type == _type) &&
            (_costCenterId == null || tx.costCenterId == _costCenterId))
          tx,
    ];
    return Column(
      children: [
        if (shown.isEmpty)
          Text(l10n.financeNoTransactionsForFilter, style: t.labelSoft)
        else
          for (final tx in shown)
            _TransactionTile(
              transaction: tx,
              centerName: centers[tx.costCenterId]?.name,
              userName: userNames == null
                  ? null
                  : userNames[tx.userId] ?? l10n.financeUserWithId(tx.userId),
              canModify: canModify,
            ),
        const SizedBox(height: DashSpace.md),
        if (state.loadingMore)
          const DashSpinner(size: 22)
        else if (state.hasMore)
          logTag(
            'finance.load_more',
            TextButton(
              onPressed: ledger.loadMore,
              child: Text(
                '${l10n.financeLoadMore} · '
                '${l10n.financeShowing(state.items.length, state.total)}',
              ),
            ),
          )
        else
          Text(
            l10n.financeShowing(state.items.length, state.total),
            style: t.monoLabel,
          ),
      ],
    );
  }
}

/// One of the administrator's shortcuts: a quiet button with the icon over a short
/// label, so three of them share a row instead of taking three.
class _AdminAction extends StatelessWidget {
  const _AdminAction({
    required this.id,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final String id;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Expanded(
    child: logTag(
      id,
      OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: DashSpace.sm,
            vertical: DashSpace.lg,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DashSpace.sm,
          children: [
            Icon(icon, size: 20),
            Text(label, textAlign: TextAlign.center, maxLines: 2),
          ],
        ),
      ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: DashSpace.md),
    child: Text(title, style: DashTokens.of(context).titleMd),
  );
}

/// `-$1.50`: the sign leads, the symbol follows it, two decimals.
String _money(String currency, double amount, {bool plus = false}) {
  final sign = amount < 0 ? '-' : (plus && amount > 0 ? '+' : '');
  return '$sign${formatMoney(currency, amount.abs().toStringAsFixed(2))}';
}

class _BalanceCard extends ConsumerWidget {
  const _BalanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final currency = ref.watch(currencySymbolProvider);
    return Container(
      padding: const EdgeInsets.all(DashSpace.lg),
      decoration: t.cardBox,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.financeBalance, style: t.labelSoft),
          const SizedBox(height: DashSpace.xs),
          dashAsyncStrip(
            context,
            ref.watch(walletBalanceProvider),
            padding: EdgeInsets.zero,
            failureMessage: l10n.financeLoadFailed,
            data: (wallet) => Align(
              alignment: Alignment.centerLeft,
              child: Text(_money(currency, wallet.balance), style: t.display),
            ),
          ),
        ],
      ),
    );
  }
}

class _CostCenterTile extends ConsumerWidget {
  const _CostCenterTile({
    required this.center,
    this.owner,
    this.canModify = false,
  });

  final CostCenter center;

  /// Whose it is — a user's name for a private center, "Shared" for the rest.
  /// Only the administrator's list says.
  final String? owner;

  final bool canModify;

  Future<void> _delete(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await confirmDialog(
      context,
      title: l10n.financeDeleteCostCenter,
      message: l10n.financeConfirmDeleteCostCenter(center.name),
      confirmLabel: l10n.financeDelete,
      destructive: true,
      id: 'finance.delete_center',
    );
    if (!confirmed || !context.mounted) return;
    await runFinanceWrite(
      context,
      action: 'finance.delete_center',
      done: l10n.financeCostCenterDeleted,
      write: (repo) => repo.deleteCostCenter(center.id),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final currency = ref.watch(currencySymbolProvider);
    final limit = center.budgetLimit;
    final available = center.budgetAvailable;
    final budgeted = limit != null && available != null;
    // The share already spent: what the bar fills, and what turns it red.
    // A limit of 0 is how an administrator stops a center printing: nothing is
    // left of it, which a zero division would otherwise draw as an untouched bar.
    final spent = !budgeted
        ? 0.0
        : limit <= 0
        ? 1.0
        : ((limit - available) / limit).clamp(0.0, 1.0);
    return Container(
      margin: const EdgeInsets.only(bottom: DashSpace.sm),
      padding: const EdgeInsets.all(DashSpace.lg),
      decoration: BoxDecoration(
        color: t.subCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.subCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  center.isPrivate
                      ? l10n.queueCostCenterPersonal(center.name)
                      : center.name,
                  style: t.bodyBold,
                ),
              ),
              if (canModify)
                logTag(
                  'finance.center_menu',
                  PopupMenuButton<String>(
                    onSelected: (v) => switch (v) {
                      'edit' => openCostCenterForm(context, existing: center),
                      'members' => openCostCenterMembers(context, center),
                      _ => _delete(context),
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: logTag(
                          'finance.center_menu.edit',
                          Text(l10n.financeEdit),
                        ),
                      ),
                      // A private center answers 400 to a membership change and
                      // to a delete; offering them would only lead to a refusal.
                      if (!center.isPrivate) ...[
                        PopupMenuItem(
                          value: 'members',
                          child: logTag(
                            'finance.center_menu.members',
                            Text(l10n.financeMembers),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: logTag(
                            'finance.center_menu.delete',
                            Text(l10n.financeDelete),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
          if (owner != null) ...[
            const SizedBox(height: DashSpace.xs),
            Text(owner!, style: t.labelSoft),
          ],
          const SizedBox(height: DashSpace.xs),
          Text(
            l10n.financeAccountBalance(_money(currency, center.totalBalance)),
            style: t.labelSoft,
          ),
          const SizedBox(height: DashSpace.sm),
          Text(
            budgeted
                ? '${_money(currency, available)} / ${_money(currency, limit)}'
                : l10n.financeUnlimited,
            style: t.body,
          ),
          const SizedBox(height: DashSpace.xs),
          Text(switch (center.budget) {
            CostCenterBudget.monthly => l10n.financeBudgetMonthly,
            CostCenterBudget.total => l10n.financeBudgetTotal,
            CostCenterBudget.none => l10n.financeBudgetNone,
          }, style: t.labelSoft),
          if (budgeted) ...[
            const SizedBox(height: DashSpace.sm),
            DashProgressBar(
              value: spent,
              height: 6,
              color: spent >= 1 ? t.dangerInk : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _TransactionTile extends ConsumerWidget {
  const _TransactionTile({
    required this.transaction,
    this.centerName,
    this.userName,
    this.canModify = false,
  });

  final WalletTransaction transaction;
  final String? centerName;

  /// Whose row it is, in the administrator's ledger of every user.
  final String? userName;

  final bool canModify;

  Future<void> _delete(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await confirmDialog(
      context,
      title: l10n.financeDeleteTransaction,
      message: l10n.financeDeleteTransactionConfirm,
      confirmLabel: l10n.financeDelete,
      destructive: true,
      id: 'finance.delete_transaction',
    );
    if (!confirmed || !context.mounted) return;
    await runFinanceWrite(
      context,
      action: 'finance.delete_transaction',
      done: l10n.financeTransactionDeleted,
      write: (repo) => repo.deleteTransaction(transaction.id),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final currency = ref.watch(currencySymbolProvider);
    final tx = transaction;
    final parsed = tx.type == WalletTransactionType.printCharge
        ? parsePrintCharge(tx.description)
        : (partial: null, text: tx.description);
    final when = tx.createdAt;
    return Container(
      margin: const EdgeInsets.only(bottom: DashSpace.sm),
      padding: const EdgeInsets.all(DashSpace.lg),
      decoration: BoxDecoration(
        color: t.subCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.subCardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: DashSpace.sm,
                  runSpacing: DashSpace.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      tx.type == WalletTransactionType.other
                          ? tx.typeWire
                          : _typeLabel(l10n, tx.type),
                      style: t.bodyBold,
                    ),
                    if (parsed.partial case final partial?)
                      Text(
                        _partialLabel(l10n, partial),
                        style: t.micro.copyWith(color: t.accentOrangeInk),
                      ),
                  ],
                ),
                const SizedBox(height: DashSpace.xs),
                Text(
                  [
                    if (when != null)
                      DateTimeFormats.of(context).dateTime(when),
                    ?userName,
                    centerName ?? '-',
                  ].join(' • '),
                  style: t.labelSoft,
                ),
                if (parsed.text != null) ...[
                  const SizedBox(height: DashSpace.xs),
                  Text(parsed.text!, style: t.body),
                ],
              ],
            ),
          ),
          const SizedBox(width: DashSpace.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _money(currency, tx.amount, plus: true),
                style: t.bodyBold.copyWith(
                  color: tx.amount == 0
                      ? null
                      : tx.amount > 0
                      ? t.accentGreenInk
                      : t.dangerInk,
                ),
              ),
              if (tx.balanceAfter != null) ...[
                const SizedBox(height: DashSpace.xs),
                Text(
                  l10n.financeBalanceAfter(_money(currency, tx.balanceAfter!)),
                  style: t.labelSoft,
                ),
              ],
            ],
          ),
          if (canModify)
            logTag(
              'finance.transaction_menu',
              PopupMenuButton<String>(
                onSelected: (v) => v == 'edit'
                    ? openTransactionEdit(context, tx)
                    : _delete(context),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: logTag(
                      'finance.transaction_menu.edit',
                      Text(l10n.financeEdit),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: logTag(
                      'finance.transaction_menu.delete',
                      Text(l10n.financeDelete),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String _typeLabel(AppLocalizations l10n, WalletTransactionType type) =>
    switch (type) {
      WalletTransactionType.printCharge => l10n.financeTypePrintCharge,
      WalletTransactionType.deposit => l10n.financeTypeDeposit,
      WalletTransactionType.withdraw => l10n.financeTypeWithdraw,
      WalletTransactionType.manualAdjustment => l10n.financeTypeAdjustment,
      WalletTransactionType.other => '',
    };

String _partialLabel(AppLocalizations l10n, PartialPrint partial) =>
    switch (partial) {
      PartialPrint.aborted => l10n.financePartialAborted,
      PartialPrint.failed => l10n.financePartialFailed,
      PartialPrint.cancelled => l10n.financePartialCancelled,
    };
