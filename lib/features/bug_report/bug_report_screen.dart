import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/diagnostics/log_store.dart' show recordingLimit;
import '../../core/diagnostics/log_summary.dart';
import '../../core/diagnostics/log_tag.dart';
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final controller = ref.read(bugReportProvider.notifier);
    final log = ref.watch(bugReportProvider).log ?? '';
    final summary = controller.summarise();

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
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      foregroundColor: t.danger,
                    ),
                    onPressed: () => _confirmDiscard(context, controller, l10n),
                    child: Text(l10n.bugReportDiscard),
                  ).tagged('bug_report.discard'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    icon: const Icon(Icons.save_alt_rounded, size: 18),
                    label: Text(l10n.bugReportSave),
                    onPressed: _save,
                  ).tagged('bug_report.save'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
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
    // The app's own dialog, not a hand-rolled one: it gives the confirmation a
    // filled, red button, so the destructive answer does not look like the way
    // out. It also names both buttons in the log.
    final confirmed = await confirmDialog(
      context,
      title: l10n.bugReportDiscardQuestion,
      message: l10n.bugReportDiscardBody,
      confirmLabel: l10n.bugReportDiscard,
      destructive: true,
      id: 'bug_report.discard',
    );
    if (confirmed) await controller.discard();
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
