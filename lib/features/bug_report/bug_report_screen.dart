import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/diagnostics/log_summary.dart';
import '../../core/diagnostics/log_tag.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import 'bug_report_controller.dart';

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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
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

  /// Hands the app straight back to the user: the bug waits on the dashboard,
  /// not here. `go` rather than `pop`, because this screen is reached from the
  /// drawer and the recording bar pushes it again when the user finishes.
  Future<void> _start(BuildContext context, WidgetRef ref) async {
    await ref.read(bugReportProvider.notifier).start();
    if (context.mounted) context.go('/');
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
          body: l10n.bugReportRecordingBody,
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
              ),
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
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: Text(l10n.bugReportCopy),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: log));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(content: Text(l10n.bugReportCopied)),
                        );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDiscard(
    BuildContext context,
    BugReportController controller,
    AppLocalizations l10n,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.bugReportDiscardQuestion),
        content: Text(l10n.bugReportDiscardBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.bugReportDiscard),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await controller.discard();
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

/// One record: offset, source, event, then the extra fields underneath.
class _LineRow extends StatelessWidget {
  const _LineRow({required this.line});

  final LogLine line;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final accent = line.isError
        ? t.danger
        : line.isWarning
            ? t.accentOrange
            : line.isMarker
                ? t.accentGreen
                : t.textTertiary;

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${line.src} · ${line.evt}',
                  style: TextStyle(
                    fontFamily: DashTokens.fontMono,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: line.isError || line.isWarning
                        ? accent
                        : t.textPrimary,
                  ),
                ),
                if (line.detail.isNotEmpty)
                  Text(
                    line.detail,
                    style: TextStyle(
                      fontFamily: DashTokens.fontMono,
                      fontSize: 11,
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

class _RawBlock extends StatelessWidget {
  const _RawBlock({required this.log});

  final String log;

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
      child: SelectableText(
        log,
        style: TextStyle(
          fontFamily: DashTokens.fontMono,
          fontSize: 10,
          color: t.textSecondary,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.body, this.icon});

  final String title;
  final String body;
  final IconData? icon;

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
