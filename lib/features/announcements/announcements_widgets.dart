import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import 'announcements_providers.dart';
import 'app_update.dart';

/// Unread entries of both sources: the server's, and the app's own update.
int watchUnreadCount(WidgetRef ref) =>
    (ref.watch(announcementsProvider).value?.unreadCount ?? 0) +
    (ref.watch(appUpdateProvider).unread ? 1 : 0);

const announcementsRoute = '/announcements';

/// The dashboard's drawer button, with a dot while anything is unread — the
/// inbox itself sits in the drawer header, so this is what says to look.
class AnnouncementsDrawerButton extends ConsumerWidget {
  const AnnouncementsDrawerButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final unread = watchUnreadCount(ref);
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
/// non-admin before the admin shares them — unless the app has an update of
/// its own to show there.
class AnnouncementsHeaderButton extends ConsumerWidget {
  const AnnouncementsHeaderButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final server = ref.watch(announcementsProvider).value?.visible ?? false;
    final unread = watchUnreadCount(ref);
    if (!server && !ref.watch(appUpdateProvider).offered) {
      return const SizedBox.shrink();
    }
    return IconButton(
      tooltip: unread > 0
          ? l10n.announcementsUnread(unread)
          : l10n.announcementsTitle,
      onPressed: () {
        Navigator.pop(context);
        context.push(announcementsRoute);
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
