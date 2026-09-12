import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../common/settings_entry_tile.dart';
import '../common/settings_rows.dart';
import '../common/system_insets.dart';
import '../dashboard/card_collapse_providers.dart';

/// What this app does on this phone, as opposed to [ServerSettingsScreen],
/// whose settings every user of the server shares.
class AppSettingsScreen extends ConsumerWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(context, title: l10n.appSettingsTitle),
        body: ListView(
          padding: withSystemNavInset(
            context,
            const EdgeInsets.fromLTRB(12, 8, 12, 24),
          ),
          children: [
            SettingsSectionHeader(l10n.navDashboard),
            SettingsCard(
              rows: [
                SettingsSwitchRow(
                  tag: 'app_settings.collapse_printer_cards',
                  title: l10n.collapsePrinterCardsTitle,
                  subtitle: l10n.collapsePrinterCardsDesc,
                  value: ref.watch(printerCardsCollapsedByDefaultProvider),
                  onChanged: ref
                      .read(printerCardsCollapsedByDefaultProvider.notifier)
                      .set,
                ),
              ],
            ),
            const SizedBox(height: 20),
            SettingsSectionHeader(l10n.notifSettingsTitle),
            SettingsEntryTile(
              icon: Icons.tune_rounded,
              title: l10n.notifEventsMenu,
              subtitle: l10n.appSettingsNotificationsSubtitle,
              onTap: () => context.push('/settings/notifications'),
              id: 'app_settings.notifications',
            ),
          ],
        ),
      ),
    );
  }
}
