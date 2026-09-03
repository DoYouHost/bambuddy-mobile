import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/diagnostics/log_tag.dart';
import '../../core/format/user_number.dart';
import '../../core/models/archive.dart';
import '../../data/archive_repository.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import '../common/dash_snack.dart';
import '../stats/stats_providers.dart';
import 'archive_providers.dart';

/// The bound the server puts on the column (`ge=0, le=100_000`). Checked here
/// so a typo answers in the field instead of as a 422 from the other end.
const filamentGramsMax = 100000.0;

/// Why a typed weight cannot be sent.
enum FilamentGramsError { notANumber, outOfRange }

/// Reads the weight field.
///
/// Empty text is a value, not a mistake: it clears the figure, which is how a
/// wrong correction is taken back. That is the one thing this adds over
/// [parseUserDecimal], which cannot tell an empty field from an unreadable one
/// and does not need to — every other field means "unset" by both.
({double? grams, FilamentGramsError? error}) parseFilamentGrams(String text) {
  if (text.trim().isEmpty) return (grams: null, error: null);

  final value = parseUserDecimal(text);
  if (value == null) return (grams: null, error: FilamentGramsError.notANumber);
  if (value < 0 || value > filamentGramsMax) {
    return (grams: null, error: FilamentGramsError.outOfRange);
  }
  return (grams: value, error: null);
}

/// A weight the way the user would write it: no decimal point on a whole
/// number, which nearly every figure is, and two decimals at most when there is
/// one.
///
/// Both the row's value and the field's initial text, so what the dialog offers
/// back is what the row shows. Two decimals is where a *typed* weight is exact
/// — nobody writes a milligram — but it is not always exactly what is stored:
/// a figure the slicer computed can carry more, and reopening the dialog and
/// saving rounds it to what the field displayed. That trade goes this way round
/// because the alternative is a field that opens on 12.344999999999999.
String filamentGramsText(double? grams) {
  if (grams == null) return '';
  final fixed = grams.toStringAsFixed(2);
  if (!fixed.contains('.')) return fixed;
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}

/// What the runs of this file say about its filament, as a line under the
/// archive's own figure — or null where they say nothing worth one.
///
/// The two numbers answer different questions. The archive's is the slicer's
/// estimate for the whole file (or a typed correction of it); this one is what
/// the runs actually drew, summed over all of them — a tracked spool's measured
/// delta where the slots were mapped to inventory, and only the estimate again
/// where they were not.
///
/// Silent in the two cases where a second line would be noise: a file with no
/// logged runs, which is also every server too old to send the aggregate, and a
/// sum that came out as the archive's own figure, which is what a single
/// completed print without spool tracking always looks like.
String? filamentActualCaption(Archive archive, AppLocalizations l10n) {
  if (archive.runCount == 0) return null;
  final actual = archive.totalFilamentActualGrams;
  // Runs that recorded nothing. The wire cannot tell that from a sum of zero
  // (`float(total) if total else None`), and it does not have to: a print
  // stopped before its first layer and one whose figure was never written both
  // mean there is no measurement to show.
  if (actual == null) return l10n.archiveFilamentNoActual;
  if (sameFilamentGrams(actual, archive.filamentUsedGrams)) return null;
  return l10n.archiveFilamentActual(
    l10n.archiveFilamentGrams(filamentGramsText(actual)),
    archive.runCount,
  );
}

/// The filament weight of one print, and the only field of an archive the app
/// writes by hand.
///
/// It exists for the print that archived without its 3MF: there is no weight to
/// read, no rescan can produce one, and the figure feeds both the statistics
/// and the project totals. Shown for every print all the same — a weight read
/// from a 3MF is an estimate, and correcting one is the same edit.
class ArchiveFilamentRow extends ConsumerStatefulWidget {
  const ArchiveFilamentRow({required this.archive, super.key});

  final Archive archive;

  @override
  ConsumerState<ArchiveFilamentRow> createState() => _ArchiveFilamentRowState();
}

class _ArchiveFilamentRowState extends ConsumerState<ArchiveFilamentRow> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    // The list is the screen's copy of this print, and the save writes the
    // stored row back into it — so the value here follows the edit without the
    // sheet being reopened.
    final live = _live(ref.watch(archiveProvider).valueOrNull);
    final grams = live.filamentUsedGrams;
    final actual = filamentActualCaption(live, l10n);

    // One control, not a label, a weight, a caption and an icon: without the
    // merge a screen reader walks a row it can tap as four unrelated strings
    // and never says it is a button. `logTag`'s identifier sits inside this and
    // reaches the merged node, which is what the interaction probe reads.
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: _card(context, l10n, t, grams, actual),
      ),
    );
  }

  Widget _card(
    BuildContext context,
    AppLocalizations l10n,
    DashTokens t,
    double? grams,
    String? actual,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: logTag(
          'archive.filament_edit',
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _saving ? null : _edit,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: t.subCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: t.subCardBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.scale_outlined, size: 18, color: t.textTertiary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l10n.archiveFilamentUsed, style: t.label),
                        const SizedBox(height: 2),
                        Text(
                          grams == null
                              ? l10n.archiveFilamentNone
                              : l10n.archiveFilamentGrams(
                                  filamentGramsText(grams)),
                          style: t.titleSm,
                        ),
                        if (actual != null) ...[
                          const SizedBox(height: 2),
                          Text(actual, style: t.micro),
                        ],
                      ],
                    ),
                  ),
                  if (_saving)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        semanticsLabel: l10n.archiveFilamentSaving,
                      ),
                    )
                  else
                    Icon(Icons.edit_outlined, size: 18, color: t.textSecondary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// This print as the loaded list holds it *now*.
  ///
  /// [ArchiveFilamentRow.archive] is the snapshot the sheet was opened with, and
  /// it never changes: the sheet around this row is a `StatelessWidget` that
  /// nothing rebuilds. After one save it carries the weight from before that
  /// save — the one figure the dialog must not offer back, since accepting it
  /// would write the old value over the new one.
  Archive _live(List<Archive>? archives) =>
      archives?.where((a) => a.id == widget.archive.id).firstOrNull ??
      widget.archive;

  Future<void> _edit() async {
    final l10n = AppLocalizations.of(context);
    // Both of these outlive this widget on purpose. The sheet can be dismissed
    // while the PATCH is in flight and the server stores the weight anyway:
    // reaching for providers through `ref` afterwards would throw, so the list
    // would keep the old figure until a manual refresh and the user would be
    // told nothing at all. The container belongs to the app, and the messenger
    // to the `MaterialApp` above the sheet, so both are still there to use.
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final repository = container.read(archiveRepositoryProvider);
    final archiveId = widget.archive.id;
    final stored = _live(container.read(archiveProvider).valueOrNull);

    final answer = await showDialog<({double? grams})>(
      context: context,
      builder: (_) => _FilamentGramsDialog(
        initial: filamentGramsText(stored.filamentUsedGrams),
      ),
    );
    if (answer == null) return;
    // Nothing to write. Opening the row to read the weight and closing it with
    // Save is an ordinary thing to do, and it should not cost a request — nor
    // report a save that stored nothing.
    if (sameFilamentGrams(stored.filamentUsedGrams, answer.grams)) return;

    if (mounted) setState(() => _saving = true);
    try {
      final result = await repository.setFilamentGrams(archiveId, answer.grams);
      container.read(archiveProvider.notifier).replace(result.archive);
      if (result.applied) {
        // The weight is an aggregate figure — the server mirrors it onto the
        // run's log entry, which is what the totals actually sum — and the tabs
        // are an `IndexedStack`, so the statistics screen behind this one stays
        // mounted with the figure it loaded. Nothing else would tell it.
        container.invalidate(statsProvider);
        container.invalidate(archiveSlimProvider);
      }
      messenger.snack(
        result.applied
            ? l10n.archiveFilamentSaved
            : l10n.archiveFilamentUnsupported,
      );
    } on AppApiException catch (e) {
      showApiFailure(messenger, e, l10n, action: 'archive.filament_edit');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// Asks for the weight. A form, so an `AlertDialog` of its own rather than
/// `confirmDialog`; a `StatefulWidget` so the controller is disposed on the
/// dialog's own lifecycle instead of racing its exit animation.
///
/// Pops `null` when cancelled and a record otherwise — the record's `grams` is
/// itself nullable, since clearing the figure is a save like any other and
/// `null` alone could not say which of the two happened.
class _FilamentGramsDialog extends StatefulWidget {
  const _FilamentGramsDialog({required this.initial});

  final String initial;

  @override
  State<_FilamentGramsDialog> createState() => _FilamentGramsDialogState();
}

class _FilamentGramsDialogState extends State<_FilamentGramsDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);
  final _field = FocusNode();
  FilamentGramsError? _error;

  @override
  void dispose() {
    _controller.dispose();
    _field.dispose();
    super.dispose();
  }

  String _message(AppLocalizations l10n, FilamentGramsError error) =>
      switch (error) {
        FilamentGramsError.notANumber => l10n.archiveFilamentNotANumber,
        FilamentGramsError.outOfRange => l10n.archiveFilamentOutOfRange(
            filamentGramsText(filamentGramsMax)),
      };

  void _save() {
    final parsed = parseFilamentGrams(_controller.text);
    if (parsed.error != null) {
      setState(() => _error = parsed.error);
      // Focus goes back to what has to change. A screen reader is otherwise
      // left on the Save button, where nothing announces that a message under
      // the field appeared at all.
      _field.requestFocus();
      return;
    }
    Navigator.pop(context, (grams: parsed.grams));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      // At 200% system text the title, the field and a two-line error do not
      // fit a short screen, and a dialog that cannot scroll clips them.
      scrollable: true,
      title: Text(l10n.archiveFilamentUsed),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            focusNode: _field,
            autofocus: true,
            // Not `TextInputType.number`: that layout has no separator key on
            // several keyboards, and the weight is written with one often
            // enough that the field accepts both.
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            // Whitespace comes through because it carries meaning: a pasted
            // "1 234,5" is only unambiguous while the space is still in it —
            // strip that and the comma becomes a guess the parser refuses.
            // Letters are what the formatter is here for.
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]')),
            ],
            decoration: InputDecoration(
              labelText: l10n.archiveFilamentLabel,
              suffixText: l10n.archiveFilamentUnit,
              errorText: _error == null ? null : _message(l10n, _error!),
              // The refusals are a sentence, and one line cuts them off at any
              // text scale above the smallest.
              errorMaxLines: 3,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _save(),
          ).tagged('archive_filament.field'),
        ],
      ),
      actions: [
        logTag(
          'archive_filament.cancel',
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
        ),
        logTag(
          'archive_filament.save',
          FilledButton(onPressed: _save, child: Text(l10n.fmSave)),
        ),
      ],
    );
  }
}
