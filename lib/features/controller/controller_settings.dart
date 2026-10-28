import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/duration_format.dart';
import '../../core/settings/controller_prefs.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import 'scale_to_fit.dart';
import 'controller_controls.dart';
import 'controller_providers.dart';
import 'controller_saver.dart';

/// The controller's own settings, stored on this device
/// ([docs/single-printer-controller.md] §4).
class ControllerSettings extends ConsumerStatefulWidget {
  const ControllerSettings({super.key});

  @override
  ConsumerState<ControllerSettings> createState() => _ControllerSettingsState();
}

class _ControllerSettingsState extends ConsumerState<ControllerSettings> {
  /// Which card shows at a large text size, where there is room for one.
  int _card = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final prefs = ref.watch(controllerPrefsProvider);
    final notifier = ref.read(controllerPrefsProvider.notifier);
    final saver = ControllerCard.single(
      title: l10n.controllerSaverTitle,
      trailing: logTag(
        'controller.saver_preview',
        FilledButton.icon(
          style: controllerButtonStyle(
            DashTokens.of(context),
            minimumSize: const Size(0, ControllerSection.headerHeight),
          ),
          icon: Icon(
            prefs.keepAwake ? Icons.visibility_outlined : Icons.lock_outline,
          ),
          label: Text(l10n.controllerSaverPreview),
          // Without the screen held on, the phone turns it off first.
          onPressed: prefs.keepAwake
              ? () => context
                    .findAncestorStateOfType<ControllerSaverHostState>()
                    ?.show()
              : null,
        ),
      ),
      child: _SaverSettings(prefs: prefs),
    );
    final keepAwakeRow = SettingsSwitchRow(
      tag: 'controller.keep_awake',
      title: l10n.controllerKeepAwake,
      // Off, the line says what it costs: the saver's settings beside it
      // are locked, and this is why.
      subtitle: prefs.keepAwake
          ? l10n.controllerKeepAwakeHint
          : l10n.controllerSaverNeedsAwake,
      value: prefs.keepAwake,
      onChanged: (v) => notifier.update((p) => p.copyWith(keepAwake: v)),
    );
    final liveCameraRow = SettingsSwitchRow(
      tag: 'controller.live_camera',
      title: l10n.wallLiveCameraTitle,
      subtitle: l10n.controllerLiveCameraHint,
      value: prefs.liveCamera,
      onChanged: (v) => notifier.update((p) => p.copyWith(liveCamera: v)),
    );
    final display = ControllerCard.single(
      title: l10n.controllerDisplayTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [keepAwakeRow, liveCameraRow],
      ),
    );
    // A large text size leaves room for one card at a time: a row of two picks
    // it, and the card has no title of its own, since the row says it.
    if (controllerLargeText(context)) {
      final t = DashTokens.of(context);
      final preview = logTag(
        'controller.saver_preview',
        FilledButton.icon(
          style: controllerButtonStyle(
            t,
            minimumSize: const Size(double.infinity, controllerButtonHeight),
          ),
          icon: Icon(
            prefs.keepAwake ? Icons.visibility_outlined : Icons.lock_outline,
          ),
          label: Text(l10n.controllerSaverPreview),
          onPressed: prefs.keepAwake
              ? () => context
                    .findAncestorStateOfType<ControllerSaverHostState>()
                    ?.show()
              : null,
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ControllerChoices(
            id: 'controller.settings_card',
            labels: [l10n.controllerSaverTitle, l10n.controllerDisplayTitle],
            selected: _card,
            onChanged: (i) => setState(() => _card = i),
          ),
          const SizedBox(height: DashSpace.sm),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(DashSpace.md),
              decoration: t.cardBox,
              child: _card == 0
                  ? _SaverSettings(prefs: prefs, large: true, preview: preview)
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: keepAwakeRow),
                        const SizedBox(width: DashSpace.md),
                        Expanded(child: liveCameraRow),
                      ],
                    ),
            ),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 3, child: saver),
        const SizedBox(width: DashSpace.md),
        Expanded(flex: 2, child: display),
      ],
    );
  }
}

class _SaverSettings extends ConsumerWidget {
  const _SaverSettings({required this.prefs, this.large = false, this.preview});

  final ControllerPrefs prefs;

  /// At a large text size the settings take two columns of the card, and the
  /// preview button is the second one's last row.
  final bool large;
  final Widget? preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(controllerPrefsProvider.notifier);
    const options = ControllerPrefs.saverAfterOptions;
    final awake = prefs.keepAwake;
    final after = ControllerChoices(
      id: 'controller.saver_after',
      selectLabel: l10n.controllerSaverAfter,
      labels: [
        for (final m in options)
          m == ControllerPrefs.saverNever
              ? l10n.controllerSaverNever
              : formatMinutes(l10n, m),
      ],
      selected: options.indexOf(prefs.saverAfterMinutes),
      enabled: awake,
      onChanged: (i) => _setAfter(context, ref, options[i]),
    );
    final brightness = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.controllerSaverBrightness,
                style: t.bodyStrong.copyWith(color: t.textSecondary),
              ),
            ),
            Text('${prefs.saverBrightness}%', style: t.monoTitle),
          ],
        ),
        Text(l10n.controllerSaverBrightnessHint, style: t.labelSoft),
        logTag(
          'controller.saver_brightness',
          Slider(
            value: prefs.saverBrightness.toDouble(),
            min: ControllerPrefs.minSaverBrightness.toDouble(),
            max: ControllerPrefs.maxSaverBrightness.toDouble(),
            divisions:
                (ControllerPrefs.maxSaverBrightness -
                    ControllerPrefs.minSaverBrightness) ~/
                ControllerPrefs.saverBrightnessStep,
            onChanged: awake
                ? (v) => notifier.update(
                    (p) => p.copyWith(saverBrightness: v.round()),
                  )
                : null,
          ),
        ),
      ],
    );
    final wake = SettingsSwitchRow(
      tag: 'controller.wake_on_warnings',
      title: l10n.controllerWakeOnWarnings,
      subtitle: l10n.controllerWakeOnWarningsHint,
      value: prefs.wakeOnWarnings,
      onChanged: awake
          ? (v) => notifier.update((p) => p.copyWith(wakeOnWarnings: v))
          : null,
    );
    if (large) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                after,
                const SizedBox(height: DashSpace.md),
                brightness,
              ],
            ),
          ),
          const SizedBox(width: DashSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                wake,
                if (preview != null) ...[
                  const SizedBox(height: DashSpace.sm),
                  preview!,
                ],
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.controllerSaverAfter,
          style: t.bodyStrong.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: DashSpace.xs),
        after,
        const SizedBox(height: DashSpace.md),
        brightness,
        wake,
      ],
    );
  }

  /// Never is stored only once the burn-in risk is accepted; any time is
  /// stored at once.
  Future<void> _setAfter(
    BuildContext context,
    WidgetRef ref,
    int minutes,
  ) async {
    // The risk was accepted when Never was chosen; tapping it again asks nothing.
    if (minutes == prefs.saverAfterMinutes) return;
    final notifier = ref.read(controllerPrefsProvider.notifier);
    if (minutes == ControllerPrefs.saverNever) {
      final l10n = AppLocalizations.of(context);
      final accepted = await confirmDialog(
        context,
        title: l10n.controllerSaverNeverTitle,
        message: l10n.controllerSaverNeverBody,
        confirmLabel: l10n.controllerSaverNeverConfirm,
        destructive: true,
        id: 'controller.saver_never',
      );
      if (!accepted) return;
    }
    await notifier.update((p) => p.copyWith(saverAfterMinutes: minutes));
  }
}
