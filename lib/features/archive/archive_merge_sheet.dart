import 'dart:async';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/app_context.dart';
import '../../core/format/datetime_format.dart';
import '../../core/models/archive_merge.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import '../common/dash_async.dart';
import 'archive_providers.dart';

/// Whether this session is offered "Merge duplicates" at all: a server with the
/// routes and both archive rights.
bool archiveMergeOffered(WidgetRef ref) =>
    ref.watch(archiveMergeAllowedProvider) &&
    ref.watch(archiveMergeSupportedProvider).orFalse;

String archiveMergeSkipLabel(AppLocalizations l10n, String? reason) =>
    switch (ArchiveMergeSkip.fromWire(reason)) {
      ArchiveMergeSkip.busy => l10n.archiveMergeSkipBusy,
      ArchiveMergeSkip.conflictingFiles => l10n.archiveMergeSkipConflicting,
      ArchiveMergeSkip.notAGroup => l10n.archiveMergeSkipNotAGroup,
      ArchiveMergeSkip.failed || null => l10n.archiveMergeSkipFailed,
    };

/// "N groups of duplicate archives" over the archive list, with the way into
/// the merge. Dismissed at a count, it comes back once there are more groups,
/// as the web's banner does: merging some leaves the rest, and some never
/// merge.
class ArchiveMergeBanner extends ConsumerWidget {
  const ArchiveMergeBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(archiveMergeCountProvider).value ?? 0;
    final dismissedAt = ref.watch(archiveMergeDismissedAtProvider);
    if (groups == 0 || (dismissedAt != null && groups <= dismissedAt)) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DashSpace.gutter,
        DashSpace.sm,
        DashSpace.gutter,
        DashSpace.xs,
      ),
      child: logTag(
        'archive.merge_banner',
        Container(
          padding: const EdgeInsets.fromLTRB(
            DashSpace.md,
            DashSpace.xs,
            DashSpace.xs,
            DashSpace.xs,
          ),
          decoration: BoxDecoration(
            color: t.accentBlue.withValues(alpha: DashAlpha.faint),
            borderRadius: BorderRadius.circular(DashRadius.lg),
            border: Border.all(
              color: t.accentBlue.withValues(alpha: DashAlpha.soft),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.merge_type, size: DashIcon.md, color: t.accentBlueInk),
              const SizedBox(width: DashSpace.sm),
              Expanded(
                child: Text(l10n.archiveMergeBanner(groups), style: t.bodySoft),
              ),
              TextButton(
                onPressed: () => showArchiveMergeSheet(context),
                style: TextButton.styleFrom(foregroundColor: t.accentBlueInk),
                child: Text(l10n.archiveMergeButton),
              ).tagged('archive.merge_banner.open'),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: l10n.archiveMergeDismiss,
                onPressed: () => ref
                    .read(archiveMergeDismissedAtProvider.notifier)
                    .dismiss(groups),
              ).tagged('archive.merge_banner.dismiss'),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showArchiveMergeSheet(BuildContext context) =>
    dashSheet<void>(context, builder: (_) => const ArchiveMergeSheet());

/// `MergeDuplicatesModal` of the web: what a merge does, the groups the server
/// found (every mergeable one ticked, the ones it leaves out with why), one
/// confirmation, and a report of what the merge itself left out.
class ArchiveMergeSheet extends ConsumerStatefulWidget {
  const ArchiveMergeSheet({super.key});

  @override
  ConsumerState<ArchiveMergeSheet> createState() => _ArchiveMergeSheetState();
}

class _ArchiveMergeSheetState extends ConsumerState<ArchiveMergeSheet> {
  final _unticked = <int>{};
  bool _merging = false;

  /// The confirmation is open: a second tap in the same frame would stack
  /// another one and send the merge twice.
  bool _asking = false;

  /// What the merge left out, shown in place of the groups once it ran.
  List<({int survivorId, String? reason})>? _leftOut;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    return logTag(
      'sheet.archive_merge',
      SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          DashSpace.gutter,
          0,
          DashSpace.gutter,
          DashSpace.lg,
        ),
        child: dashAsync(
          context,
          ref.watch(archiveMergePreviewProvider),
          onRetry: () => ref.invalidate(archiveMergePreviewProvider),
          data: (groups) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DashSpace.md,
            children: [
              Text(l10n.archiveMergeTitle, style: t.titleSm),
              for (final effect in [
                l10n.archiveMergeEffectKeep,
                l10n.archiveMergeEffectLinks,
                l10n.archiveMergeEffectMoney,
              ])
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•', style: t.labelSoft),
                    const SizedBox(width: DashSpace.sm),
                    Expanded(child: Text(effect, style: t.labelSoft)),
                  ],
                ),
              ..._body(l10n, t, groups),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(
    AppLocalizations l10n,
    DashTokens t,
    List<ArchiveMergeGroup> groups,
  ) {
    final close = TextButton(
      onPressed: () => Navigator.pop(context),
      child: Text(MaterialLocalizations.of(context).closeButtonLabel),
    ).tagged('archive.merge.close');
    final leftOut = _leftOut;
    if (leftOut != null) {
      final names = {for (final g in groups) g.survivor.id: g.survivor.name};
      return [
        Text(l10n.archiveMergeLeftOut, style: t.bodyStrong),
        for (final skip in leftOut)
          _Reasoned(
            title: names[skip.survivorId] ?? '#${skip.survivorId}',
            reason: archiveMergeSkipLabel(l10n, skip.reason),
          ),
        close,
      ];
    }
    if (groups.isEmpty) {
      return [Text(l10n.archiveMergeNone, style: t.body), close];
    }
    final mergeable = groups.where((g) => g.mergeable).toList();
    final waiting = groups.where((g) => !g.mergeable).toList();
    final selected = [
      for (final g in mergeable)
        if (!_unticked.contains(g.survivor.id)) g.survivor.id,
    ];
    return [
      for (final group in mergeable)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: !_unticked.contains(group.survivor.id),
          onChanged: _merging
              ? null
              : (on) => setState(() {
                  if (on == true) {
                    _unticked.remove(group.survivor.id);
                  } else {
                    _unticked.add(group.survivor.id);
                  }
                }),
          title: Text(group.survivor.name, style: t.bodyStrong),
          subtitle: _Members(group: group),
        ).tagged('archive.merge.group'),
      if (waiting.isNotEmpty) ...[
        Text(l10n.archiveMergeWaiting, style: t.bodyStrong),
        for (final group in waiting)
          _Reasoned(
            title: group.survivor.name,
            reason: archiveMergeSkipLabel(l10n, group.skipped),
            members: _Members(group: group),
          ),
      ],
      // Close stands in for the merge whenever there is nothing ticked, so the
      // sheet always has a way out besides the drag handle.
      if (selected.isNotEmpty)
        FilledButton.icon(
          icon: _merging
              ? const SizedBox.square(
                  dimension: DashIcon.md,
                  child: CircularProgressIndicator(
                    strokeWidth: DashStroke.regular,
                  ),
                )
              : const Icon(Icons.merge_type),
          label: Text(l10n.archiveMergeAction(selected.length)),
          onPressed: _merging ? null : () => _merge(selected),
        ).tagged('archive.merge.confirm')
      else
        close,
    ];
  }

  Future<void> _merge(List<int> survivors) async {
    if (_merging || _asking) return;
    _asking = true;
    final l10n = AppLocalizations.of(context);
    final bool ok;
    try {
      ok = await confirmDialog(
        context,
        id: 'archive.merge.confirm_dialog',
        title: l10n.archiveMergeAction(survivors.length),
        message: l10n.archiveMergeConfirmBody,
        confirmLabel: l10n.archiveMergeButton,
      );
    } finally {
      _asking = false;
    }
    if (!ok || !mounted) return;
    setState(() => _merging = true);
    final (:providers, :messenger) = detachFrom(context);
    final navigator = Navigator.of(context);
    try {
      final result = await providers
          .read(archiveRepositoryProvider)
          .merge(survivors);
      // Prints moved between archives: the list and its count are stale.
      providers.invalidate(archiveMergeCountProvider);
      // Not awaited: the merge is done, and the list reloads behind the sheet.
      if (providers.exists(archiveProvider)) {
        unawaited(providers.read(archiveProvider.notifier).refresh());
      }
      if (result.skipped.isEmpty) {
        messenger.snack(l10n.archiveMergeDone(result.merged.length));
        if (mounted) navigator.pop();
        return;
      }
      messenger.snack(
        l10n.archiveMergeDoneSome(result.merged.length, result.skipped.length),
      );
      if (mounted) {
        setState(() {
          _merging = false;
          _leftOut = result.skipped;
        });
      }
    } on AppApiException catch (e) {
      showApiFailure(
        mounted ? messenger : null,
        e,
        l10n,
        action: 'archive.merge.confirm',
      );
      if (mounted) setState(() => _merging = false);
    } catch (_) {
      if (mounted) setState(() => _merging = false);
      rethrow;
    }
  }
}

/// The archives of a group: the one that stays, then those going into it.
class _Members extends StatelessWidget {
  const _Members({required this.group});

  final ArchiveMergeGroup group;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final dates = DateTimeFormats.of(context);
    String line(ArchiveMergeMember m) => l10n.archiveMergeMember(
      m.name,
      m.createdAt == null ? '—' : dates.date(m.createdAt!),
      m.runCount,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${l10n.archiveMergeStays}: ${line(group.survivor)}',
          style: t.labelSoft,
        ),
        for (final m in group.merged) Text('+ ${line(m)}', style: t.labelSoft),
      ],
    );
  }
}

class _Reasoned extends StatelessWidget {
  const _Reasoned({required this.title, required this.reason, this.members});

  final String title;
  final String reason;
  final Widget? members;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DashSpace.xs,
      children: [
        Text(title, style: t.body),
        ?members,
        Text(reason, style: t.label.copyWith(color: t.accentOrangeInk)),
      ],
    );
  }
}
