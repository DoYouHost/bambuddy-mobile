import 'dart:math' as math;

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/format/datetime_format.dart';
import '../../core/models/print_batch.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/server_refusal.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import '../common/dash_async.dart';
import '../common/date_time_picker.dart';
import '../common/dash_input.dart';
import '../common/dash_stepper.dart';
import 'orders_providers.dart';
import 'orders_screen.dart';

/// Edits an order's header and per-plate targets (`PATCH`, 1.2.5.3+).
///
/// The web has no such form — its orders tab only dispatches and cancels — so
/// this follows the route itself: every field is optional, a null leaves it
/// alone, and nothing here can be cleared once set except the notes (to `""`).
class OrderEditScreen extends ConsumerWidget {
  const OrderEditScreen({super.key, required this.batchId});

  final int batchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(batchDetailProvider(batchId));
    final batch = async.valueOrNull;
    // The form seeds its fields from the batch, so it is built once, from the
    // first answer; until then the bar is all there is.
    if (batch != null) return DashBackground(child: _OrderForm(batch: batch));
    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(context, title: l10n.orderEditTitle),
        body: dashAsync(
          context,
          async,
          onRetry: () => ref.invalidate(batchDetailProvider(batchId)),
          data: (_) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// The edit form's own refusals, before the screen's shared ones.
final List<RefusalRule> _editRefusals = [
  (['at least one print'], (l) => l.orderEditErrNothingAsked),
  (['name is required'], (l) => l.orderEditErrName),
];

class _OrderForm extends ConsumerStatefulWidget {
  const _OrderForm({required this.batch});

  final PrintBatch batch;

  @override
  ConsumerState<_OrderForm> createState() => _OrderFormState();
}

class _OrderFormState extends ConsumerState<_OrderForm> {
  late final _name = TextEditingController(text: widget.batch.name);
  late final _notes = TextEditingController(text: widget.batch.notes ?? '');
  late DateTime? _due = widget.batch.dueDate;
  late int? _projectId = widget.batch.projectId;
  late final List<int> _targets = [
    for (final p in widget.batch.plates) p.quantityTarget,
  ];
  bool _saving = false;
  bool _nameMissing = false;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  PrintBatch get _b => widget.batch;

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final due = _due;
    final picked = await pickDate(
      context,
      initial: due ?? now.add(const Duration(days: 7)),
      // The range reaches the stored date, whichever side of it: a due date
      // that has passed, or one an integration set years ahead, must still be
      // the day the calendar shows and can keep.
      firstDate: due != null && due.isBefore(now) ? due : now,
      lastDate: DateTime(math.max(now.year + 5, (due?.year ?? now.year) + 1)),
    );
    if (picked == null) return;
    // The end of the picked day, so "due today" is not overdue until it ends.
    setState(
      () => _due = DateTime(picked.year, picked.month, picked.day, 23, 59, 59),
    );
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameMissing = true);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final providers = ProviderScope.containerOf(context, listen: false);
    final notes = _notes.text.trim();
    final projectChanged = _projectId != _b.projectId;
    final targetsChanged = [
      for (final (i, p) in _b.plates.indexed) _targets[i] != p.quantityTarget,
    ].any((changed) => changed);

    final inFlight = providers.read(ordersInFlightProvider.notifier);
    // A dispatch or cancel from the list would race the new targets.
    if (inFlight.state.contains(_b.id)) return;
    inFlight.state = {...inFlight.state, _b.id};
    setState(() => _saving = true);
    try {
      await providers
          .read(batchRepositoryProvider)
          .update(
            _b.id,
            name: name == _b.name ? null : name,
            notes: notes == (_b.notes ?? '').trim() ? null : notes,
            dueDate: _due == _b.dueDate ? null : _due,
            projectId: projectChanged ? _projectId : null,
            plates: targetsChanged
                ? [
                    for (final (i, p) in _b.plates.indexed)
                      (
                        plateId: p.plateId,
                        plateName: p.plateName,
                        quantity: _targets[i],
                      ),
                  ]
                : null,
          );
      providers.invalidate(batchesProvider);
      providers.invalidate(batchDetailProvider(_b.id));
      messenger.snack(l10n.orderEditSaved);
      navigator.pop();
    } on AppApiException catch (e) {
      showApiFailure(
        messenger,
        e,
        l10n,
        action: 'order_edit.save',
        // The mapper keeps a detail for a 400 or 422 only, so a 404 for the
        // project and one for the batch look alike; a changed project is the
        // likelier of the two.
        message: e.statusCode == 404 && projectChanged
            ? l10n.orderEditErrProject
            : orderRefusal(l10n, e, _editRefusals),
      );
      if (mounted) setState(() => _saving = false);
    } finally {
      inFlight.state = {...inFlight.state}..remove(_b.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final projects = ref.watch(orderProjectsProvider).valueOrNull;
    // A dispatch or cancel from the list holds the batch: the save waits,
    // visibly, rather than ignore the tap.
    final busy =
        _saving ||
        ref.watch(ordersInFlightProvider.select((s) => s.contains(_b.id)));
    final due = _due;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: dashAppBar(
        context,
        title: l10n.orderEditTitle,
        actions: [
          dashSaveAction(
            id: 'order_edit.save',
            label: l10n.orderEditSave,
            busy: busy,
            onPressed: _save,
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: busy,
        child: ListView(
          padding: withSystemNavInset(
            context,
            const EdgeInsets.fromLTRB(16, 12, 16, 32),
          ),
          children: [
            TextField(
              controller: _name,
              style: t.bodyStrong,
              onChanged: (_) {
                if (_nameMissing) setState(() => _nameMissing = false);
              },
              decoration: dashFieldDecoration(
                t,
                labelText: l10n.orderEditName,
                errorText: _nameMissing ? l10n.orderEditErrName : null,
              ),
            ).tagged('order_edit.name'),
            const SizedBox(height: 12),
            dashPickerField(
              context,
              id: 'order_edit.due',
              label: l10n.orderEditDue,
              placeholder: l10n.orderEditDueNone,
              value: due == null ? null : DateTimeFormats.of(context).date(due),
              prefixIcon: Icons.event_outlined,
              // The route has no way to remove one, so say so rather than
              // offer a clear button that would do nothing.
              helperText: due == null ? null : l10n.orderEditDueHint,
              onTap: _pickDue,
            ),
            if (projects != null && projects.isNotEmpty) ...[
              const SizedBox(height: 6),
              dashCombo<int?>(
                context,
                id: 'order_edit.project',
                label: Text(l10n.orderEditProject),
                initialSelection: _projectId,
                helperText: _b.projectId == null
                    ? null
                    : l10n.orderEditProjectHint,
                textStyle: t.body,
                onSelected: (v) => setState(() => _projectId = v),
                entries: [
                  // Only while none is set: the route cannot unset one.
                  if (_b.projectId == null)
                    DropdownMenuEntry(
                      value: null,
                      label: l10n.orderEditProjectNone,
                      labelWidget: logTag(
                        'order_edit.project.none',
                        Text(l10n.orderEditProjectNone),
                      ),
                    ),
                  for (final p in projects)
                    DropdownMenuEntry(
                      value: p.id,
                      label: p.name,
                      labelWidget: logTag(
                        'order_edit.project.option',
                        Text(p.name),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              style: t.body,
              minLines: 2,
              maxLines: 6,
              decoration: dashFieldDecoration(
                t,
                labelText: l10n.orderEditNotes,
              ),
            ).tagged('order_edit.notes'),
            if (_b.hasTargets && _b.plates.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(l10n.orderEditTargets, style: t.titleSm),
              const SizedBox(height: 4),
              Text(l10n.orderEditTargetsHint, style: t.bodySoft),
              for (final (i, p) in _b.plates.indexed)
                _TargetRow(
                  label: batchPlateLabel(l10n, p),
                  done: p.completedCount,
                  value: _targets[i],
                  onChanged: (v) => setState(() => _targets[i] = v),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One plate's target: − n +, 0..999 as the schema bounds it.
class _TargetRow extends StatelessWidget {
  const _TargetRow({
    required this.label,
    required this.done,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int done;
  final int value;
  final ValueChanged<int> onChanged;

  static const _max = 999;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: t.bodyStrong),
                Text(l10n.orderEditPlateDone(done), style: t.monoMicro),
              ],
            ),
          ),
          DashStepper(
            value: value,
            min: 0,
            max: _max,
            onChanged: onChanged,
            lessTooltip: l10n.orderEditTargetLess,
            moreTooltip: l10n.orderEditTargetMore,
            lessId: 'order_edit.target_down',
            moreId: 'order_edit.target_up',
          ),
        ],
      ),
    );
  }
}
