import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/demo/demo_backend.dart';
import '../../core/settings/appearance_prefs.dart';
import '../../core/theme/app_brand.dart';
import '../../core/theme/appearance_providers.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../dashboard/card_collapse_providers.dart';
import '../tour/tour_beacon.dart';
import '../wall/wall_providers.dart';
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
          padding: screenListPadding(context),
          children: [
            SettingsSectionHeader(l10n.appearanceTitle),
            const _AppearanceCard(),
            const SizedBox(height: DashSpace.xl),
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
            const SizedBox(height: DashSpace.xl),
            SettingsSectionHeader(l10n.wallModeTitle),
            SettingsCard(
              rows: [
                SettingsSwitchRow(
                  tag: 'app_settings.wall_keep_awake',
                  title: l10n.wallKeepAwakeTitle,
                  subtitle: l10n.wallKeepAwakeDesc,
                  value: ref.watch(wallKeepAwakeProvider),
                  onChanged: ref.read(wallKeepAwakeProvider.notifier).set,
                ),
              ],
            ),
            // Demo only: on a real server the number of printing machines is
            // the server's business, and this row would be a lie.
            if (ref.watch(serverProfileProvider)?.isDemo ?? false) ...[
              const SizedBox(height: DashSpace.xl),
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
                        ref.read(demoPrintingCountProvider.notifier).preview(v),
                    onChangeEnd: (v) =>
                        ref.read(demoPrintingCountProvider.notifier).set(v),
                  ),
                ],
              ),
            ],
            const SizedBox(height: DashSpace.xl),
            SettingsEntryTile(
              icon: Icons.label_outline,
              title: l10n.labelPrinterTitle,
              subtitle: l10n.labelPrinterEntrySubtitle,
              onTap: () => context.push('/settings/label-printer'),
              id: 'app_settings.label_printer',
            ),
            const SizedBox(height: DashSpace.xl),
            SettingsSectionHeader(l10n.notifSettingsTitle),
            SettingsEntryTile(
              icon: Icons.tune_rounded,
              title: l10n.notifEventsMenu,
              subtitle: l10n.appSettingsNotificationsSubtitle,
              onTap: () => context.push('/settings/notifications'),
              id: 'app_settings.notifications',
            ),
            // The tour's own copy of this screen would start a tour in a tour.
            if (ref.watch(tourBeaconProvider) == null) ...[
              const SizedBox(height: DashSpace.xl),
              SettingsEntryTile(
                icon: Icons.lightbulb_outline_rounded,
                title: l10n.tipsTitle,
                subtitle: l10n.tipsSubtitle,
                onTap: () => context.push('/settings/tips'),
                id: 'app_settings.tips',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Accent and light/dark, the two choices of how the app looks on this phone.
class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final prefs = ref.watch(appearanceProvider);
    final notifier = ref.read(appearanceProvider.notifier);
    final system = ref.watch(systemSchemesProvider);
    // A stored "System" stays listed on a phone without a palette, or the field
    // would show no choice at all.
    final accents = [
      for (final a in AccentSource.values)
        if (a != AccentSource.system ||
            system != null ||
            prefs.accent == AccentSource.system)
          a,
    ];

    return SettingsCard(
      rows: [
        Padding(
          padding: const EdgeInsets.all(DashSpace.sm),
          child: dashCombo<AccentSource>(
            context,
            id: 'app_settings.accent',
            label: Text(l10n.appearanceAccent),
            initialSelection: prefs.accent,
            onSelected: (a) {
              if (a != null) notifier.set(prefs.copyWith(accent: a));
            },
            entries: [
              for (final a in accents)
                DropdownMenuEntry(
                  value: a,
                  label: _accentLabel(l10n, a),
                  leadingIcon: _AccentDot(
                    resolveBrand(a, system).of(t.brightness).fill,
                  ),
                  labelWidget: logTag(
                    _accentIds[a]!,
                    Text(_accentLabel(l10n, a)),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(DashSpace.sm),
          child: dashCombo<ThemeMode>(
            context,
            id: 'app_settings.theme_mode',
            label: Text(l10n.appearanceMode),
            initialSelection: prefs.mode,
            onSelected: (m) {
              if (m != null) notifier.set(prefs.copyWith(mode: m));
            },
            entries: [
              for (final m in ThemeMode.values)
                DropdownMenuEntry(
                  value: m,
                  label: _modeLabel(l10n, m),
                  labelWidget: logTag(_modeIds[m]!, Text(_modeLabel(l10n, m))),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AccentDot extends StatelessWidget {
  const _AccentDot(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 16,
    height: 16,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

String _accentLabel(AppLocalizations l10n, AccentSource a) => switch (a) {
  AccentSource.bambuddy => l10n.appearanceAccentBambuddy,
  AccentSource.system => l10n.appearanceAccentSystem,
  AccentSource.blue => l10n.appearanceAccentBlue,
  AccentSource.purple => l10n.appearanceAccentPurple,
  AccentSource.orange => l10n.appearanceAccentOrange,
  AccentSource.pink => l10n.appearanceAccentPink,
  AccentSource.graphite => l10n.appearanceAccentGraphite,
};

String _modeLabel(AppLocalizations l10n, ThemeMode m) => switch (m) {
  ThemeMode.system => l10n.appearanceModeSystem,
  ThemeMode.light => l10n.appearanceModeLight,
  ThemeMode.dark => l10n.appearanceModeDark,
};

// Literal ids: an interpolated one would slip past the redactor's shape check.
const _accentIds = {
  AccentSource.bambuddy: 'app_settings.accent.bambuddy',
  AccentSource.system: 'app_settings.accent.system',
  AccentSource.blue: 'app_settings.accent.blue',
  AccentSource.purple: 'app_settings.accent.purple',
  AccentSource.orange: 'app_settings.accent.orange',
  AccentSource.pink: 'app_settings.accent.pink',
  AccentSource.graphite: 'app_settings.accent.graphite',
};

const _modeIds = {
  ThemeMode.system: 'app_settings.theme_mode.system',
  ThemeMode.light: 'app_settings.theme_mode.light',
  ThemeMode.dark: 'app_settings.theme_mode.dark',
};
