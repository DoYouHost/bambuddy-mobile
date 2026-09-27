import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/datetime_format.dart';
import '../../core/models/archive.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/dash_async.dart';

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

/// The card's marker for where a print stands: waiting for a verdict, or the
/// verdict it got. Nothing for a print that was never asked and never judged,
/// which is every print on an older server.
class ArchiveVerdictBadge extends StatelessWidget {
  const ArchiveVerdictBadge({super.key, required this.archive});

  final Archive archive;

  @override
  Widget build(BuildContext context) {
    if (!archiveTakesVerdict(archive)) return const SizedBox.shrink();
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final (label, border, ink) = switch (archive.userVerdict) {
      PrintVerdict.good => (
        l10n.outcomeGoodPart,
        t.accentGreen,
        t.accentGreenInk,
      ),
      PrintVerdict.reject => (l10n.outcomeRejected, t.danger, t.dangerInk),
      null when archive.awaitsVerdict => (
        l10n.outcomeAwaiting,
        t.accentOrange,
        t.accentOrangeInk,
      ),
      null => (null, null, null),
    };
    if (label == null || border == null || ink == null) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border.withValues(alpha: 0.5)),
      ),
      child: Text(label, style: t.micro.copyWith(color: ink)),
    );
  }
}

/// The detail sheet's line on the part's verdict: what was recorded, how and
/// when — or that the print is still waiting for one.
///
/// Only on a completed print. "No verdict yet" needs a server that records
/// verdicts — on one that cannot hold one it would be a question nobody can
/// answer.
class ArchiveOutcomeRow extends ConsumerWidget {
  const ArchiveOutcomeRow({
    super.key,
    required this.archive,
    required this.onRate,
  });

  final Archive archive;

  /// Opens the outcome sheet. Offered only where a verdict can be written.
  final VoidCallback onRate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!archiveTakesVerdict(archive)) return const SizedBox.shrink();
    // A verdict the archive carries proves the server keeps them; only the
    // question of a missing one waits for the gate.
    if (archive.userVerdict == null &&
        !ref.watch(printOutcomeSupportedProvider).orFalse) {
      return const SizedBox.shrink();
    }
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final verdict = archive.userVerdict;
    final at = archive.userVerdictAt;
    final writable = ref.watch(printOutcomeSupportedProvider).orFalse;
    final details = [
      if (verdict != null) ?verdictSourceLabel(l10n, archive.userVerdictSource),
      if (verdict != null && at != null)
        DateTimeFormats.of(context).dateTime(at),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(switch (verdict) {
            PrintVerdict.good => Icons.thumb_up_alt_outlined,
            PrintVerdict.reject => Icons.thumb_down_alt_outlined,
            null => Icons.help_outline,
          }, color: t.textSecondary),
          const SizedBox(width: 12),
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
          if (writable)
            logTag(
              'archive.rate_outcome',
              TextButton(
                onPressed: onRate,
                child: Text(
                  verdict == null ? l10n.outcomeRate : l10n.outcomeChange,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
