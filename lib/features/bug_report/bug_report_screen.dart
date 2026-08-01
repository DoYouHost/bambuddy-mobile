import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/diagnostics/log_store.dart' show recordingLimit;
import '../../core/diagnostics/log_summary.dart';
import '../../core/diagnostics/log_tag.dart';
import '../../core/diagnostics/relay_client.dart';
import '../../core/diagnostics/report_sender.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/confirm_dialog.dart';
import 'bug_report_controller.dart';
import 'log_export.dart';
import 'log_preview.dart';

/// Guided bug report: explain → record → review. Recording itself lives in
/// [BugReportController] and keeps running while the user leaves this screen
/// to reproduce the problem; the recording bar is what follows them there.
class BugReportScreen extends ConsumerWidget {
  const BugReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(bugReportProvider);

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(context, title: l10n.bugReportTitle),
        body: switch (state.phase) {
          BugReportPhase.idle => const _IdleView(),
          BugReportPhase.recording => const _RecordingView(),
          BugReportPhase.review => const _ReviewView(),
        },
      ),
    );
  }
}

class _IdleView extends ConsumerWidget {
  const _IdleView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final recovered = ref.watch(
      bugReportProvider.select((s) => s.recovered),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // First on the screen when it is there: whoever the app crashed on came
        // here to report exactly that.
        if (recovered != null) ...[
          _Card(
            title: l10n.bugReportRecoveredHeader,
            body: l10n.bugReportRecoveredBody,
            icon: Icons.restore_rounded,
            footer: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: () =>
                        ref.read(bugReportProvider.notifier).dropRecovered(),
                    child: Text(l10n.bugReportDiscard),
                  ).tagged('bug_report.recovered_discard'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed:
                        ref.read(bugReportProvider.notifier).showRecovered,
                    child: Text(l10n.bugReportShow),
                  ).tagged('bug_report.recovered_show'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        _Card(
          title: l10n.bugReportIntroHeader,
          body: l10n.bugReportIntroBody,
        ),
        const SizedBox(height: 12),
        _Card(
          title: l10n.bugReportPrivacyHeader,
          body: l10n.bugReportPrivacyBody,
          icon: Icons.lock_outline_rounded,
        ),
        const SizedBox(height: 12),
        _Note(l10n.bugReportPending),
        const SizedBox(height: 20),
        logTag(
          'bug_report.start',
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            icon: const Icon(Icons.fiber_manual_record_rounded, size: 16),
            label: Text(l10n.bugReportStart),
            onPressed: () => _start(context, ref),
          ),
        ),
      ],
    );
  }

  /// Hands the app straight back to the user: the bug waits on the screen they
  /// came from, not here. `go` rather than `pop`, because this screen is reached
  /// from the drawer and the recording bar pushes it again when the user
  /// finishes. Without a server profile the dashboard would bounce off the
  /// router's redirect, so a pre-setup recording goes back to setup — which is
  /// the screen worth recording in that case.
  Future<void> _start(BuildContext context, WidgetRef ref) async {
    final home = ref.read(serverProfileProvider) == null ? '/setup' : '/';
    await ref.read(bugReportProvider.notifier).start();
    if (context.mounted) context.go(home);
  }
}

class _RecordingView extends ConsumerWidget {
  const _RecordingView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return ListView(
      // Clears the recording bar floating above this screen.
      padding: const EdgeInsets.fromLTRB(16, 64, 16, 24),
      children: [
        _Card(
          title: l10n.bugReportRecordingHeader,
          body: '${l10n.bugReportRecordingBody}\n\n'
              '${l10n.bugReportLimit(recordingLimit.inMinutes)}',
          icon: Icons.fiber_manual_record_rounded,
        ),
        const SizedBox(height: 20),
        // Tagged like the bar's own button so the probe skips it: the mark is
        // already recorded as `user_marker`.
        logTag(
          'bug_report.mark',
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            icon: const Icon(Icons.bookmark_add_outlined, size: 18),
            label: Text(l10n.bugReportMark),
            onPressed: () {
              ref.read(bugReportProvider.notifier).mark();
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(l10n.bugReportMarked)));
            },
          ),
        ),
      ],
    );
  }
}

class _ReviewView extends ConsumerStatefulWidget {
  const _ReviewView();

  @override
  ConsumerState<_ReviewView> createState() => _ReviewViewState();
}

class _ReviewViewState extends ConsumerState<_ReviewView> {
  bool _raw = false;
  final _description = TextEditingController();

  /// Ticks the countdown while a queued report waits out its delay. One timer
  /// for the screen rather than a rebuild per frame; nothing else here changes
  /// every second.
  Timer? _tick;

  @override
  void dispose() {
    _description.dispose();
    _tick?.cancel();
    super.dispose();
  }

  void _syncTicker(SendPhase phase) {
    final needed = phase == SendPhase.waiting;
    if (needed == (_tick != null)) return;
    _tick?.cancel();
    _tick = needed
        ? Timer.periodic(
            const Duration(seconds: 1),
            (_) => setState(() {}),
          )
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final controller = ref.read(bugReportProvider.notifier);
    final state = ref.watch(bugReportProvider);
    final log = state.log ?? '';
    final summary = controller.summarise();
    _syncTicker(state.send.phase);

    if (summary.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.bugReportEmpty, textAlign: TextAlign.center),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              _Card(
                title: l10n.bugReportReviewHeader,
                body: l10n.bugReportReviewBody,
              ),
              const SizedBox(height: 12),
              // Above the log rather than under the actions: it decides what
              // everything below is *for*, and a five-line text field pinned to
              // the bottom would leave the log itself a strip between the
              // keyboard and the buttons.
              _DestinationChoice(
                destination: state.destination,
                onChanged: controller.chooseDestination,
              ),
              if (state.destination == ReportDestination.issue) ...[
                const SizedBox(height: 12),
                // Editable again after a dead end: the sender drops the queued
                // copy then, so the next attempt is genuinely a fresh report.
                _DescriptionField(
                  controller: _description,
                  enabled: state.send.phase == SendPhase.idle ||
                      state.send.phase == SendPhase.failed,
                ),
                _SendStatus(send: state.send),
              ],
              const SizedBox(height: 12),
              _SummaryCard(summary: summary),
              const SizedBox(height: 12),
              TextButton.icon(
                icon: Icon(_raw
                    ? Icons.visibility_off_outlined
                    : Icons.code_rounded),
                label: Text(
                  _raw ? l10n.bugReportHideRaw : l10n.bugReportShowRaw,
                ),
                onPressed: () => setState(() => _raw = !_raw),
              ).tagged('bug_report.toggle_raw'),
              if (_raw)
                _RawBlock(log: log)
              else
                for (final line in summary.lines) _LineRow(line: line),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: state.send.phase == SendPhase.sent
                ? _SentActions(
                    url: state.send.issueUrl,
                    onDone: () => _finish(
                      ScaffoldMessenger.of(context),
                      l10n.bugReportSent,
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 48),
                            foregroundColor: t.danger,
                          ),
                          onPressed: () =>
                              _confirmDiscard(context, controller, l10n),
                          child: Text(l10n.bugReportDiscard),
                        ).tagged('bug_report.discard'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: state.destination == ReportDestination.file
                            ? FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 48),
                                ),
                                icon: const Icon(Icons.save_alt_rounded,
                                    size: 18),
                                // Short, because the choice above already says
                                // "save to a file" and two controls with the
                                // same words are two things to tell apart.
                                label: Text(l10n.bugReportSaveShort),
                                onPressed: _save,
                              ).tagged('bug_report.save')
                            : _SendButton(
                                send: state.send,
                                onSend: _send,
                              ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  /// Refuses an empty description rather than disabling the button: a disabled
  /// button with no explanation is a dead end, and the reason only matters at
  /// the moment somebody tries.
  Future<void> _send() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final description = _description.text.trim();
    if (description.isEmpty) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(l10n.bugReportDescriptionRequired)),
        );
      return;
    }
    await ref.read(bugReportProvider.notifier).sendToIssue(description);
  }

  /// The whole session goes into the file — the only way out of the app, and
  /// `log_export.dart` says why the clipboard is not the other one.
  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(logFileSaverProvider)(
      fileName: logFileName(DateTime.now()),
      log: ref.read(bugReportProvider).log ?? '',
      dialogTitle: l10n.bugReportSave,
    );
    if (!mounted) return;
    switch (result) {
      // Backing out of the picker is an answer, not a failure: nothing to say,
      // and the review stays open.
      case LogSaveResult.cancelled:
        return;
      case LogSaveResult.failed:
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(l10n.bugReportSaveFailed)));
      case LogSaveResult.saved:
        await _finish(messenger, l10n.bugReportSaved);
    }
  }

  /// The log left the app, in a file the user picked. The app's own copy has no
  /// reason to outlive that, so the session's files go and the user is handed
  /// back to where the bug happened. The router is taken before the await:
  /// discarding rebuilds this screen away.
  Future<void> _finish(
    ScaffoldMessengerState messenger,
    String message,
  ) async {
    final router = GoRouter.of(context);
    final home = ref.read(serverProfileProvider) == null ? '/setup' : '/';
    final controller = ref.read(bugReportProvider.notifier);
    // Shown by the messenger above the routes, so it survives the trip back.
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    await controller.discard();
    router.go(home);
  }

  Future<void> _confirmDiscard(
    BuildContext context,
    BugReportController controller,
    AppLocalizations l10n,
  ) async {
    // Once a report is queued, discarding does one thing more than it says on
    // the button, so the dialog has to say it: the send is called off too.
    final queued = switch (ref.read(bugReportProvider).send.phase) {
      SendPhase.waiting || SendPhase.sending => true,
      _ => false,
    };
    // The app's own dialog, not a hand-rolled one: it gives the confirmation a
    // filled, red button, so the destructive answer does not look like the way
    // out. It also names both buttons in the log.
    final confirmed = await confirmDialog(
      context,
      title: l10n.bugReportDiscardQuestion,
      message: queued
          ? l10n.bugReportDiscardBodyQueued
          : l10n.bugReportDiscardBody,
      confirmLabel: l10n.bugReportDiscard,
      destructive: true,
      id: 'bug_report.discard',
    );
    if (confirmed) await controller.discard();
  }
}

/// The one decision on this screen: the log stays on the phone, or it becomes a
/// public issue. Spelled out rather than implied by a button label — the second
/// option is irreversible and the first one is not.
class _DestinationChoice extends StatelessWidget {
  const _DestinationChoice({required this.destination, required this.onChanged});

  final ReportDestination destination;
  final ValueChanged<ReportDestination> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final toIssue = destination == ReportDestination.issue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ReportDestination>(
            segments: [
              ButtonSegment(
                value: ReportDestination.file,
                icon: const Icon(Icons.save_alt_rounded, size: 16),
                label: Text(l10n.bugReportDestinationFile),
              ),
              ButtonSegment(
                value: ReportDestination.issue,
                icon: const Icon(Icons.bug_report_outlined, size: 16),
                label: Text(l10n.bugReportDestinationIssue),
              ),
            ],
            selected: {destination},
            showSelectedIcon: false,
            onSelectionChanged: (picked) => onChanged(picked.first),
          ),
        ).tagged('bug_report.destination'),
        const SizedBox(height: 8),
        Text(
          toIssue
              ? l10n.bugReportDestinationIssueBody
              : l10n.bugReportDestinationFileBody,
          style: TextStyle(
            fontFamily: DashTokens.fontUi,
            fontSize: 12,
            height: 1.4,
            // The public, permanent option says so in the colour the app uses
            // for "read this before you tap it".
            color: toIssue ? t.accentOrange : t.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _DescriptionField extends StatelessWidget {
  const _DescriptionField({required this.controller, required this.enabled});

  final TextEditingController controller;

  /// False once the report has been handed over. What is queued is a copy, so
  /// carrying on typing would edit something that is no longer what gets sent.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextField(
      controller: controller,
      enabled: enabled,
      minLines: 3,
      maxLines: 5,
      // The relay's own ceiling. Counted here so the limit is visible while
      // typing rather than arriving as a rejection after the tap.
      maxLength: 2000,
      textCapitalization: TextCapitalization.sentences,
      keyboardType: TextInputType.multiline,
      decoration: InputDecoration(
        labelText: l10n.bugReportDescriptionLabel,
        hintText: l10n.bugReportDescriptionHint,
        border: const OutlineInputBorder(),
        alignLabelWithHint: true,
      ),
      // Not tagged with its text: what the user types never reaches the log.
    ).tagged('bug_report.description');
  }
}

/// What the sender is doing, under the description.
///
/// The wait gets a card of its own rather than a line of grey text: it is the
/// one thing on this screen the user did not ask for and cannot shorten, so
/// burying it reads as the app having quietly hung.
class _SendStatus extends StatelessWidget {
  const _SendStatus({required this.send});

  final SendState send;

  /// `m:ss`, because "167 s" is a number the reader has to convert themselves.
  static String clock(Duration left) {
    final seconds = left.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return switch (send.phase) {
      SendPhase.waiting => _Waiting(remaining: send.remaining),
      SendPhase.sending => const _Working(),
      SendPhase.failed => _Failed(failure: send.failure),
      SendPhase.idle || SendPhase.sent => const SizedBox.shrink(),
    };
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.remaining});

  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.subCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.subCardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule_rounded, size: 20, color: t.accentBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.bugReportSendWaiting(_SendStatus.clock(remaining)),
                  style: TextStyle(
                    // Mono, so the digits do not shuffle sideways every second.
                    fontFamily: DashTokens.fontMono,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.bugReportSendWaitingBody,
                  style: TextStyle(
                    fontFamily: DashTokens.fontUi,
                    fontSize: 12,
                    height: 1.4,
                    color: t.textSecondary,
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

class _Working extends StatelessWidget {
  const _Working();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            l10n.bugReportSending,
            style: TextStyle(
              fontFamily: DashTokens.fontUi,
              fontSize: 12,
              color: t.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.failure});

  final RelayFailure? failure;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        _failureText(AppLocalizations.of(context), failure),
        style: TextStyle(
          fontFamily: DashTokens.fontUi,
          fontSize: 12,
          height: 1.4,
          color: t.danger,
        ),
      ),
    );
  }

  static String _failureText(AppLocalizations l10n, RelayFailure? failure) =>
      switch (failure) {
        RelayFailure.notYet => l10n.bugReportSendFailedNotYet,
        RelayFailure.refused => l10n.bugReportSendFailedRefused,
        RelayFailure.duplicate => l10n.bugReportSendFailedDuplicate,
        RelayFailure.unreachable => l10n.bugReportSendFailedUnreachable,
        RelayFailure.demo => l10n.bugReportSendFailedDemo,
        RelayFailure.rejected || null => l10n.bugReportSendFailedRejected,
      };
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.send, required this.onSend});

  final SendState send;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Only while something is actually in flight. A queued report waiting out
    // its delay needs no second tap, and a failed one is worth retrying.
    final busy =
        send.phase == SendPhase.sending || send.phase == SendPhase.waiting;

    return FilledButton.icon(
      style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
      icon: const Icon(Icons.send_rounded, size: 18),
      label: Text(busy ? l10n.bugReportSending : l10n.bugReportSend),
      onPressed: busy ? null : onSend,
    ).tagged('bug_report.send');
  }
}

/// Replaces the actions once the issue exists: the URL is the one thing the user
/// cannot get back if this screen closes without showing it.
class _SentActions extends StatelessWidget {
  const _SentActions({required this.url, required this.onDone});

  final String? url;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final target = url;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle_outline_rounded,
                size: 16, color: t.accentGreen),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${l10n.bugReportSent} — ${l10n.bugReportSentBody}',
                style: TextStyle(
                  fontFamily: DashTokens.fontUi,
                  fontSize: 12,
                  height: 1.4,
                  color: t.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            if (target != null) ...[
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(l10n.bugReportOpenIssue),
                  onPressed: () => launchUrl(
                    Uri.parse(target),
                    mode: LaunchMode.externalApplication,
                  ),
                ).tagged('bug_report.open_issue'),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: onDone,
                child: Text(l10n.bugReportDone),
              ).tagged('bug_report.send_done'),
            ),
          ],
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final LogSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: t.cardGradient,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.bugReportSummary(
              summary.lines.length,
              summary.errors,
              summary.warnings,
            ),
            style: TextStyle(
              fontFamily: DashTokens.fontUi,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: t.textPrimary,
            ),
          ),
          if (summary.markers > 0) ...[
            const SizedBox(height: 4),
            Text(
              l10n.bugReportMarkers(summary.markers),
              style: TextStyle(
                fontFamily: DashTokens.fontUi,
                fontSize: 12,
                color: t.accentGreen,
              ),
            ),
          ],
          if (summary.truncated) ...[
            const SizedBox(height: 4),
            Text(
              l10n.bugReportTruncated,
              style: TextStyle(
                fontFamily: DashTokens.fontUi,
                fontSize: 12,
                color: t.accentOrange,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in summary.sourceCounts)
                DashPill(
                  label: '${entry.key} ${entry.value}',
                  accent: t.accentBlue,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One record in the review list — offset, source, event, then the extra fields
/// underneath, with the detail kept short until asked.
///
/// A record used to be a line or two. Since a response contributes one of its
/// own records in full, an `http response` is forty lines of body and pushes the
/// tap that caused it off the screen — and skimming for "where did it go wrong"
/// is the whole reason this list exists rather than the raw log. So the detail is
/// clamped, and a tap opens the one record the reader is actually looking at.
class _LineRow extends StatefulWidget {
  const _LineRow({required this.line});

  final LogLine line;

  @override
  State<_LineRow> createState() => _LineRowState();
}

class _LineRowState extends State<_LineRow> {
  /// Two lines: enough for a path and a status, which is what the short records
  /// were, and what makes a long one recognisable before opening it.
  static const _collapsedLines = 2;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final t = DashTokens.of(context);
    final accent = line.isError
        ? t.danger
        : line.isWarning
            ? t.accentOrange
            : line.isMarker
                ? t.accentGreen
                : t.textTertiary;
    final detailStyle = TextStyle(
      fontFamily: DashTokens.fontMono,
      fontSize: 11,
      color: t.textSecondary,
    );

    final headerStyle = TextStyle(
      fontFamily: DashTokens.fontMono,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: line.isError || line.isWarning ? accent : t.textPrimary,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 54,
            child: Text(
              line.offset,
              style: TextStyle(
                fontFamily: DashTokens.fontMono,
                fontSize: 11,
                color: t.textTertiary,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 4, right: 10),
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          Expanded(
            // The measurement needs the width the detail will actually be laid
            // out at, and the chevron needs the measurement, so both live inside
            // the builder: no state carried between frames, no width guessed
            // from paddings spelled out a second time.
            child: LayoutBuilder(
              builder: (context, constraints) {
                final clamped = line.detail.isNotEmpty &&
                    _overflows(line.detail, detailStyle, constraints.maxWidth);
                final block = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('${line.src} · ${line.evt}',
                              style: headerStyle),
                        ),
                        // Only where tapping does something: a chevron on a
                        // record that is already whole promises more than there is.
                        if (clamped)
                          Icon(
                            _expanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 16,
                            color: t.textTertiary,
                          ),
                      ],
                    ),
                    if (line.detail.isNotEmpty)
                      Text(
                        line.detail,
                        style: detailStyle,
                        maxLines: _expanded ? null : _collapsedLines,
                        overflow: _expanded
                            ? TextOverflow.clip
                            : TextOverflow.ellipsis,
                      ),
                  ],
                );
                if (!clamped) return block;
                return GestureDetector(
                  // Opaque so the whole block answers, including the gaps
                  // between its two lines of text.
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: block,
                ).tagged('bug_report.toggle_line');
              },
            ),
          ),
        ],
      ),
    );
  }

  static bool _overflows(String text, TextStyle style, double maxWidth) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: _collapsedLines,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    final overflows = painter.didExceedMaxLines;
    painter.dispose();
    return overflows;
  }
}

class _RawBlock extends StatelessWidget {
  const _RawBlock({required this.log});

  final String log;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final preview = logPreview(log);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.subCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.subCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (preview.hiddenChars > 0) ...[
            Text(
              // Rounded up, so a clip is never reported as zero.
              l10n.bugReportRawClipped((preview.hiddenChars + 1023) ~/ 1024),
              style: TextStyle(fontSize: 11, color: t.textTertiary),
            ),
            const SizedBox(height: 8),
          ],
          SelectableText(
            preview.text,
            style: TextStyle(
              fontFamily: DashTokens.fontMono,
              fontSize: 10,
              color: t.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.body,
    this.icon,
    this.footer,
  });

  final String title;
  final String body;
  final IconData? icon;

  /// Buttons belonging to this card, when it asks for a decision.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: t.cardGradient,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: t.textSecondary),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: DashTokens.fontUi,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(
              fontFamily: DashTokens.fontUi,
              fontSize: 13,
              height: 1.45,
              color: t.textSecondary,
            ),
          ),
          if (footer != null) ...[const SizedBox(height: 14), footer!],
        ],
      ),
    );
  }
}

/// Temporary: says out loud which sources are not instrumented yet, so a log
/// that looks thin is not mistaken for a broken recorder.
class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.subCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.subCardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.construction_rounded, size: 16, color: t.accentOrange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: DashTokens.fontUi,
                fontSize: 12,
                height: 1.4,
                color: t.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
