import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/datetime_format.dart';
import '../../core/models/archive.dart';
import '../../core/models/current_user.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../core/api/api_exceptions.dart';
import '../common/api_failure_snack.dart';
import '../common/dash_async.dart';
import '../../core/app_context.dart';
import 'outcome_sheet.dart';

/// Whether this server records a user's verdict on a printed part (#1898).
///
/// Every control that *writes* one rests on this: `ArchiveUpdate` on an older
/// server drops `user_verdict` and answers 200, so a verdict offered there
/// would look saved and be gone. What an archive already carries needs no gate
/// — an older server never sends a verdict to show.
final printOutcomeSupportedProvider = capabilityGate(
  (ref) => ref.watch(archiveRepositoryProvider).outcomeCapability,
);

/// Whether this print can be given a verdict at all: the web offers it on
/// completed prints only, since a failed one already has its answer.
bool archiveTakesVerdict(Archive archive) => archive.status == 'completed';

String verdictLabel(AppLocalizations l10n, PrintVerdict verdict) =>
    switch (verdict) {
      PrintVerdict.good => l10n.outcomeGoodPart,
      PrintVerdict.reject => l10n.outcomeRejected,
    };

/// How a verdict arrived, as a sentence — the plate-clear default answers
/// prompts on its own, and without this a verdict nobody remembers giving
/// looks like it came from nowhere. Null for a source this build does not
/// know, which is better said by nothing than by a guess.
String? verdictSourceLabel(AppLocalizations l10n, String? source) =>
    switch (source) {
      'dialog' => l10n.outcomeSourceDialog,
      'link' => l10n.outcomeSourceLink,
      'plate_clear' => l10n.outcomeSourcePlateClear,
      'printer_card' => l10n.outcomeSourcePrinterCard,
      'api' => l10n.outcomeSourceApi,
      'reaction' => l10n.outcomeSourceReaction,
      _ => null,
    };

/// The card's marker for where a print stands — kept, binned, or waiting to
/// be asked — as a round mark on the thumbnail's corner rather than a row of
/// its own, which made every judged card taller than the rest. Nothing for a
/// print that was never asked and never judged, which is every print on an
/// older server. The state's name goes to a screen reader.
class ArchiveVerdictMark extends StatelessWidget {
  const ArchiveVerdictMark({super.key, required this.archive});

  final Archive archive;

  static const size = 22.0;

  @override
  Widget build(BuildContext context) {
    if (!archiveTakesVerdict(archive)) return const SizedBox.shrink();
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final mark = switch (archive.userVerdict) {
      PrintVerdict.good => (
        l10n.outcomeGoodPart,
        Icons.thumb_up_alt,
        t.accentGreen,
        t.accentGreenInk,
      ),
      PrintVerdict.reject => (
        l10n.outcomeRejected,
        Icons.thumb_down_alt,
        t.danger,
        t.dangerInk,
      ),
      null when archive.awaitsVerdict => (
        l10n.outcomeAwaiting,
        Icons.hourglass_top,
        t.accentOrange,
        t.accentOrangeInk,
      ),
      null => null,
    };
    if (mark == null) return const SizedBox.shrink();
    final (label, icon, tone, ink) = mark;
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          // Opaque, so the mark reads the same over any thumbnail.
          color: Color.alphaBlend(
            tone.withValues(alpha: 0.25),
            t.overlaySurface,
          ),
          shape: BoxShape.circle,
          border: Border.all(color: tone.withValues(alpha: 0.6)),
        ),
        child: Icon(icon, size: 13, color: ink),
      ),
    );
  }
}

/// The detail sheet's line on the part's verdict — what was recorded, how and
/// when — with a thumb for each answer. The chosen thumb is filled; tapping it
/// again clears the verdict. A thumb down also opens the outcome sheet on its
/// reason step, since a reject is where a cause and a reprint belong.
///
/// Only on a completed print. "No verdict yet" needs a server that records
/// verdicts — on one that cannot hold one it would be a question nobody can
/// answer.
class ArchiveOutcomeRow extends ConsumerStatefulWidget {
  const ArchiveOutcomeRow({
    super.key,
    required this.archive,
    required this.onReject,
  });

  final Archive archive;

  /// Opens the outcome sheet on its reason step, once a reject is stored.
  final VoidCallback onReject;

  @override
  ConsumerState<ArchiveOutcomeRow> createState() => _ArchiveOutcomeRowState();
}

class _ArchiveOutcomeRowState extends ConsumerState<ArchiveOutcomeRow> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final archive = widget.archive;
    if (!archiveTakesVerdict(archive)) return const SizedBox.shrink();
    // A verdict the archive carries proves the server keeps them; only the
    // question of a missing one waits for the gate.
    final supported = ref.watch(printOutcomeSupportedProvider).orFalse;
    if (archive.userVerdict == null && !supported) {
      return const SizedBox.shrink();
    }
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final verdict = archive.userVerdict;
    final at = archive.userVerdictAt;
    // The route still checks the print's owner against update-own.
    final writable =
        supported &&
        (ref.watch(permissionProvider(Permissions.archivesUpdateAll)) ||
            ref.watch(permissionProvider(Permissions.archivesUpdateOwn)));
    final details = [
      if (verdict != null) ?verdictSourceLabel(l10n, archive.userVerdictSource),
      if (verdict != null && at != null)
        DateTimeFormats.of(context).dateTime(at),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: DashSpace.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  verdict == null
                      ? (archive.awaitsVerdict
                            ? l10n.outcomeAwaiting
                            : l10n.outcomeNotRecorded)
                      : verdictLabel(l10n, verdict),
                  style: t.bodyStrong,
                ),
                if (details.isNotEmpty)
                  Text(details.join(' · '), style: t.labelSoft),
              ],
            ),
          ),
          for (final (choice, gap) in [
            (PrintVerdict.good, false),
            (PrintVerdict.reject, true),
          ]) ...[
            if (gap) const SizedBox(width: DashSpace.sm),
            _thumb(t, l10n, choice, writable: writable),
          ],
        ],
      ),
    );
  }

  Widget _thumb(
    DashTokens t,
    AppLocalizations l10n,
    PrintVerdict choice, {
    required bool writable,
  }) {
    final chosen = widget.archive.userVerdict == choice;
    final good = choice == PrintVerdict.good;
    final (fill, ink) = good
        ? (t.accentGreen, t.accentGreenInk)
        : (t.danger, t.dangerInk);
    final icon = switch ((good, chosen)) {
      (true, true) => Icons.thumb_up_alt,
      (true, false) => Icons.thumb_up_alt_outlined,
      (false, true) => Icons.thumb_down_alt,
      (false, false) => Icons.thumb_down_alt_outlined,
    };
    final label = good ? l10n.outcomeGood : l10n.outcomeReject;
    final onPressed = writable && !_saving ? () => _choose(choice) : null;
    final button = chosen
        ? IconButton.filled(
            onPressed: onPressed,
            style: IconButton.styleFrom(
              backgroundColor: fill,
              foregroundColor: good ? t.onAccent : t.onDanger,
              disabledBackgroundColor: fill.withValues(alpha: 0.5),
              disabledForegroundColor: good ? t.onAccent : t.onDanger,
            ),
            icon: Icon(icon),
          )
        : IconButton.outlined(
            onPressed: onPressed,
            style: IconButton.styleFrom(
              foregroundColor: ink,
              side: BorderSide(color: fill.withValues(alpha: 0.5)),
            ),
            icon: Icon(icon),
          );
    return Semantics(
      label: label,
      selected: chosen,
      child: Tooltip(
        message: label,
        child: button.tagged(
          good ? 'archive.verdict_good' : 'archive.verdict_reject',
        ),
      ),
    );
  }

  /// Records [choice], or clears it when it is the verdict already standing.
  Future<void> _choose(PrintVerdict choice) async {
    if (_saving) return;
    final archive = widget.archive;
    final next = archive.userVerdict == choice ? null : choice;
    final l10n = AppLocalizations.of(context);
    final (:providers, :messenger) = detachFrom(context);
    setState(() => _saving = true);
    try {
      // A cause the print already carries stays with a new reject; the reason
      // step that opens next is where it can be changed or taken off.
      final result = await writeVerdict(
        providers,
        archive,
        next,
        reason: next == PrintVerdict.reject ? archive.failureReason : null,
      );
      messenger.snack(verdictSavedMessage(l10n, next, applied: result.applied));
      if (next == PrintVerdict.reject && result.applied && mounted) {
        widget.onReject();
      }
    } on AppApiException catch (e) {
      showApiFailure(
        mounted ? messenger : null,
        e,
        l10n,
        action: next == null
            ? 'archive.verdict_clear'
            : 'archive.verdict_${next.wire}',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
