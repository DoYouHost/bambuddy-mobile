import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/models/print_log_entry.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import '../common/confirm_dialog.dart';
import '../common/currency_symbol.dart';
import '../common/dash_input.dart';
import '../common/format_datetime.dart';
import '../common/print_run_labels.dart';
import '../stats/stats_common.dart' show fmtDuration, fmtGrams, fmtNum;
import 'print_log_providers.dart';

/// Editor for one run's classification — the failure cause, and the status it
/// is counted under.
///
/// The two belong together because the server only ever shows a cause for a run
/// it counts as a failure (`FailureAnalysisService` groups within
/// `failed`/`aborted`), so setting one without the other is the way to store a
/// value nothing will ever display. The hint under the status says which of the
/// two the current selection means.
class PrintLogClassifySheet extends ConsumerStatefulWidget {
  const PrintLogClassifySheet({super.key, required this.entry});

  final PrintLogEntry entry;

  @override
  ConsumerState<PrintLogClassifySheet> createState() =>
      _PrintLogClassifySheetState();
}

class _PrintLogClassifySheetState
    extends ConsumerState<PrintLogClassifySheet> {
  /// `''` is "not classified" — the value the server takes to clear the field.
  late String _reason = widget.entry.failureReason ?? '';
  late String _status = widget.entry.status;
  var _saving = false;

  /// The stored status is outside what `PATCH /print-log/{id}` can write —
  /// `aborted` from the archive side, or a value we failed to parse. Leaving
  /// the field untouched keeps it; picking anything else is one-way.
  bool get _statusIsUnwritable =>
      !printLogStatuses.contains(widget.entry.status);

  bool get _changed =>
      _reason != (widget.entry.failureReason ?? '') ||
      _status != widget.entry.status;

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final original = widget.entry.failureReason ?? '';

    setState(() => _saving = true);
    final error = await ref.read(printLogProvider.notifier).reclassify(
          widget.entry.id,
          // Each field is sent only when the user moved it: an unsent field is
          // a no-op server-side, which is what keeps an unwritable status.
          failureReason:
              _reason != original && _reason.isNotEmpty ? _reason : null,
          clearFailureReason: _reason != original && _reason.isEmpty,
          status: _status == widget.entry.status ? null : _status,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      showApiFailure(
        messenger,
        error,
        l10n,
        action: 'print_log.classify.save',
        message: l10n.printLogSaveFailed,
      );
      return;
    }
    navigator.pop();
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await confirmDialog(
      context,
      title: l10n.printLogDeleteTitle,
      message: l10n.printLogDeleteBody,
      confirmLabel: l10n.printLogDelete,
      destructive: true,
      icon: Icons.delete_outline,
      id: 'print_log.delete',
    );
    if (!confirmed || !mounted) return;

    final error =
        await ref.read(printLogProvider.notifier).deleteEntry(widget.entry.id);
    if (!mounted) return;
    if (error != null) {
      showApiFailure(
        messenger,
        error,
        l10n,
        action: 'print_log.delete',
        message: l10n.printLogDeleteFailed,
      );
      return;
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final entry = widget.entry;

    // Cost and energy are absent from every row below 1.2.6, so their lines
    // would read as "this run drew nothing" rather than "this server does not
    // say" — the same gate the list columns are behind.
    final showMoney =
        ref.watch(printLogCostEnergyProvider).valueOrNull ?? false;
    final currency = ref.watch(currencySymbolProvider);

    return logTag(
      'sheet.print_log_classify',
      SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.printName ?? l10n.printLogClassifyTitle,
              style: t.titleSm,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              [
                if (entry.printerName != null) entry.printerName!,
                entry.createdByUsername ?? l10n.printLogNoUser,
                if (entry.isOrphan) l10n.printLogOrphan,
              ].join(' · '),
              style: t.label.copyWith(color: t.textSecondary),
            ),
            const SizedBox(height: 14),

            // What the row could only show abbreviated, in full: the card has
            // one line for all of it and cuts whatever does not fit.
            _RunDetailRow(
              label: l10n.printLogDetailStarted,
              value: entry.startedAt == null
                  ? null
                  : formatDateTime(entry.startedAt!),
            ),
            _RunDetailRow(
              label: l10n.printLogDetailFinished,
              value: entry.completedAt == null
                  ? null
                  : formatDateTime(entry.completedAt!),
            ),
            _RunDetailRow(
              label: l10n.printLogDetailDuration,
              value: entry.durationSeconds == null
                  ? null
                  : fmtDuration(entry.durationSeconds!),
            ),
            _RunDetailRow(
              label: l10n.printLogDetailFilament,
              value: [
                if (entry.filamentType != null) entry.filamentType!,
                if (entry.filamentUsedGrams != null)
                  fmtGrams(entry.filamentUsedGrams!),
              ].join(' · '),
            ),
            if (showMoney) ...[
              _RunDetailRow(
                label: l10n.printLogDetailCost,
                value: entry.cost == null
                    ? null
                    : formatMoney(currency, fmtNum(entry.cost!)),
              ),
              _RunDetailRow(
                label: l10n.printLogDetailEnergy,
                value: entry.energyKwh == null
                    ? null
                    : [
                        l10n.printLogEnergy(fmtNum(entry.energyKwh!)),
                        if (entry.energyCost != null)
                          formatMoney(currency, fmtNum(entry.energyCost!)),
                      ].join(' · '),
              ),
            ],
            const SizedBox(height: 14),
            Divider(color: t.hairline, height: 1),
            const SizedBox(height: 18),

            dashCombo<String>(
              context,
              id: 'print_log.classify.reason',
              label: Text(l10n.printLogFailureCause),
              initialSelection: _reason,
              textStyle: t.body,
              onSelected: (v) => setState(() => _reason = v ?? ''),
              entries: [
                DropdownMenuEntry(
                  value: '',
                  label: l10n.printLogNoClassification,
                  labelWidget: logTag(
                    'print_log.classify.reason.none',
                    Text(l10n.printLogNoClassification),
                  ),
                ),
                for (final key in printLogFailureReasons)
                  DropdownMenuEntry(
                    value: key,
                    label: failureReasonLabel(l10n, key),
                    labelWidget: logTag(
                      'print_log.classify.reason.option',
                      Text(failureReasonLabel(l10n, key)),
                    ),
                  ),
                // A cause stored outside the vocabulary — an older web build
                // saved translated labels. Offered so the field shows what the
                // row actually holds instead of reading as unclassified.
                if (entry.failureReason != null &&
                    !printLogFailureReasons.contains(entry.failureReason))
                  DropdownMenuEntry(
                    value: entry.failureReason!,
                    label: failureReasonLabel(l10n, entry.failureReason),
                    labelWidget: logTag(
                      'print_log.classify.reason.legacy',
                      Text(failureReasonLabel(l10n, entry.failureReason)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            dashCombo<String>(
              context,
              id: 'print_log.classify.status',
              label: Text(l10n.printLogStatusLabel),
              initialSelection: _status,
              textStyle: t.body,
              onSelected: (v) => setState(() => _status = v ?? _status),
              entries: [
                for (final s in printLogStatuses)
                  DropdownMenuEntry(
                    value: s,
                    label: printRunStatusLabel(l10n, s),
                    labelWidget: logTag(
                      'print_log.classify.status.option',
                      Text(printRunStatusLabel(l10n, s)),
                    ),
                  ),
                if (_statusIsUnwritable)
                  DropdownMenuEntry(
                    value: entry.status,
                    label: printRunStatusLabel(l10n, entry.status),
                    labelWidget: logTag(
                      'print_log.classify.status.current',
                      Text(printRunStatusLabel(l10n, entry.status)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            Text(
              printLogStatusIsFailure(_status)
                  ? l10n.printLogCountsAsFailure
                  : l10n.printLogNotCountedAsFailure,
              style: t.label,
            ),
            if (_statusIsUnwritable && _status == entry.status) ...[
              const SizedBox(height: 6),
              Text(
                l10n.printLogStatusOneWay(
                  printRunStatusLabel(l10n, entry.status),
                ),
                style: t.label.copyWith(color: t.accentOrange),
              ),
            ],
            const SizedBox(height: 20),

            Row(
              children: [
                logTag(
                  'print_log.classify.delete',
                  TextButton.icon(
                    onPressed: _saving ? null : _delete,
                    icon: Icon(Icons.delete_outline, size: 18, color: t.danger),
                    label: Text(
                      l10n.printLogDelete,
                      style: TextStyle(color: t.danger),
                    ),
                  ),
                ),
                const Spacer(),
                logTag(
                  'print_log.classify.save',
                  FilledButton(
                    onPressed: _changed && !_saving ? _save : null,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.printLogSave),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One `label — value` line of the run's detail block. Renders nothing when
/// the server has no value for it: an empty right-hand side reads as a zero,
/// which for cost and energy is a different claim entirely.
class _RunDetailRow extends StatelessWidget {
  const _RunDetailRow({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final text = value?.trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(child: Text(label, style: t.label)),
          const SizedBox(width: 12),
          Text(text, style: t.monoValue),
        ],
      ),
    );
  }
}
