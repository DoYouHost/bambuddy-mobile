import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/settings/appearance_prefs.dart';
import '../../core/theme/app_brand.dart';
import '../../core/theme/appearance_providers.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import 'app_settings_screen.dart' show AccentDot, accentLabel;

/// The paired watch's colours, set on the phone because a watch screen is a
/// poor place for settings. Two switches that exclude each other; with both
/// off the watch wears the preset chosen below them.
class WatchSettings extends ConsumerWidget {
  const WatchSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final watch = ref.watch(watchAppearanceProvider);
    final notifier = ref.read(watchAppearanceProvider.notifier);
    // Turning one source on turns the other off; turning it off leaves the
    // preset, so the two never end up both on.
    void choose(WatchThemeSource source, bool on) => notifier.set(
      ref
          .read(watchAppearanceProvider)
          .copyWith(source: on ? source : WatchThemeSource.preset),
    );

    return SettingsCard(
      rows: [
        SettingsSwitchRow(
          tag: 'watch_settings.from_face',
          title: l10n.watchThemeFromFace,
          subtitle: l10n.watchThemeFromFaceDesc,
          value: watch.source == WatchThemeSource.face,
          onChanged: (on) => choose(WatchThemeSource.face, on),
        ),
        SettingsSwitchRow(
          tag: 'watch_settings.from_phone',
          title: l10n.watchThemeFromPhone,
          subtitle: l10n.watchThemeFromPhoneDesc,
          value: watch.source == WatchThemeSource.phone,
          onChanged: (on) => choose(WatchThemeSource.phone, on),
        ),
        if (watch.source == WatchThemeSource.preset)
          Padding(
            padding: const EdgeInsets.all(DashSpace.sm),
            child: dashCombo<AccentSource>(
              context,
              id: 'watch_settings.accent',
              label: Text(l10n.appearanceAccent),
              initialSelection: watch.preset,
              onSelected: (a) {
                if (a == null) return;
                notifier.set(
                  ref.read(watchAppearanceProvider).copyWith(preset: a),
                );
              },
              entries: [
                for (final a in watchPresets)
                  DropdownMenuEntry(
                    value: a,
                    label: accentLabel(l10n, a),
                    leadingIcon: AccentDot(
                      resolveBrand(a, null).of(t.brightness).fill,
                    ),
                    labelWidget: logTag(
                      _presetIds[a]!,
                      Text(accentLabel(l10n, a)),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The phone's accents without "System": the face switch is the watch's own
/// system colour, and the phone's palette is the other switch.
final watchPresets = [
  for (final a in AccentSource.values)
    if (a != AccentSource.system) a,
];

const _presetIds = {
  AccentSource.bambuddy: 'watch_settings.accent.bambuddy',
  AccentSource.blue: 'watch_settings.accent.blue',
  AccentSource.purple: 'watch_settings.accent.purple',
  AccentSource.orange: 'watch_settings.accent.orange',
  AccentSource.pink: 'watch_settings.accent.pink',
  AccentSource.graphite: 'watch_settings.accent.graphite',
};
