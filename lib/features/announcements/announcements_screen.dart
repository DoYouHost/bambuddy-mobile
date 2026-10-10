import 'dart:async';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/datetime_format.dart';
import '../../core/models/announcement.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../common/dash_async.dart';
import '../common/web_link.dart';
import 'announcements_providers.dart';

/// The web's announcements panel as a screen: newest first, an unread one
/// marked until it is opened — opening is what marks it read — and expired
/// ones under a collapsed "Earlier".
class AnnouncementsScreen extends ConsumerStatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  ConsumerState<AnnouncementsScreen> createState() =>
      _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends ConsumerState<AnnouncementsScreen> {
  final _expanded = <String>{};
  bool _earlierOpen = false;

  void _markRead(String id) {
    final feed = ref.read(announcementsProvider).valueOrNull;
    final hit = feed?.items.where((a) => a.id == id).firstOrNull;
    if (hit != null && hit.unread) {
      unawaited(ref.read(announcementsProvider.notifier).markRead(id));
    }
  }

  void _toggle(String id) {
    setState(() {
      if (!_expanded.remove(id)) _expanded.add(id);
    });
    if (_expanded.contains(id)) _markRead(id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final feed = ref.watch(announcementsProvider);
    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(
          context,
          title: l10n.announcementsTitle,
          actions: [
            if ((feed.valueOrNull?.unreadCount ?? 0) > 0)
              IconButton(
                tooltip: l10n.announcementsMarkAllRead,
                icon: const Icon(Icons.done_all),
                onPressed: () => unawaited(
                  ref.read(announcementsProvider.notifier).markAllRead(),
                ),
              ).tagged('announcements.mark_all_read'),
          ],
        ),
        body: dashAsync(
          context,
          feed,
          onRetry: () => ref.read(announcementsProvider.notifier).refresh(),
          data: (feed) {
            final current = feed.items.where((a) => !a.archived).toList();
            final earlier = feed.items.where((a) => a.archived).toList();
            return RefreshIndicator(
              onRefresh: () =>
                  ref.read(announcementsProvider.notifier).refresh(),
              child: ListView(
                padding: withSystemNavInset(
                  context,
                  const EdgeInsets.fromLTRB(
                    DashSpace.gutter,
                    DashSpace.sm,
                    DashSpace.gutter,
                    DashSpace.xl,
                  ),
                ),
                children: [
                  if (current.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: DashSpace.xl,
                      ),
                      child: Text(
                        l10n.announcementsEmpty,
                        textAlign: TextAlign.center,
                        style: t.labelSoft.copyWith(color: t.textSecondary),
                      ),
                    ),
                  for (final a in current) _item(a),
                  if (earlier.isNotEmpty) ...[
                    logTag(
                      'announcements.earlier',
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          l10n.announcementsEarlier(earlier.length),
                          style: t.titleSm.copyWith(color: t.textSecondary),
                        ),
                        trailing: Icon(
                          _earlierOpen ? Icons.expand_less : Icons.expand_more,
                          color: t.textTertiary,
                        ),
                        onTap: () =>
                            setState(() => _earlierOpen = !_earlierOpen),
                      ),
                    ),
                    if (_earlierOpen)
                      for (final a in earlier) _item(a),
                  ],
                  const SizedBox(height: DashSpace.lg),
                  Text(
                    l10n.announcementsSource,
                    textAlign: TextAlign.center,
                    style: t.monoMicro.copyWith(color: t.textTertiary),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _item(Announcement a) => AnnouncementTile(
    announcement: a,
    expanded: _expanded.contains(a.id),
    onToggle: () => _toggle(a.id),
  );
}

class AnnouncementTile extends StatelessWidget {
  const AnnouncementTile({
    super.key,
    required this.announcement,
    required this.expanded,
    required this.onToggle,
  });

  final Announcement announcement;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final a = announcement;
    final text = a.textFor(Localizations.localeOf(context).toLanguageTag());
    final link = a.safeLink;
    final published = a.publishedAt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DashSpace.xs),
      child: Material(
        color: Colors.transparent,
        child: logTag(
          'announcements.item',
          InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onToggle,
            child: Container(
              padding: const EdgeInsets.all(DashSpace.lg),
              decoration: t.cardBox,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: DashSpace.sm,
                          runSpacing: DashSpace.xs,
                          children: [
                            _levelPill(t, l10n, a.level),
                            if (a.unread)
                              DashPill(
                                label: l10n.announcementsNew,
                                accent: t.accentGreen,
                                accentInk: t.accentGreenInk,
                                dense: true,
                              ),
                          ],
                        ),
                      ),
                      if (published != null)
                        Text(
                          DateTimeFormats.of(context).date(published),
                          style: t.monoMicro.copyWith(color: t.textTertiary),
                        ),
                      Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        color: t.textTertiary,
                      ),
                    ],
                  ),
                  const SizedBox(height: DashSpace.sm),
                  Text(
                    text.title,
                    style: t.titleMd.copyWith(
                      color: a.unread ? t.textPrimary : t.textSecondary,
                    ),
                  ),
                  if (expanded) ...[
                    const SizedBox(height: DashSpace.sm),
                    Text(
                      text.body,
                      style: t.labelSoft.copyWith(color: t.textSecondary),
                    ),
                    if (link != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () =>
                              openWebLink(context, link.toString()),
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: Text(
                            text.linkLabel ?? l10n.announcementsReadMore,
                          ),
                        ).tagged('announcements.link'),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _levelPill(DashTokens t, AppLocalizations l10n, AnnouncementLevel l) =>
    switch (l) {
      AnnouncementLevel.critical => DashPill(
        label: l10n.announcementLevelCritical,
        accent: t.danger,
        accentInk: t.dangerInk,
        dense: true,
      ),
      AnnouncementLevel.important => DashPill(
        label: l10n.announcementLevelImportant,
        accent: t.warning,
        accentInk: t.warningInk,
        dense: true,
      ),
      AnnouncementLevel.info => DashPill(
        label: l10n.announcementLevelInfo,
        accent: t.accentBlue,
        dense: true,
      ),
    };
