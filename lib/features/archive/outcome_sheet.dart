import 'dart:async';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/archive.dart';
import '../../core/notifications/finish_alert_memory.dart';
import '../../core/notifications/outcome_alert.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import '../common/dash_async.dart';
import '../../core/app_context.dart';
import '../common/media_image.dart';
import '../common/print_run_labels.dart';
import '../common/print_thumbnail.dart';
import '../queue/queue_drafts.dart';
import '../queue/queue_edit_screen.dart';
import 'archive_providers.dart';
import 'print_outcome.dart';

/// "How did your print come out?" for one archive: the finish photo, Good or
/// Reject, and for a reject an optional reason and a reprint.
///
/// Opened from the archive, from the server's `print_confirm_request` while
/// the app is on screen, and from the outcome notification. The archive is
/// re-read rather than handed in: the finish photo is attached after the print
/// ends, and a prompt can be answered elsewhere while this one waits.
///
/// [rejecting] opens it on the reason step, for a reject the archive detail has
/// just recorded with its thumb.
///
/// [runId] asks about one print of the archive instead of its latest, behind
/// `archiveRunsSupportedProvider`.
Future<void> showOutcomeSheet(
  BuildContext context,
  int archiveId, {
  bool rejecting = false,
  int? runId,
}) => dashSheet<void>(
  context,
  builder: (_) =>
      OutcomeSheet(archiveId: archiveId, rejecting: rejecting, runId: runId),
);

/// Writes [verdict] (null clears it) and keeps the screen's list and the
/// outcome notification in step with what the server stored.
///
/// The cause goes with a reject as chosen — "No reason" included, which
/// clears one the print still carries. Leaving a reject clears its cause,
/// as the web's edit dialog does; anything else leaves it alone.
///
/// With [runId] the verdict is that print's, and [archive] is the archive as
/// that print printed (its reason is what a reject carries over). The answer
/// is the archive as its latest print shows it, like any other `PATCH`.
Future<({Archive archive, bool applied})> writeVerdict(
  ProviderContainer providers,
  Archive archive,
  PrintVerdict? verdict, {
  String? reason,
  int? runId,
}) async {
  final chosen = (reason ?? '').isEmpty ? null : reason;
  final carried = archive.failureReason != null;
  final result = await providers
      .read(archiveRepositoryProvider)
      .setVerdict(
        archive.id,
        verdict,
        reason: chosen,
        clearReason: verdict == PrintVerdict.reject
            ? chosen == null && carried
            : archive.userVerdict == PrintVerdict.reject && carried,
        runId: runId,
      );
  final latest = result.archive;
  // Either way a print's verdict changed, and the sheet's print list shows it.
  providers.invalidate(archiveRunsProvider(archive.id));
  // Only a list somebody is looking at: building it here would fetch every
  // archive the server has to change one row.
  if (providers.exists(archiveProvider)) {
    providers.read(archiveProvider.notifier).replace(latest);
  }
  // Answered here, so the notification asking the same thing has nothing
  // left to ask — for one print, only once the latest is answered.
  if (result.applied && !latest.awaitsVerdict) {
    unawaited(
      cancelOutcomeAlert(
        archive.id,
        memory: FinishAlertMemory(providers.read(sharedPreferencesProvider)),
      ),
    );
  }
  return result;
}

/// The snack confirming what [writeVerdict] did.
String verdictSavedMessage(
  AppLocalizations l10n,
  PrintVerdict? verdict, {
  required bool applied,
}) => !applied
    ? l10n.outcomeUnsupported
    : switch (verdict) {
        PrintVerdict.good => l10n.outcomeSavedGood,
        PrintVerdict.reject => l10n.outcomeSavedReject,
        null => l10n.outcomeCleared,
      };

class OutcomeSheet extends ConsumerStatefulWidget {
  const OutcomeSheet({
    super.key,
    required this.archiveId,
    this.rejecting = false,
    this.runId,
  });

  final int archiveId;
  final bool rejecting;
  final int? runId;

  @override
  ConsumerState<OutcomeSheet> createState() => _OutcomeSheetState();
}

class _OutcomeSheetState extends ConsumerState<OutcomeSheet> {
  late bool _rejecting = widget.rejecting;
  String? _reason;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    return logTag(
      'sheet.outcome',
      SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          DashSpace.gutter,
          0,
          DashSpace.gutter,
          DashSpace.lg,
        ),
        child: dashAsync(
          context,
          switch (widget.runId) {
            null => ref.watch(archiveDetailProvider(widget.archiveId)),
            final runId => ref.watch(
              archiveRunDetailProvider((widget.archiveId, runId)),
            ),
          },
          onRetry: () => switch (widget.runId) {
            null => ref.invalidate(archiveDetailProvider(widget.archiveId)),
            final runId => ref.invalidate(
              archiveRunDetailProvider((widget.archiveId, runId)),
            ),
          },
          data: (archive) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.outcomeTitle, style: t.titleSm),
              const SizedBox(height: DashSpace.md),
              _FinishPhoto(archive: archive),
              const SizedBox(height: DashSpace.sm),
              Text(
                archive.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: t.bodyStrong,
              ),
              if (archive.userVerdict case final verdict?) ...[
                const SizedBox(height: DashSpace.xs),
                Text(
                  [
                    verdictLabel(l10n, verdict),
                    ?verdictSourceLabel(l10n, archive.userVerdictSource),
                  ].join(' · '),
                  textAlign: TextAlign.center,
                  style: t.labelSoft,
                ),
              ],
              const SizedBox(height: DashSpace.lg),
              if (_rejecting)
                ..._rejectStep(l10n, archive)
              else
                ..._verdictStep(l10n, archive),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _verdictStep(AppLocalizations l10n, Archive archive) {
    final verdict = archive.userVerdict;
    return [
      ButtonPair(
        primaryLabel: l10n.outcomeGood,
        secondaryLabel: l10n.outcomeReject,
        primary: logTag(
          'outcome.good',
          FilledButton.icon(
            icon: const Icon(Icons.thumb_up_alt_outlined),
            label: Text(l10n.outcomeGood),
            onPressed: _saving || verdict == PrintVerdict.good
                ? null
                : () =>
                      _save(archive, PrintVerdict.good, logId: 'outcome.good'),
          ),
        ),
        secondary: logTag(
          'outcome.reject',
          OutlinedButton.icon(
            icon: const Icon(Icons.thumb_down_alt_outlined),
            label: Text(l10n.outcomeReject),
            onPressed: _saving
                ? null
                : () => setState(() {
                    _rejecting = true;
                    _reason = archive.failureReason;
                  }),
          ),
        ),
      ),
      const SizedBox(height: DashSpace.xs),
      if (verdict == null)
        logTag(
          'outcome.later',
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.outcomeLater),
          ),
        )
      else
        logTag(
          'outcome.clear',
          TextButton(
            onPressed: _saving
                ? null
                : () => _save(archive, null, logId: 'outcome.clear'),
            child: Text(l10n.outcomeClear),
          ),
        ),
    ];
  }

  List<Widget> _rejectStep(AppLocalizations l10n, Archive archive) {
    final reprintBlock = ref.watch(
      archiveReprintBlockProvider(archive.createdById),
    );
    return [
      dashCombo<String>(
        context,
        id: 'outcome.reason',
        label: Text(l10n.outcomeRejectReason),
        initialSelection: _reason ?? archive.failureReason ?? '',
        onSelected: (v) => setState(() => _reason = v),
        entries: failureReasonEntries(
          l10n,
          none: l10n.outcomeNoReason,
          carries: archive.failureReason,
          ids: (
            none: 'outcome.reason.none',
            option: 'outcome.reason.option',
            legacy: 'outcome.reason.legacy',
          ),
        ),
      ),
      const SizedBox(height: DashSpace.md),
      ButtonPair(
        primaryLabel: l10n.outcomeSaveReject,
        secondaryLabel: l10n.outcomeRejectAndReprint,
        primary: logTag(
          'outcome.reject_save',
          FilledButton(
            onPressed: _saving
                ? null
                : () => _save(
                    archive,
                    PrintVerdict.reject,
                    reason: _reason ?? archive.failureReason,
                    logId: 'outcome.reject_save',
                  ),
            child: Text(l10n.outcomeSaveReject),
          ),
        ),
        secondary: logTag(
          'outcome.reject_reprint',
          OutlinedButton.icon(
            icon: const Icon(Icons.replay),
            label: Text(l10n.outcomeRejectAndReprint),
            onPressed: _saving || reprintBlock != null
                ? null
                : () => _save(
                    archive,
                    PrintVerdict.reject,
                    reason: _reason ?? archive.failureReason,
                    reprint: true,
                    logId: 'outcome.reject_reprint',
                  ),
          ),
        ),
      ),
      if (reprintBlock != null)
        Padding(
          padding: const EdgeInsets.only(top: DashSpace.xs),
          child: Text(
            reprintBlock.reason(l10n),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      const SizedBox(height: DashSpace.xs),
      logTag(
        'outcome.back',
        TextButton(
          onPressed: _saving ? null : () => setState(() => _rejecting = false),
          child: Text(l10n.back),
        ),
      ),
    ];
  }

  /// Writes [verdict] (null clears it) and closes the sheet once it landed.
  Future<void> _save(
    Archive archive,
    PrintVerdict? verdict, {
    required String logId,
    String? reason,
    bool reprint = false,
  }) async {
    // Two taps in one frame both get here before the rebuild disables the
    // buttons, and two verdicts in flight land in whichever order they like.
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    // The sheet can be dismissed while the PATCH is out, and the server
    // stores the verdict anyway.
    final (:providers, :messenger) = detachFrom(context);
    final navigator = Navigator.of(context);
    // The reprint form opens on whatever pushed this sheet, which outlives it.
    final host = Navigator.of(context).context;
    setState(() => _saving = true);
    try {
      final result = await writeVerdict(
        providers,
        archive,
        verdict,
        reason: reason,
        runId: widget.runId,
      );
      messenger.snack(
        verdictSavedMessage(l10n, verdict, applied: result.applied),
      );
      // Only while this sheet is still the route: dismissed during the
      // request, the navigator's top is somebody else's screen.
      if (mounted) navigator.pop();
      if (reprint && result.applied && host.mounted) {
        unawaited(openQueueCreate(host, draft: archiveQueueDraft(archive)));
      }
    } on AppApiException catch (e) {
      showApiFailure(mounted ? messenger : null, e, l10n, action: logId);
      if (mounted) setState(() => _saving = false);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      rethrow;
    }
  }
}

/// The shot the server takes off the camera as the print ends — `photos[0]`,
/// which the finish photo is prepended as (server #1397) — or the model's
/// thumbnail when the printer has no camera.
class _FinishPhoto extends StatelessWidget {
  const _FinishPhoto({required this.archive});

  final Archive archive;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final photo = archive.photos.firstOrNull;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DashRadius.lg),
        child: ColoredBox(
          color: t.subCard,
          child: photo == null
              ? Center(
                  child: PrintThumbnail(
                    archiveId: archive.id,
                    size: DashSize.d128,
                  ),
                )
              : MediaImage(
                  path: Endpoints.archivePhoto(archive.id, photo),
                  fit: BoxFit.contain,
                  placeholder: (_) => Center(
                    child: Icon(Icons.image_outlined, color: t.textTertiary),
                  ),
                ),
        ),
      ),
    );
  }
}
