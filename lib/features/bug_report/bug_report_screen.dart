import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/diagnostics/log_store.dart' show recordingLimit;
import '../../core/diagnostics/log_summary.dart';
import '../../core/diagnostics/log_tag.dart';
import 'package:app_report_client/app_report_client.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/confirm_dialog.dart';
import '../common/dash_progress.dart';
import '../common/dash_snack.dart';
import '../common/device_files.dart';
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

/// Where all three kinds start. A bug goes on to record; a change or feature
/// request is written and sent from here, because there is nothing about the app
/// running that would settle it.
class _IdleView extends ConsumerStatefulWidget {
  const _IdleView();

  @override
  ConsumerState<_IdleView> createState() => _IdleViewState();
}

class _IdleViewState extends ConsumerState<_IdleView> {
  final _description = TextEditingController();

  /// Ticks the countdown while a queued request waits out the relay's delay —
  /// the same job [_ReviewViewState] does for a bug report.
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
        ? Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}))
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(bugReportProvider);
    final recovered = state.recovered;
    _syncTicker(state.send.phase);

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
        _KindChoice(
          kind: state.kind,
          onChanged: ref.read(bugReportProvider.notifier).chooseKind,
        ),
        const SizedBox(height: 12),
        if (state.kind.needsLog) ...[
          // A request queued a moment ago is still on its way out, and switching
          // tabs does not call it off. Shown here too, or the countdown would run
          // on a screen that says nothing about it and the one control that can
          // still stop it would be a tab away.
          if (state.send.phase == SendPhase.waiting ||
              state.send.phase == SendPhase.sending) ...[
            _SendStatus(send: state.send),
            if (state.send.phase == SendPhase.waiting) const _CancelSend(),
            const SizedBox(height: 12),
          ],
          ..._bugSteps(l10n),
        ] else
          ..._requestForm(l10n, state),
      ],
    );
  }

  List<Widget> _bugSteps(AppLocalizations l10n) => [
        _Card(
          title: l10n.bugReportIntroHeader,
          rows: [
            _Step(1, l10n.bugReportStepRecord),
            _Step(2, l10n.bugReportStepReproduce),
            _Step(3, l10n.bugReportStepFinish),
          ],
        ),
        const SizedBox(height: 12),
        _Card(
          title: l10n.bugReportPrivacyHeader,
          icon: Icons.lock_outline_rounded,
          rows: [
            _Fact.kept(l10n.bugReportLogScreens),
            _Fact.kept(l10n.bugReportLogRequests),
            // The one nobody expects to be in there, and the reason the old
            // version of this card needed a warning box of its own.
            _Fact.kept(l10n.bugReportLogService),
            _Fact.kept(l10n.bugReportLogErrors),
            _Fact.kept(l10n.bugReportLogSetup),
            _Fact.never(l10n.bugReportLogNoKey),
            _Fact.never(l10n.bugReportLogNoTyping),
            _Fact.never(l10n.bugReportLogNoAddress),
            _Fact.never(l10n.bugReportLogNoData),
          ],
          note: l10n.bugReportReviewFirst,
        ),
        const SizedBox(height: 20),
        logTag(
          'bug_report.start',
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            icon: const Icon(Icons.fiber_manual_record_rounded, size: 16),
            label: Text(l10n.bugReportStart),
            onPressed: _start,
          ),
        ),
      ];

  List<Widget> _requestForm(AppLocalizations l10n, BugReportState state) {
    final feature = state.kind == ReportKind.feature;
    final sent = state.send.phase == SendPhase.sent;
    return [
      _Card(
        title:
            feature ? l10n.bugReportFeatureHeader : l10n.bugReportChangeHeader,
        body: feature ? l10n.bugReportFeatureBody : l10n.bugReportChangeBody,
        icon: feature ? Icons.lightbulb_outline_rounded : Icons.tune_rounded,
      ),
      const SizedBox(height: 12),
      _Card(
        title: l10n.bugReportRequestPrivacyHeader,
        icon: Icons.lock_outline_rounded,
        rows: [
          _Fact.kept(l10n.bugReportRequestWhatYouWrite),
          // Named because it is the one thing about the phone that bears on an
          // idea: whether it is already done in a build the user does not have.
          _Fact.kept(l10n.bugReportRequestVersions),
          _Fact.never(l10n.bugReportRequestNoLog),
          _Fact.never(l10n.bugReportRequestNoData),
        ],
        note: l10n.bugReportRequestPublic,
      ),
      const SizedBox(height: 16),
      _DescriptionField(
        controller: _description,
        // Frozen once the report is queued: what waits on disk is a copy, so
        // typing on would edit something that is no longer what gets sent.
        enabled: state.send.phase == SendPhase.idle ||
            state.send.phase == SendPhase.failed,
        label: feature ? l10n.bugReportFeatureLabel : l10n.bugReportChangeLabel,
        hint: feature ? l10n.bugReportFeatureHint : l10n.bugReportChangeHint,
        // Where a request's ticket is bought, so the relay's delay runs while
        // the sentence is being finished rather than after the send tap.
        onChanged: ref.read(bugReportProvider.notifier).describingRequest,
      ),
      _SendStatus(send: state.send),
      const SizedBox(height: 8),
      if (sent)
        _SentActions(
          url: state.send.issueUrl,
          body: l10n.bugReportRequestSentBody,
          onDone: _finishRequest,
        )
      else ...[
        _SendButton(send: state.send, onSend: _sendRequest),
        // Only while something is queued. Before that there is nothing to call
        // off, and afterwards the relay already has it.
        if (state.send.phase == SendPhase.waiting) ...[
          const SizedBox(height: 8),
          const _CancelSend(),
        ],
      ],
    ];
  }

  /// Refuses an empty request rather than disabling the button, for the same
  /// reason the bug flow does: a dead button explains nothing.
  Future<void> _sendRequest() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final description = _description.text.trim();
    if (description.isEmpty) {
      messenger.snack(l10n.bugReportRequestRequired, replaceCurrent: true);
      return;
    }
    // False means the app could not even describe itself — nothing was queued,
    // so nothing downstream will ever put a failure on the screen.
    if (await ref.read(bugReportProvider.notifier).sendRequest(description)) {
      return;
    }
    messenger.snack(l10n.bugReportRequestNotPrepared, replaceCurrent: true);
  }

  /// Nothing to delete here — a request leaves no recording behind — so this
  /// only clears the form and hands the user back.
  void _finishRequest() {
    final l10n = AppLocalizations.of(context);
    final home = ref.read(serverProfileProvider) == null ? '/setup' : '/';
    ScaffoldMessenger.of(context).snack(l10n.bugReportSent, replaceCurrent: true);
    _description.clear();
    ref.read(bugReportProvider.notifier).reset();
    GoRouter.of(context).go(home);
  }

  /// Hands the app straight back to the user: the bug waits on the screen they
  /// came from, not here. `go` rather than `pop`, because this screen is reached
  /// from the drawer and the recording bar pushes it again when the user
  /// finishes. Without a server profile the dashboard would bounce off the
  /// router's redirect, so a pre-setup recording goes back to setup — which is
  /// the screen worth recording in that case.
  Future<void> _start() async {
    final home = ref.read(serverProfileProvider) == null ? '/setup' : '/';
    await ref.read(bugReportProvider.notifier).start();
    if (mounted) context.go(home);
  }
}

/// The first decision: a bug, which is settled by evidence, or a request, which
/// is settled by argument. It is what decides whether anything gets recorded at
/// all.
class _KindChoice extends StatelessWidget {
  const _KindChoice({required this.kind, required this.onChanged});

  final ReportKind kind;
  final ValueChanged<ReportKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            l10n.bugReportKindQuestion,
            style: t.bodyBold,
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ReportKind>(
            segments: [
              ButtonSegment(
                value: ReportKind.bug,
                icon: const Icon(Icons.bug_report_outlined, size: 16),
                label: Text(l10n.bugReportKindBug),
              ),
              ButtonSegment(
                value: ReportKind.change,
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: Text(l10n.bugReportKindChange),
              ),
              ButtonSegment(
                value: ReportKind.feature,
                icon: const Icon(Icons.lightbulb_outline_rounded, size: 16),
                label: Text(l10n.bugReportKindFeature),
              ),
            ],
            selected: {kind},
            showSelectedIcon: false,
            onSelectionChanged: (picked) => onChanged(picked.first),
          ),
        ).tagged('bug_report.kind'),
      ],
    );
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
              ScaffoldMessenger.of(context).snack(l10n.bugReportMarked, replaceCurrent: true);
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
      messenger.snack(l10n.bugReportDescriptionRequired, replaceCurrent: true);
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
      case DeviceFileOutcome.cancelled:
        return;
      case DeviceFileOutcome.failed:
        messenger.snack(l10n.bugReportSaveFailed, replaceCurrent: true);
      case DeviceFileOutcome.done:
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
    messenger.snack(message, replaceCurrent: true);
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
  const _DescriptionField({
    required this.controller,
    required this.enabled,
    this.label,
    this.hint,
    this.onChanged,
  });

  final TextEditingController controller;

  /// Typing is what tells a request apart from a look around, so this fires on
  /// it rather than on the choice that opened the field.
  final VoidCallback? onChanged;

  /// False once the report has been handed over. What is queued is a copy, so
  /// carrying on typing would edit something that is no longer what gets sent.
  final bool enabled;

  /// Defaults to the bug wording. A request asks for something that does not
  /// exist yet, so "what went wrong" would be the wrong question.
  final String? label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextField(
      controller: controller,
      enabled: enabled,
      onChanged: onChanged == null ? null : (_) => onChanged!(),
      minLines: 3,
      maxLines: 5,
      // The relay's own ceiling. Counted here so the limit is visible while
      // typing rather than arriving as a rejection after the tap.
      maxLength: 2000,
      textCapitalization: TextCapitalization.sentences,
      keyboardType: TextInputType.multiline,
      decoration: InputDecoration(
        labelText: label ?? l10n.bugReportDescriptionLabel,
        hintText: hint ?? l10n.bugReportDescriptionHint,
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
      // The kind of the report that failed, not the tab in front of the user:
      // every fallback the bug wording offers is about the log, and a request
      // has none.
      SendPhase.failed => _Failed(failure: send.failure, kind: send.kind),
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
                  style: t.labelSoft.copyWith(color: t.textSecondary, height: 1.4),
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
          const DashSpinner(size: 12),
          const SizedBox(width: 8),
          Text(
            l10n.bugReportSending,
            style: t.labelSoft.copyWith(color: t.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.failure, required this.kind});

  final RelayFailure? failure;
  final ReportKind kind;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        kind.needsLog
            ? _failureText(AppLocalizations.of(context), failure)
            : _requestFailureText(AppLocalizations.of(context), failure),
        style: t.labelSoft.copyWith(color: t.danger, height: 1.4),
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

  /// The same failures, minus every "save the log to a file" — there is no log
  /// behind a request, so that advice would send the reader looking for a file
  /// that was never written.
  static String _requestFailureText(
    AppLocalizations l10n,
    RelayFailure? failure,
  ) =>
      switch (failure) {
        RelayFailure.notYet => l10n.bugReportRequestFailedNotYet,
        RelayFailure.duplicate => l10n.bugReportSendFailedDuplicate,
        RelayFailure.unreachable => l10n.bugReportRequestFailedUnreachable,
        RelayFailure.demo => l10n.bugReportRequestFailedDemo,
        // Both dead ends, and both leave the user the same one way through:
        // GitHub's own form.
        RelayFailure.refused ||
        RelayFailure.rejected ||
        null =>
          l10n.bugReportRequestFailedRefused,
      };
}

/// Calls off a queued report before the relay gets it. Rendered only while one
/// is actually waiting — on either tab, because switching tabs does not cancel.
class _CancelSend extends ConsumerWidget {
  const _CancelSend();

  @override
  Widget build(BuildContext context, WidgetRef ref) => TextButton(
        onPressed: ref.read(bugReportProvider.notifier).cancelSend,
        child: Text(AppLocalizations.of(context).bugReportCancelSend),
      ).tagged('bug_report.cancel_send');
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
  const _SentActions({required this.url, required this.onDone, this.body});

  final String? url;
  final VoidCallback onDone;

  /// Defaults to the bug wording, which promises an attached log a request does
  /// not have.
  final String? body;

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
                '${l10n.bugReportSent} — ${body ?? l10n.bugReportSentBody}',
                style: t.labelSoft.copyWith(color: t.textSecondary, height: 1.4),
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
            style: t.bodyBold.copyWith(color: t.textPrimary),
          ),
          if (summary.markers > 0) ...[
            const SizedBox(height: 4),
            Text(
              l10n.bugReportMarkers(summary.markers),
              style: t.labelSoft.copyWith(color: t.accentGreen),
            ),
          ],
          if (summary.truncated) ...[
            const SizedBox(height: 4),
            Text(
              l10n.bugReportTruncated,
              style: t.labelSoft.copyWith(color: t.accentOrange),
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
    final detailStyle = t.monoMicro.copyWith(color: t.textSecondary);

    final headerStyle = t.monoLabel.copyWith(color: line.isError || line.isWarning ? accent : t.textPrimary);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 54,
            child: Text(
              line.offset,
              style: t.monoMicro,
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
            style: t.monoMicro.copyWith(color: t.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    this.body,
    this.rows = const [],
    this.note,
    this.icon,
    this.footer,
  });

  final String title;

  /// A short lead. Optional, because most of these cards are better as [rows]:
  /// a consent notice nobody reads is worse consent than a list of six lines
  /// somebody skims.
  final String? body;

  /// The card's content as one scannable line each.
  final List<Widget> rows;

  /// A closing line under the rows, for the one thing that is not a fact about
  /// the list above it.
  final String? note;

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
                  style: t.bodyBold.copyWith(color: t.textPrimary),
                ),
              ),
            ],
          ),
          if (body case final String lead) ...[
            const SizedBox(height: 8),
            Text(
              lead,
              style: t.bodyPlain.copyWith(height: 1.45),
            ),
          ],
          if (rows.isNotEmpty) ...[const SizedBox(height: 10), ...rows],
          if (note case final String closing) ...[
            const SizedBox(height: 10),
            Text(
              closing,
              style: t.label.copyWith(height: 1.4),
            ),
          ],
          if (footer != null) ...[const SizedBox(height: 14), footer!],
        ],
      ),
    );
  }
}

/// One line of a card's list, with a mark in front of it.
///
/// The marks do the work a sub-heading would otherwise do: a tick is something
/// the report carries, a cross is something it does not. Both are good news
/// here, so the cross is grey rather than red — it is not a warning, it is the
/// half of the promise the reader came for.
class _Fact extends StatelessWidget {
  const _Fact(this.text, {required this.included});

  const _Fact.kept(String text) : this(text, included: true);
  const _Fact.never(String text) : this(text, included: false);

  final String text;
  final bool included;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              included ? Icons.check_rounded : Icons.close_rounded,
              size: 15,
              color: included ? t.accentGreen : t.textTertiary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: t.bodyPlain.copyWith(color: included ? t.textSecondary : t.textTertiary, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// A numbered step. Three of these replace the paragraph that used to explain
/// the same three things in prose.
class _Step extends StatelessWidget {
  const _Step(this.number, this.text);

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.cardBorder,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$number',
              style: t.monoLabel.copyWith(color: t.textSecondary),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                text,
                style: t.body.copyWith(color: t.textSecondary, height: 1.35),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
