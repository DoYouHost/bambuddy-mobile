import 'dart:async';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:app_update/app_update.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/datetime_format.dart';
import '../../core/models/announcement.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../common/dash_async.dart';
import '../common/web_link.dart';
import 'announcements_providers.dart';
import 'announcements_widgets.dart';
import 'app_update.dart';

/// The source line of a server entry: a product name, the same in every
/// language.
const announcementsServerSource = 'Bambuddy';

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
    final feed = ref.read(announcementsProvider).value;
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
    final server = ref.watch(announcementsProvider);
    final update = ref.watch(appUpdateProvider);
    // The app's own entry does not wait for the server's, nor fail with it.
    final feed = update.offered && !server.hasValue
        ? const AsyncData(AnnouncementFeed.hidden)
        : server;
    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(
          context,
          title: l10n.announcementsTitle,
          actions: [
            if (watchUnreadCount(ref) > 0)
              IconButton(
                tooltip: l10n.announcementsMarkAllRead,
                icon: const Icon(Icons.done_all),
                onPressed: () {
                  ref.read(appUpdateProvider.notifier).markRead();
                  unawaited(
                    ref.read(announcementsProvider.notifier).markAllRead(),
                  );
                },
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
                padding: screenListPadding(context),
                children: [
                  if (update.offered) _AppUpdateCard(update),
                  if (current.isEmpty && !update.offered)
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
                  if (feed.visible) ...[
                    const SizedBox(height: DashSpace.lg),
                    Text(
                      l10n.announcementsSource,
                      textAlign: TextAlign.center,
                      style: t.monoMicro.copyWith(color: t.textTertiary),
                    ),
                  ],
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
    return TappableCard(
      id: 'announcements.item',
      onTap: onToggle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _SourceLine(
                  icon: Icons.campaign_outlined,
                  name: announcementsServerSource,
                  color: t.textSecondary,
                  chips: [
                    _levelPill(t, l10n, a.level),
                    if (a.unread) _newPill(t, l10n),
                  ],
                ),
              ),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                color: t.textTertiary,
              ),
            ],
          ),
          Divider(height: DashSpace.lg, color: t.hairline),
          Text(
            text.title,
            style: t.titleMd.copyWith(
              color: a.unread ? t.textPrimary : t.textSecondary,
            ),
          ),
          if (published != null) ...[
            const SizedBox(height: DashSpace.xs),
            Text(
              DateTimeFormats.of(context).date(published),
              style: t.monoMicro.copyWith(color: t.textTertiary),
            ),
          ],
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
                  onPressed: () => openWebLink(context, link.toString()),
                  icon: const Icon(Icons.open_in_new, size: DashIcon.sm),
                  label: Text(text.linkLabel ?? l10n.announcementsReadMore),
                ).tagged('announcements.link'),
              ),
          ],
        ],
      ),
    );
  }
}

/// Where an entry comes from, with its chips at the end of the same line. When
/// both do not fit, the chips move below and stay at the end.
class _SourceLine extends StatelessWidget {
  const _SourceLine({
    required this.icon,
    required this.name,
    required this.color,
    required this.chips,
  });

  final IconData icon;
  final String name;
  final Color color;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return OverflowBar(
      alignment: MainAxisAlignment.spaceBetween,
      overflowAlignment: OverflowBarAlignment.end,
      spacing: DashSpace.sm,
      overflowSpacing: DashSpace.xs,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: DashIcon.sm, color: color),
            const SizedBox(width: DashSpace.sm),
            Flexible(
              child: Text(name, style: t.bodyBold.copyWith(color: color)),
            ),
          ],
        ),
        Wrap(spacing: DashSpace.sm, runSpacing: DashSpace.xs, children: chips),
      ],
    );
  }
}

/// The app's own entry, pinned above the server's and tinted so it is not
/// taken for one of them. Its button is always on show: there is nothing to
/// expand.
class _AppUpdateCard extends ConsumerWidget {
  const _AppUpdateCard(this.update);

  final AppUpdate update;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final updates = ref.read(appUpdateProvider.notifier);
    final (title, body, action) = switch (update.play.phase) {
      PlayUpdatePhase.ready => (
        l10n.appUpdateReady,
        null,
        TextButton(
          onPressed: updates.install,
          style: TextButton.styleFrom(foregroundColor: t.accentGreenInk),
          child: Text(l10n.appUpdateRestart),
        ).tagged('announcements.app_update_restart'),
      ),
      PlayUpdatePhase.downloading => (
        l10n.appUpdateTitle,
        l10n.appUpdateDownloading,
        null,
      ),
      _ => (
        l10n.appUpdateTitle,
        l10n.appUpdateBody,
        TextButton(
          onPressed: () => unawaited(updates.download()),
          style: TextButton.styleFrom(foregroundColor: t.accentGreenInk),
          child: Text(l10n.appUpdateButton),
        ).tagged('announcements.app_update_download'),
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DashSpace.xs),
      child: Material(
        color: Colors.transparent,
        child: logTag(
          'announcements.app_update',
          InkWell(
            borderRadius: BorderRadius.circular(DashRadius.xl),
            onTap: updates.markRead,
            child: Container(
              padding: const EdgeInsets.all(DashSpace.lg),
              decoration: t.tintBox(t.accentGreen, radius: DashRadius.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SourceLine(
                    icon: Icons.smartphone,
                    name: l10n.announcementsSourceMobile,
                    color: t.accentGreenInk,
                    chips: [if (update.unread) _newPill(t, l10n)],
                  ),
                  Divider(height: DashSpace.lg, color: t.hairline),
                  Text(title, style: t.titleMd.copyWith(color: t.textPrimary)),
                  if (body != null) ...[
                    const SizedBox(height: DashSpace.xs),
                    Text(
                      body,
                      style: t.labelSoft.copyWith(color: t.textSecondary),
                    ),
                  ],
                  if (action != null)
                    Align(alignment: Alignment.centerLeft, child: action),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _newPill(DashTokens t, AppLocalizations l10n) => DashPill(
  label: l10n.announcementsNew,
  accent: t.accentGreen,
  accentInk: t.accentGreenInk,
  dense: true,
);

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
