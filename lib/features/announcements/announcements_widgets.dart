import 'dart:async';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/announcement.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import 'announcements_providers.dart';

String announcementsRoute([String? openId]) => openId == null
    ? '/announcements'
    : '/announcements?open=${Uri.encodeQueryComponent(openId)}';

/// The dashboard's drawer button, with a dot while anything is unread — the
/// inbox itself sits in the drawer header, so this is what says to look.
class AnnouncementsDrawerButton extends ConsumerWidget {
  const AnnouncementsDrawerButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final unread =
        ref.watch(announcementsProvider).valueOrNull?.unreadCount ?? 0;
    return Badge(
      isLabelVisible: unread > 0,
      smallSize: 8,
      backgroundColor: t.dangerInk,
      alignment: const AlignmentDirectional(0.35, -0.45),
      child: const DrawerButton(),
    );
  }
}

/// The inbox entry in the drawer header. Absent while the server says this
/// session gets no announcements — an API key, an older server, or a
/// non-admin before the admin shares them.
class AnnouncementsHeaderButton extends ConsumerWidget {
  const AnnouncementsHeaderButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final feed = ref.watch(announcementsProvider).valueOrNull;
    if (feed == null || !feed.visible) return const SizedBox.shrink();
    final unread = feed.unreadCount;
    return IconButton(
      tooltip: unread > 0
          ? l10n.announcementsUnread(unread)
          : l10n.announcementsTitle,
      onPressed: () {
        Navigator.pop(context);
        context.push(announcementsRoute());
      },
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text('$unread'),
        backgroundColor: t.dangerInk,
        textColor: t.onDanger,
        child: Icon(Icons.campaign_outlined, color: t.textPrimary),
      ),
    ).tagged('drawer.announcements');
  }
}

/// The web's strip above the page: one unread important or critical message,
/// the most severe; "Read more" opens it, "Got it" marks it read. Info-level
/// messages never get one, only the dot.
class AnnouncementBanner extends ConsumerWidget {
  const AnnouncementBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final items = ref.watch(announcementsProvider).valueOrNull?.bannerItems;
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    final first = items.first;
    final critical = first.level == AnnouncementLevel.critical;
    final (accent, ink) = critical
        ? (t.danger, t.dangerInk)
        : (t.warning, t.warningInk);
    final text = first.textFor(Localizations.localeOf(context).toLanguageTag());
    return Semantics(
      liveRegion: true,
      child: Material(
        color: accent.withValues(alpha: 0.16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            DashSpace.gutter,
            DashSpace.sm,
            DashSpace.sm,
            DashSpace.sm,
          ),
          child: Row(
            children: [
              Icon(
                critical
                    ? Icons.warning_amber_rounded
                    : Icons.campaign_outlined,
                size: 18,
                color: ink,
              ),
              const SizedBox(width: DashSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text.title,
                      style: t.titleSm.copyWith(color: t.textPrimary),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: ink,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () =>
                          context.push(announcementsRoute(first.id)),
                      child: Text(
                        items.length > 1
                            ? l10n.announcementsReadMoreCount(items.length - 1)
                            : l10n.announcementsReadMore,
                      ),
                    ).tagged('announcements.banner.open'),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => unawaited(
                  ref.read(announcementsProvider.notifier).markRead(first.id),
                ),
                child: Text(l10n.announcementsGotIt),
              ).tagged('announcements.banner.dismiss'),
            ],
          ),
        ),
      ),
    );
  }
}
