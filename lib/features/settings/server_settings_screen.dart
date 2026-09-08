import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../admin/admin_screen.dart';
import '../common/settings_entry_tile.dart';
import '../common/system_insets.dart';

/// One entry for everything this app can change **on the server** — the
/// configuration every user of that server shares.
///
/// The drawer used to carry these one by one, and the list was only going to
/// grow. Grouping them also draws the line that matters: what is here changes
/// the server for everybody, while Notifications changes this phone.
///
/// Nothing here is gated on [canOpenAdminProvider]. That gate answers `false`
/// for an anonymous session, which is right for accounts and API keys and wrong
/// for settings: with authentication switched off server-side the settings
/// routes are wide open, so the one session with full rights would have been
/// the one that could not find them.
class ServerSettingsScreen extends ConsumerWidget {
  const ServerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(context, title: l10n.serverSettingsTitle),
        body: ListView(
          padding: withSystemNavInset(
            context,
            const EdgeInsets.fromLTRB(12, 8, 12, 24),
          ),
          children: [
            SettingsEntryTile(
              icon: Icons.local_fire_department_outlined,
              title: l10n.queueSettingsTitle,
              subtitle: l10n.serverSettingsQueueSubtitle,
              onTap: () => context.push('/settings/queue'),
              id: 'server_settings.queue',
            ),
            SettingsEntryTile(
              icon: Icons.build_outlined,
              title: l10n.maintenanceSettingsTitle,
              subtitle: l10n.serverSettingsMaintenanceSubtitle,
              onTap: () => context.push('/settings/maintenance'),
              id: 'server_settings.maintenance',
            ),
            SettingsEntryTile(
              icon: Icons.cloud_outlined,
              title: l10n.cloudAccountMenu,
              subtitle: l10n.serverSettingsCloudSubtitle,
              onTap: () => context.push('/settings/cloud'),
              id: 'server_settings.cloud',
            ),
            if (ref.watch(canOpenAdminProvider))
              SettingsEntryTile(
                icon: Icons.admin_panel_settings_outlined,
                title: l10n.adminTitle,
                subtitle: l10n.serverSettingsAdminSubtitle,
                onTap: () => context.push('/admin'),
                id: 'server_settings.admin',
              ),
          ],
        ),
      ),
    );
  }
}
