import 'dart:async';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../common/settings_rows.dart';
import 'wall_providers.dart';

const _landscape = [
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
];

/// Always-on farm view for a phone or tablet on a stand (docs/tv-flavor.md
/// §13): landscape, no system bars, and the screen held on while the
/// "keep screen awake" setting says so.
///
/// Pushed over the dashboard, never swapped in for it: the dashboard owns the
/// foreground service and the token refreshers, which must keep running under
/// the wall.
class WallScreen extends ConsumerStatefulWidget {
  const WallScreen({super.key});

  /// Below this width the side panel starts as a rail (D16). Provisional:
  /// set from the spike screenshots — phones in landscape stay under it, a
  /// 7-inch tablet reaches it.
  static const panelExpandedFromWidth = 960.0;

  static const panelWidth = 290.0;
  static const railWidth = 64.0;

  @override
  ConsumerState<WallScreen> createState() => _WallScreenState();
}

class _WallScreenState extends ConsumerState<WallScreen> {
  // Read once here: `dispose` must still reach it, and `ref` is gone by then.
  late final ScreenAwake _awake;
  bool _settings = false;

  @override
  void initState() {
    super.initState();
    _awake = ref.read(screenAwakeProvider);
    unawaited(SystemChrome.setPreferredOrientations(_landscape));
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    unawaited(_awake.set(ref.read(wallKeepAwakeProvider)));
  }

  @override
  void dispose() {
    // Every way out lands here — Back, the exit button, and `/setup` replacing
    // the whole stack when the session expires — so the rest of the app gets
    // its free rotation, its bars and its screen timeout back on each of them.
    // The app sets no orientation of its own, so "restore" is the empty list.
    unawaited(SystemChrome.setPreferredOrientations(const []));
    // Not `edgeToEdge`: the engine ignores that below API 29 and the bars would
    // stay hidden, and on 29–34 it would switch the app to a mode it never
    // runs in. Both overlays in manual mode are the flags the activity starts
    // with (PlatformPlugin.setSystemChromeEnabledSystemUIOverlays).
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      ),
    );
    unawaited(_awake.set(false));
    super.dispose();
  }

  void _setExpanded(bool expanded) {
    setState(() => _settings = false);
    unawaited(ref.read(wallPanelExpandedProvider.notifier).set(expanded));
  }

  /// From the rail this opens the panel straight on its settings (D19),
  /// without saving it as expanded: closing them brings the rail back.
  void _toggleSettings() => setState(() => _settings = !_settings);

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(wallKeepAwakeProvider, (_, on) => _awake.set(on));
    final choice = ref.watch(wallPanelExpandedProvider);

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, box) {
                final expanded =
                    _settings ||
                    (choice ??
                        box.maxWidth >= WallScreen.panelExpandedFromWidth);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Expanded(child: _WallGrid()),
                    const SizedBox(width: 12),
                    if (expanded)
                      _WallPanel(
                        settings: _settings,
                        onSettings: _toggleSettings,
                        onCollapse: () => _setExpanded(false),
                      )
                    else
                      _WallRail(
                        onSettings: _toggleSettings,
                        onExpand: () => _setExpanded(true),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Where the printer tiles go.
class _WallGrid extends StatelessWidget {
  const _WallGrid();

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Center(
      child: Icon(Icons.view_quilt_outlined, size: 48, color: t.textTertiary),
    );
  }
}

/// The two buttons that end both the panel header and the rail, in the same
/// order (D20): settings, then expand/collapse.
List<Widget> _panelButtons(
  BuildContext context, {
  required bool settingsOpen,
  required VoidCallback onSettings,
  required bool expanded,
  required VoidCallback onToggle,
}) {
  final l10n = AppLocalizations.of(context);
  final t = DashTokens.of(context);
  return [
    logTag(
      'wall.settings',
      IconButton(
        tooltip: l10n.wallPanelSettings,
        isSelected: settingsOpen,
        color: t.textSecondary,
        selectedIcon: Icon(Icons.tune_rounded, color: t.accentGreenInk),
        icon: const Icon(Icons.tune_rounded),
        onPressed: onSettings,
      ),
    ),
    logTag(
      expanded ? 'wall.panel_collapse' : 'wall.panel_expand',
      IconButton(
        tooltip: expanded ? l10n.wallPanelCollapse : l10n.wallPanelExpand,
        color: t.textSecondary,
        icon: Icon(
          expanded ? Icons.last_page_rounded : Icons.first_page_rounded,
        ),
        onPressed: onToggle,
      ),
    ),
  ];
}

class _WallPanel extends StatelessWidget {
  const _WallPanel({
    required this.settings,
    required this.onSettings,
    required this.onCollapse,
  });

  final bool settings;
  final VoidCallback onSettings;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    return Container(
      width: WallScreen.panelWidth,
      decoration: t.cardBox,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    (settings ? l10n.wallPanelSettings : l10n.wallPanelFarm)
                        .toUpperCase(),
                    style: t.label.copyWith(
                      color: t.accentGreenInk,
                      letterSpacing: 0.4,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ..._panelButtons(
                  context,
                  settingsOpen: settings,
                  onSettings: onSettings,
                  expanded: true,
                  onToggle: onCollapse,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: t.hairline),
          // One scrolling list under the pinned header (D20). Its height is the
          // panel's, never its content's, so switching views cannot resize the
          // grid beside it.
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(10),
              children: [if (settings) const _WallSettings()],
            ),
          ),
        ],
      ),
    );
  }
}

class _WallSettings extends ConsumerWidget {
  const _WallSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSwitchRow(
          tag: 'wall.keep_awake',
          title: l10n.wallKeepAwakeTitle,
          subtitle: l10n.wallKeepAwakeDesc,
          value: ref.watch(wallKeepAwakeProvider),
          onChanged: ref.read(wallKeepAwakeProvider.notifier).set,
        ),
        const SizedBox(height: 12),
        logTag(
          'wall.exit',
          OutlinedButton.icon(
            icon: const Icon(Icons.logout_rounded),
            label: Text(l10n.wallModeExit),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
      ],
    );
  }
}

class _WallRail extends StatelessWidget {
  const _WallRail({required this.onSettings, required this.onExpand});

  final VoidCallback onSettings;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      width: WallScreen.railWidth,
      decoration: t.cardBox,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          const Spacer(),
          Divider(height: 13, indent: 18, endIndent: 18, color: t.hairline),
          ..._panelButtons(
            context,
            settingsOpen: false,
            onSettings: onSettings,
            expanded: false,
            onToggle: onExpand,
          ),
        ],
      ),
    );
  }
}
