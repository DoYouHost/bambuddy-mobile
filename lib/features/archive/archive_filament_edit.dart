import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/diagnostics/log_tag.dart';
import '../../core/format/user_number.dart';
import '../../core/models/archive.dart';
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
    final grams = _live(ref.watch(archiveProvider).valueOrNull).filamentUsedGrams;

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
                      ],
                    ),
                  ),
                  if (_saving)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
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
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(archiveRepositoryProvider);
    final archiveId = widget.archive.id;
    final stored = _live(ref.read(archiveProvider).valueOrNull);

    final answer = await showDialog<({double? grams})>(
      context: context,
      builder: (_) => _FilamentGramsDialog(
        initial: filamentGramsText(stored.filamentUsedGrams),
      ),
    );
    if (answer == null || !mounted) return;

    setState(() => _saving = true);
    try {
      final result = await repository.setFilamentGrams(archiveId, answer.grams);
      // The sheet can be gone by now — the request outlives it — so nothing
      // below may touch this widget's `ref` without asking first.
      if (!mounted) return;
      ref.read(archiveProvider.notifier).replace(result.archive);
      if (result.applied) {
        // The weight is an aggregate figure — the server mirrors it onto the
        // run's log entry, which is what the totals actually sum — and the tabs
        // are an `IndexedStack`, so the statistics screen behind this one stays
        // mounted with the figure it loaded. Nothing else would tell it.
        ref.invalidate(statsProvider);
        ref.invalidate(archiveSlimProvider);
      }
      messenger.snack(
        result.applied
            ? l10n.archiveFilamentSaved
            : l10n.archiveFilamentUnsupported,
      );
    } on AppApiException catch (e) {
      showApiFailure(
        mounted ? messenger : null,
        e,
        l10n,
        action: 'archive.filament_edit',
      );
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
  FilamentGramsError? _error;

  @override
  void dispose() {
    _controller.dispose();
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
      return;
    }
    Navigator.pop(context, (grams: parsed.grams));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.archiveFilamentUsed),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.archiveFilamentHint),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            // Not `TextInputType.number`: that layout has no separator key on
            // several keyboards, and the weight is written with one often
            // enough that the field accepts both.
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: InputDecoration(
              labelText: l10n.archiveFilamentLabel,
              suffixText: l10n.archiveFilamentUnit,
              errorText: _error == null ? null : _message(l10n, _error!),
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
