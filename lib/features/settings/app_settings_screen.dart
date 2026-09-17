import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/demo/demo_backend.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../common/settings_entry_tile.dart';
import '../common/settings_rows.dart';
import '../../providers.dart';
import '../dashboard/card_collapse_providers.dart';
import 'demo_printers_provider.dart';

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
            // Demo only: on a real server the number of printing machines is
            // the server's business, and this row would be a lie.
            if (ref.watch(serverProfileProvider)?.isDemo ?? false) ...[
              const SizedBox(height: 20),
              SettingsSectionHeader(l10n.demoSettingsSection),
              SettingsCard(
                rows: [
                  SettingsSlider(
                    tag: 'app_settings.demo_printing_count',
                    label: l10n.demoPrintingCountTitle,
                    subtitle: l10n.demoPrintingCountDesc,
                    value: ref.watch(demoPrintingCountProvider),
                    min: 0,
                    max: DemoBackend.maxPrintingPrinters,
                    enabled: true,
                    onChanged: (v) =>
                        ref.read(demoPrintingCountProvider.notifier).set(v),
                  ),
                ],
              ),
            ],
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
