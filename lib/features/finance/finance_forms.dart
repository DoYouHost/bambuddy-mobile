import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:app_util/app_util.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/archive_stats.dart';
import '../../core/models/cost_center.dart';
import '../../core/models/wallet.dart';
import '../../core/theme/dash_theme.dart';
import '../../data/finance_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/server_refusal.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import '../stats/stats_providers.dart' show statsUsersProvider;
import 'finance_providers.dart';

/// What an administrator's write answers with, in words. Everything else the
/// server says about a refused center, member or ledger row is quoted: these
/// are the two that read as a rule rather than as a reason.
final _refusals = <RefusalRule>[
  (
    ['cannot be deleted while transactions reference'],
    (l10n) => l10n.financeDeleteBlockedTransactions,
  ),
  (
    ['cannot be deleted while active budget reservations'],
    (l10n) => l10n.financeDeleteBlockedReservations,
  ),
];

/// Forgets what finance has read, so every list on screen asks again.
void refreshFinance(ProviderContainer container) => container
  ..invalidate(allCostCentersProvider)
  ..invalidate(myCostCentersProvider)
  ..invalidate(walletBalanceProvider)
  ..invalidate(printableCostCentersProvider)
  ..invalidate(financeTransactionsProvider)
  ..invalidate(adminTransactionsProvider);

/// Runs one administrator write. On success finance is re-read and [done] shown;
/// on a refusal the server's own reason is. Answers whether it went through.
Future<bool> runFinanceWrite(
  BuildContext context, {
  required String action,
  required Future<void> Function(FinanceRepository repo) write,
  String? done,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    await write(container.read(financeRepositoryProvider));
    refreshFinance(container);
    if (done != null) messenger.snack(done);
    return true;
  } on AppApiException catch (e) {
    showApiFailure(
      messenger,
      e,
      l10n,
      action: action,
      message: serverRefusal(l10n, e, _refusals),
    );
    return false;
  }
}

/// The administrator's repair of the ledger's running balances, which the web
/// keeps behind a button in Settings. Asks first: it rewrites every row's balance.
Future<void> openRebuildLedger(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await confirmDialog(
    context,
    title: l10n.financeRebuildLedger,
    message: l10n.financeRebuildLedgerConfirm,
    confirmLabel: l10n.financeRebuildLedgerRun,
    id: 'finance.rebuild_ledger',
  );
  if (!confirmed || !context.mounted) return;
  await runFinanceWrite(
    context,
    action: 'finance.rebuild_ledger',
    done: l10n.financeLedgerRebuilt,
    write: (repo) async {
      await repo.rebuildLedger();
    },
  );
}

/// A sheet holding one form, scrolled with the keyboard in mind.
Widget _formSheet({
  required String id,
  required String title,
  required List<Widget> children,
  double initialSize = 0.85,
}) => logTag(
  id,
  DraggableSheetSurface(
    initialSize: initialSize,
    builder: (context, controller) {
      final t = DashTokens.of(context);
      return ListView(
        controller: controller,
        padding: EdgeInsets.fromLTRB(
          DashSpace.gutter,
          0,
          DashSpace.gutter,
          DashSpace.xl + MediaQuery.of(context).viewInsets.bottom,
        ),
        children: [
          Text(title, style: t.display),
          const SizedBox(height: DashSpace.md),
          ...children,
        ],
      );
    },
  ),
);

Widget _gap() => const SizedBox(height: DashSpace.md);

/// The amount field the money forms share: a decimal, never negative and
/// required unless [optional] — the sign belongs to the kind of write.
class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.id,
    this.allowZero = true,
    this.optional = false,
  });

  final TextEditingController controller;
  final String id;

  /// An empty box is a valid answer: a budget the web leaves unset means none.
  final bool optional;

  /// A deposit of nothing is no deposit.
  final bool allowZero;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    return TextFormField(
      controller: controller,
      style: t.body,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: dashDecoration(t, labelText: l10n.financeAmount),
      validator: (v) {
        if ((v ?? '').trim().isEmpty) {
          return optional ? null : l10n.inventoryFieldRequired;
        }
        final n = parseUserDecimal(v);
        if (n == null) return l10n.financeAmountInvalid;
        if (n < 0) return l10n.financeAmountInvalid;
        if (!allowZero && n == 0) return l10n.financeAmountPositive;
        return null;
      },
    ).tagged(id);
  }
}

class _DescriptionField extends StatelessWidget {
  const _DescriptionField({required this.controller, required this.id});

  final TextEditingController controller;
  final String id;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextFormField(
      controller: controller,
      style: DashTokens.of(context).body,
      decoration: dashDecoration(
        DashTokens.of(context),
        labelText: l10n.financeDescription,
      ),
    ).tagged(id);
  }
}

/// A user from the server's list, as a filterable select. The ids of its rows
/// are one, since a name is the user's own words.
Widget _userPicker(
  BuildContext context,
  WidgetRef ref, {
  required String id,
  required int? selected,
  required ValueChanged<int?> onPick,
  String? errorText,
  Set<int> except = const {},
}) {
  final l10n = AppLocalizations.of(context);
  final users = [
    for (final u in ref.watch(statsUsersProvider).value ?? <UserSummary>[])
      if (!except.contains(u.id)) u,
  ];
  return dashCombo<int>(
    context,
    id: id,
    label: Text(l10n.financeUser),
    errorText: errorText,
    filterable: true,
    initialSelection: users.any((u) => u.id == selected) ? selected : null,
    onSelected: onPick,
    entries: [
      for (final u in users)
        DropdownMenuEntry(
          value: u.id,
          label: u.username,
          labelWidget: logTag('$id.option', Text(u.username)),
        ),
    ],
  );
}

Widget _centerPicker(
  BuildContext context, {
  required String id,
  required List<CostCenter> centers,
  required int? selected,
  required ValueChanged<int?> onPick,
  String? errorText,
}) {
  final l10n = AppLocalizations.of(context);
  String name(CostCenter c) =>
      c.isPrivate ? l10n.queueCostCenterPersonal(c.name) : c.name;
  return dashCombo<int>(
    context,
    id: id,
    label: Text(l10n.financeCostCenter),
    errorText: errorText,
    filterable: true,
    initialSelection: centers.any((c) => c.id == selected) ? selected : null,
    onSelected: onPick,
    entries: [
      for (final c in centers)
        DropdownMenuEntry(
          value: c.id,
          label: name(c),
          labelWidget: logTag('$id.option', Text(name(c))),
        ),
    ],
  );
}

Widget _saveButton(
  BuildContext context, {
  required String id,
  required String label,
  required bool saving,
  required VoidCallback onPressed,
}) => SizedBox(
  width: double.infinity,
  child: FilledButton(
    onPressed: saving ? null : onPressed,
    child: saving
        ? DashSpinner(size: 20, color: DashTokens.of(context).onAccent)
        : Text(label),
  ).tagged(id),
);

// --- Create or edit a cost center ---

/// A shared center to create, or [existing] to edit. A private one edits only
/// its budget: its name and standing are the server's, and it answers 400 to
/// both.
Future<void> openCostCenterForm(BuildContext context, {CostCenter? existing}) =>
    dashSurfaceSheet<void>(
      context,
      builder: (_) => _CostCenterForm(existing: existing),
    );

class _CostCenterForm extends ConsumerStatefulWidget {
  const _CostCenterForm({this.existing});

  final CostCenter? existing;

  @override
  ConsumerState<_CostCenterForm> createState() => _CostCenterFormState();
}

class _CostCenterFormState extends ConsumerState<_CostCenterForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _amount = TextEditingController(
    text: widget.existing?.budgetLimit == null
        ? ''
        : _plain(widget.existing!.budgetLimit!),
  );
  // The web starts a new center on a monthly budget.
  late CostCenterBudget _kind =
      widget.existing?.budget ?? CostCenterBudget.monthly;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  /// `100` rather than `100.0`.
  static String _plain(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  BudgetInput get _budget => _kind == CostCenterBudget.none
      ? BudgetInput.none
      // An empty amount is no budget, which is what the web sends too.
      : parseUserDecimal(_amount.text) == null
      ? BudgetInput.none
      : BudgetInput(_kind, parseUserDecimal(_amount.text));

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final existing = widget.existing;
    final name = _name.text.trim();
    setState(() => _saving = true);
    final ok = await runFinanceWrite(
      context,
      action: 'finance_form.save_center',
      done: existing == null
          ? l10n.financeCostCenterCreated
          : l10n.financeCostCenterUpdated,
      write: (repo) async {
        if (existing == null) {
          await repo.createCostCenter(name: name, budget: _budget);
          return;
        }
        // A personal center's name field is locked, so only a shared one differs.
        if (name != existing.name) {
          await repo.updateCostCenter(existing.id, name: name);
        }
        await repo.setBudget(existing.id, _budget);
      },
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final existing = widget.existing;
    final editing = existing != null;
    return _formSheet(
      id: 'sheet.cost_center_form',
      title: editing
          ? l10n.financeEditCostCenter
          : l10n.financeCreateCostCenter,
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                enabled: existing?.isPrivate != true,
                style: t.body,
                maxLength: 150,
                decoration: dashDecoration(
                  t,
                  labelText: l10n.financeCostCenterName,
                ),
                validator: (v) => (v ?? '').trim().isEmpty
                    ? l10n.financeCostCenterNameRequired
                    : null,
              ).tagged('finance_form.name'),
              _gap(),
              dashCombo<CostCenterBudget>(
                context,
                id: 'finance_form.budget_kind',
                label: Text(l10n.financeBudgetType),
                initialSelection: _kind,
                onSelected: (v) =>
                    setState(() => _kind = v ?? CostCenterBudget.none),
                entries: [
                  for (final (kind, label) in [
                    (CostCenterBudget.monthly, l10n.financeBudgetMonthly),
                    (CostCenterBudget.total, l10n.financeBudgetTotal),
                    (CostCenterBudget.none, l10n.financeBudgetNone),
                  ])
                    DropdownMenuEntry(
                      value: kind,
                      label: label,
                      labelWidget: logTag(
                        'finance_form.budget_kind.${kind.name}',
                        Text(label),
                      ),
                    ),
                ],
              ),
              if (_kind != CostCenterBudget.none) ...[
                _gap(),
                _AmountField(
                  controller: _amount,
                  id: 'finance_form.budget',
                  optional: true,
                ),
              ],
              if (existing?.isPrivate == true) ...[
                _gap(),
                Text(l10n.financePrivateBudgetOnly, style: t.labelSoft),
              ],
              const SizedBox(height: DashSpace.xl),
              _saveButton(
                context,
                id: 'finance_form.save_center',
                label: editing ? l10n.financeSave : l10n.financeCreate,
                saving: _saving,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// --- Adjust a wallet ---

Future<void> openWalletAdjust(BuildContext context) =>
    dashSurfaceSheet<void>(context, builder: (_) => const _WalletAdjustForm());

class _WalletAdjustForm extends ConsumerStatefulWidget {
  const _WalletAdjustForm();

  @override
  ConsumerState<_WalletAdjustForm> createState() => _WalletAdjustFormState();
}

class _WalletAdjustFormState extends ConsumerState<_WalletAdjustForm> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  int? _userId;
  int? _centerId;
  bool _deposit = true;
  bool _userMissing = false;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final valid = _formKey.currentState!.validate();
    setState(() => _userMissing = _userId == null);
    if (!valid || _userId == null) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    final description = _description.text.trim();
    final ok = await runFinanceWrite(
      context,
      action: 'finance_form.save_adjust',
      done: _deposit ? l10n.financeDepositDone : l10n.financeWithdrawDone,
      write: (repo) => repo.adjustWallet(
        _userId!,
        amount: parseUserDecimal(_amount.text)!,
        deposit: _deposit,
        description: description.isEmpty ? null : description,
        costCenterId: _centerId,
      ),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final centers = ref.watch(allCostCentersProvider).value ?? const [];
    return _formSheet(
      id: 'sheet.wallet_adjust',
      title: l10n.financeAdjustWallet,
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _userPicker(
                context,
                ref,
                id: 'finance_form.user',
                selected: _userId,
                errorText: _userMissing ? l10n.financeUserRequired : null,
                onPick: (v) => setState(() {
                  _userId = v;
                  _userMissing = false;
                }),
              ),
              _gap(),
              dashCombo<bool>(
                context,
                id: 'finance_form.adjust_kind',
                label: Text(l10n.financeType),
                initialSelection: _deposit,
                onSelected: (v) => setState(() => _deposit = v ?? true),
                entries: [
                  DropdownMenuEntry(
                    value: true,
                    label: l10n.financeTypeDeposit,
                    labelWidget: logTag(
                      'finance_form.adjust_kind.deposit',
                      Text(l10n.financeTypeDeposit),
                    ),
                  ),
                  DropdownMenuEntry(
                    value: false,
                    label: l10n.financeTypeWithdraw,
                    labelWidget: logTag(
                      'finance_form.adjust_kind.withdraw',
                      Text(l10n.financeTypeWithdraw),
                    ),
                  ),
                ],
              ),
              _gap(),
              _AmountField(
                controller: _amount,
                id: 'finance_form.amount',
                allowZero: false,
              ),
              _gap(),
              dashAnyOrOne<int>(
                context,
                id: 'finance_form.center',
                label: Text(l10n.financeCostCenter),
                anyLabel: l10n.financeNoCostCenter,
                selected: _centerId,
                options: [for (final c in centers) (c.id, c.name)],
                onPick: (v) => setState(() => _centerId = v),
              ),
              _gap(),
              _DescriptionField(
                controller: _description,
                id: 'finance_form.description',
              ),
              const SizedBox(height: DashSpace.xl),
              _saveButton(
                context,
                id: 'finance_form.save_adjust',
                label: l10n.financeApplyAdjustment,
                saving: _saving,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// --- A manual print charge ---

Future<void> openManualPrint(BuildContext context) =>
    dashSurfaceSheet<void>(context, builder: (_) => const _ManualPrintForm());

class _ManualPrintForm extends ConsumerStatefulWidget {
  const _ManualPrintForm();

  @override
  ConsumerState<_ManualPrintForm> createState() => _ManualPrintFormState();
}

class _ManualPrintFormState extends ConsumerState<_ManualPrintForm> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  int? _userId;
  int? _centerId;
  bool _missing = false;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final valid = _formKey.currentState!.validate();
    setState(() => _missing = _userId == null || _centerId == null);
    if (!valid || _userId == null || _centerId == null) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    final description = _description.text.trim();
    final ok = await runFinanceWrite(
      context,
      action: 'finance_form.save_manual',
      done: l10n.financeManualPrintDone,
      write: (repo) => repo.addManualPrint(
        userId: _userId!,
        costCenterId: _centerId!,
        amount: parseUserDecimal(_amount.text)!.abs(),
        description: description.isEmpty ? null : description,
      ),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final centers = ref.watch(allCostCentersProvider).value ?? const [];
    return _formSheet(
      id: 'sheet.manual_print',
      title: l10n.financeAddManualPrint,
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _userPicker(
                context,
                ref,
                id: 'finance_form.user',
                selected: _userId,
                errorText: _missing && _userId == null
                    ? l10n.financeUserRequired
                    : null,
                onPick: (v) => setState(() => _userId = v),
              ),
              _gap(),
              _centerPicker(
                context,
                id: 'finance_form.center',
                centers: centers,
                selected: _centerId,
                errorText: _missing && _centerId == null
                    ? l10n.financeCostCenterRequired
                    : null,
                onPick: (v) => setState(() => _centerId = v),
              ),
              _gap(),
              _AmountField(
                controller: _amount,
                id: 'finance_form.amount',
                allowZero: false,
              ),
              _gap(),
              _DescriptionField(
                controller: _description,
                id: 'finance_form.description',
              ),
              const SizedBox(height: DashSpace.xl),
              _saveButton(
                context,
                id: 'finance_form.save_manual',
                label: l10n.financeAddCharge,
                saving: _saving,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// --- Edit a ledger row ---

Future<void> openTransactionEdit(
  BuildContext context,
  WalletTransaction transaction,
) => dashSurfaceSheet<void>(
  context,
  builder: (_) => _TransactionEditForm(transaction: transaction),
);

class _TransactionEditForm extends ConsumerStatefulWidget {
  const _TransactionEditForm({required this.transaction});

  final WalletTransaction transaction;

  @override
  ConsumerState<_TransactionEditForm> createState() =>
      _TransactionEditFormState();
}

class _TransactionEditFormState extends ConsumerState<_TransactionEditForm> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: widget.transaction.amount.toString(),
  );
  late final _description = TextEditingController(
    text: widget.transaction.description ?? '',
  );
  late int? _userId = widget.transaction.userId;
  late int? _centerId = widget.transaction.costCenterId;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final tx = widget.transaction;
    final amount = parseUserDecimal(_amount.text);
    final description = _description.text.trim();
    setState(() => _saving = true);
    // Only what changed goes out: the server marks any description it is sent
    // as an admin edit, and rebuilds the ledger for each.
    final ok = await runFinanceWrite(
      context,
      action: 'finance_form.save_transaction',
      done: l10n.financeTransactionEdited,
      write: (repo) => repo.editTransaction(
        tx.id,
        userId: _userId != tx.userId ? _userId : null,
        costCenterId: _centerId != tx.costCenterId ? _centerId : null,
        amount: amount != null && amount != tx.amount ? amount : null,
        description: description.isNotEmpty && description != tx.description
            ? description
            : null,
      ),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final centers = ref.watch(allCostCentersProvider).value ?? const [];
    final t = DashTokens.of(context);
    return _formSheet(
      id: 'sheet.transaction_edit',
      title: l10n.financeEditTransaction,
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _userPicker(
                context,
                ref,
                id: 'finance_form.user',
                selected: _userId,
                onPick: (v) => setState(() => _userId = v),
              ),
              _gap(),
              _centerPicker(
                context,
                id: 'finance_form.center',
                centers: centers,
                selected: _centerId,
                onPick: (v) => setState(() => _centerId = v),
              ),
              _gap(),
              // A ledger amount is signed, unlike every other money field here.
              TextFormField(
                controller: _amount,
                style: t.body,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: dashDecoration(t, labelText: l10n.financeAmount),
                validator: (v) => parseUserDecimal(v) == null
                    ? l10n.financeAmountInvalid
                    : null,
              ).tagged('finance_form.amount'),
              _gap(),
              _DescriptionField(
                controller: _description,
                id: 'finance_form.description',
              ),
              const SizedBox(height: DashSpace.xl),
              _saveButton(
                context,
                id: 'finance_form.save_transaction',
                label: l10n.financeSave,
                saving: _saving,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// --- Who may print with a shared center ---

final costCenterDetailProvider = FutureProvider.autoDispose
    .family<CostCenterDetail, int>(
      (ref, id) => ref.watch(financeRepositoryProvider).costCenter(id),
    );

Future<void> openCostCenterMembers(BuildContext context, CostCenter center) =>
    dashSurfaceSheet<void>(
      context,
      builder: (_) => _MembersSheet(center: center),
    );

class _MembersSheet extends ConsumerStatefulWidget {
  const _MembersSheet({required this.center});

  final CostCenter center;

  @override
  ConsumerState<_MembersSheet> createState() => _MembersSheetState();
}

class _MembersSheetState extends ConsumerState<_MembersSheet> {
  int? _newUser;
  bool _newCanPrint = true;
  bool _busy = false;

  Future<void> _write(
    String action,
    Future<void> Function(FinanceRepository repo) write, {
    String? done,
  }) async {
    setState(() => _busy = true);
    final ok = await runFinanceWrite(
      context,
      action: action,
      write: write,
      done: done,
    );
    if (!mounted) return;
    if (ok) ref.invalidate(costCenterDetailProvider(widget.center.id));
    setState(() {
      _busy = false;
      if (ok) _newUser = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final id = widget.center.id;
    final detail = ref.watch(costCenterDetailProvider(id));
    final names = {
      for (final u in ref.watch(statsUsersProvider).value ?? <UserSummary>[])
        u.id: u.username,
    };
    final members = detail.value?.members ?? const <CostCenterMember>[];
    return _formSheet(
      id: 'sheet.cost_center_members',
      title: widget.center.name,
      children: [
        Text(l10n.financeManageMembers, style: t.labelSoft),
        _gap(),
        if (detail.isLoading && !detail.hasValue)
          const Center(child: DashSpinner(size: 22))
        else if (detail.hasError && !detail.hasValue)
          Text(l10n.financeLoadFailed, style: t.labelSoft)
        else if (members.isEmpty)
          Text(l10n.financeNoMembers, style: t.labelSoft)
        else
          // The name is the row's title, so a reader says whose switch it is.
          for (final m in members)
            Row(
              children: [
                Expanded(
                  child: SettingsSwitchRow(
                    tag: 'finance_form.member_can_print',
                    title: names[m.userId] ?? l10n.financeUserWithId(m.userId),
                    subtitle: l10n.financeCanPrint,
                    value: m.canPrint,
                    onChanged: _busy
                        ? null
                        : (v) => _write(
                            'finance_form.member_can_print',
                            (repo) => repo.setMember(id, m.userId, canPrint: v),
                          ),
                  ),
                ),
                IconButton(
                  tooltip: l10n.financeRemoveMember,
                  onPressed: _busy
                      ? null
                      : () => _write(
                          'finance_form.member_remove',
                          (repo) => repo.removeMember(id, m.userId),
                          done: l10n.financeMemberRemoved,
                        ),
                  icon: const Icon(Icons.person_remove_outlined),
                ).tagged('finance_form.member_remove'),
              ],
            ),
        const Divider(height: DashSpace.xl),
        _userPicker(
          context,
          ref,
          id: 'finance_form.member_user',
          selected: _newUser,
          // A user who is already a member is changed above, not added again.
          except: {for (final m in members) m.userId},
          onPick: (v) => setState(() => _newUser = v),
        ),
        _gap(),
        SettingsSwitchRow(
          tag: 'finance_form.member_new_can_print',
          title: l10n.financeMemberCanPrint,
          subtitle: l10n.financeMemberCanPrintHint,
          value: _newCanPrint,
          onChanged: (v) => setState(() => _newCanPrint = v),
        ),
        _gap(),
        _saveButton(
          context,
          id: 'finance_form.member_add',
          label: l10n.financeAddMember,
          saving: _busy,
          onPressed: () {
            final user = _newUser;
            if (user == null) {
              ScaffoldMessenger.of(context).snack(l10n.financeNoEligibleUsers);
              return;
            }
            _write(
              'finance_form.member_add',
              (repo) => repo.setMember(id, user, canPrint: _newCanPrint),
              done: l10n.financeMemberSaved,
            );
          },
        ),
      ],
    );
  }
}
