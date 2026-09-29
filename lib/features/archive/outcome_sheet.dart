import 'dart:async';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/archive.dart';
import '../../core/models/queue_item.dart';
import '../../core/notifications/finish_alert_memory.dart';
import '../../core/notifications/outcome_alert.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import '../common/dash_async.dart';
import '../common/dash_input.dart';
import '../common/detached_flow.dart';
import '../common/media_image.dart';
import '../common/print_run_labels.dart';
import '../common/print_thumbnail.dart';
import '../queue/queue_edit_screen.dart';
import 'archive_providers.dart';
import 'print_outcome.dart';

/// The queue draft a reprint of [archive] starts from. The archive's own
/// printer is a starting point, not a decision — the form lists every printer
/// and the user can switch before anything is created.
QueueItem archiveQueueDraft(Archive archive, {bool manualStart = false}) =>
    QueueItem.draft(
      archiveId: archive.id,
      name: archive.displayName,
      thumbnail: archive.thumbnailPath,
      printerId: archive.printerId,
      filamentType: archive.filamentType,
      filamentColor: archive.filamentColor,
      slicedForModel: archive.slicedForModel,
      // The plate this print ran on, so a reprint runs the same one. Null on
      // a single-plate file and on servers that do not report it, which is
      // what the form and the server both read as plate 1.
      plateId: archive.plateId,
      manualStart: manualStart,
      // Sticky on the server: a reprint of an archive that asked asks again.
      confirmOutcome: archive.confirmRequested,
    );

/// "How did your print come out?" for one archive: the finish photo, Good or
/// Reject, and for a reject an optional reason and a reprint.
///
/// Opened from the archive, from the server's `print_confirm_request` while
/// the app is on screen, and from the outcome notification. The archive is
/// re-read rather than handed in: the finish photo is attached after the print
/// ends, and a prompt can be answered elsewhere while this one waits.
Future<void> showOutcomeSheet(BuildContext context, int archiveId) =>
    dashSheet<void>(
      context,
      builder: (_) => OutcomeSheet(archiveId: archiveId),
    );

class OutcomeSheet extends ConsumerStatefulWidget {
  const OutcomeSheet({super.key, required this.archiveId});

  final int archiveId;

  @override
  ConsumerState<OutcomeSheet> createState() => _OutcomeSheetState();
}

class _OutcomeSheetState extends ConsumerState<OutcomeSheet> {
  bool _rejecting = false;
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
          ref.watch(archiveDetailProvider(widget.archiveId)),
          onRetry: () =>
              ref.invalidate(archiveDetailProvider(widget.archiveId)),
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

  List<Widget> _rejectStep(AppLocalizations l10n, Archive archive) => [
    dashCombo<String>(
      context,
      id: 'outcome.reason',
      label: Text(l10n.outcomeRejectReason),
      initialSelection: _reason ?? '',
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
                  reason: _reason,
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
          onPressed: _saving
              ? null
              : () => _save(
                  archive,
                  PrintVerdict.reject,
                  reason: _reason,
                  reprint: true,
                  logId: 'outcome.reject_reprint',
                ),
        ),
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

  /// Writes [verdict] (null clears it) and closes the sheet once it landed.
  ///
  /// The cause goes with a reject as chosen — "No reason" included, which
  /// clears one the print still carries. Leaving a reject clears its cause,
  /// as the web's edit dialog does; anything else leaves it alone.
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
    final chosen = (reason ?? '').isEmpty ? null : reason;
    final carried = archive.failureReason != null;
    // The sheet can be dismissed while the PATCH is out, and the server
    // stores the verdict anyway.
    final (:providers, :messenger) = detachFrom(context);
    final navigator = Navigator.of(context);
    // The reprint form opens on whatever pushed this sheet, which outlives it.
    final host = Navigator.of(context).context;
    setState(() => _saving = true);
    try {
      final result = await providers
          .read(archiveRepositoryProvider)
          .setVerdict(
            archive.id,
            verdict,
            reason: chosen,
            clearReason: verdict == PrintVerdict.reject
                ? chosen == null && carried
                : archive.userVerdict == PrintVerdict.reject && carried,
          );
      // Only a list somebody is looking at: building it here would fetch every
      // archive the server has to change one row.
      if (providers.exists(archiveProvider)) {
        providers.read(archiveProvider.notifier).replace(result.archive);
      }
      // Answered here, so the notification asking the same thing has nothing
      // left to ask.
      if (result.applied) {
        unawaited(
          cancelOutcomeAlert(
            archive.id,
            memory: FinishAlertMemory(
              providers.read(sharedPreferencesProvider),
            ),
          ),
        );
      }
      messenger.snack(
        !result.applied
            ? l10n.outcomeUnsupported
            : switch (verdict) {
                PrintVerdict.good => l10n.outcomeSavedGood,
                PrintVerdict.reject => l10n.outcomeSavedReject,
                null => l10n.outcomeCleared,
              },
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
        borderRadius: BorderRadius.circular(16),
        child: ColoredBox(
          color: t.subCard,
          child: photo == null
              ? Center(child: PrintThumbnail(archiveId: archive.id, size: 120))
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
