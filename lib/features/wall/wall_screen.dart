import 'dart:async';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../common/settings_rows.dart';
import '../../core/models/queue_item.dart';
import '../dashboard/ws_providers.dart';
import '../queue/queue_providers.dart';
import 'wall_faults.dart';
import 'wall_layout.dart';
import 'wall_providers.dart';
import 'wall_tile.dart';

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

  /// The server pushes no event for a queue add, delete or reorder (D18).
  static const queuePoll = Duration(seconds: 30);

  @override
  ConsumerState<WallScreen> createState() => _WallScreenState();
}

class _WallScreenState extends ConsumerState<WallScreen> {
  // Read once here: `dispose` must still reach it, and `ref` is gone by then.
  late final ScreenAwake _awake;
  late final AppLifecycleListener _lifecycle;
  Timer? _queuePoll;
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
    _startQueuePoll();
    // D18 polls while the wall is visible, not while the app sits behind
    // another one — the queue screen stops its timer the same way.
    _lifecycle = AppLifecycleListener(
      onShow: _startQueuePoll,
      onHide: _stopQueuePoll,
    );
  }

  void _startQueuePoll() {
    _queuePoll?.cancel();
    // The queue provider outlives this screen (the nav badge keeps it), so
    // what it holds may be old: refresh on entry, then on the poll. One that
    // is still loading its first answer needs no second request beside it.
    if (ref.read(queueProvider).hasValue) {
      unawaited(ref.read(queueProvider.notifier).refresh());
    }
    _queuePoll = Timer.periodic(
      WallScreen.queuePoll,
      (_) => unawaited(ref.read(queueProvider.notifier).refresh()),
    );
  }

  void _stopQueuePoll() {
    _queuePoll?.cancel();
    _queuePoll = null;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _stopQueuePoll();
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

/// The printers, from the same state the dashboard under the wall polls.
class _WallGrid extends ConsumerWidget {
  const _WallGrid();

  static const _gap = 10.0;

  /// A tile shorter than this no longer fits its text; past it the grid
  /// scrolls instead of shrinking further.
  static const _minTileHeight = 120.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final printers = ref.watch(wallPrintersProvider);
    if (printers == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (printers.isEmpty) {
      return Center(
        child: Text(
          l10n.noPrinters,
          style: t.bodySoft,
          textAlign: TextAlign.center,
        ),
      );
    }
    final inTouchSince = ref
        .read(printerStatusesProvider.notifier)
        .inTouchSince;
    return LayoutBuilder(
      builder: (context, box) {
        final cols = wallColumns(
          printers.length,
          box.biggest,
          gap: _gap,
          minTileHeight: _minTileHeight,
        );
        final rows = (printers.length / cols).ceil();
        final fitted = (box.maxHeight - _gap * (rows - 1)) / rows;
        return GridView.builder(
          padding: EdgeInsets.zero,
          itemCount: printers.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: _gap,
            mainAxisSpacing: _gap,
            mainAxisExtent: fitted < _minTileHeight ? _minTileHeight : fitted,
          ),
          itemBuilder: (_, i) => WallTile(
            key: ValueKey(printers[i].printer.id),
            item: printers[i],
            inTouchSince: inTouchSince,
          ),
        );
      },
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
              children: [
                if (settings) const _WallSettings() else const _WallFarm(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The farm view of the panel: active faults, then the queue (D13, D20).
/// Read-only — nothing here acts on a printer.
class _WallFarm extends ConsumerWidget {
  const _WallFarm();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final faults = ref.watch(wallFaultsProvider);
    final queue = ref.watch(queueProvider).valueOrNull ?? const <QueueItem>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(title: l10n.wallErrorsTitle, count: faults.length),
        if (faults.isEmpty)
          _Quiet(l10n.wallNoFaults)
        else
          for (final f in faults) _FaultItem(fault: f),
        const SizedBox(height: 14),
        _SectionHeader(title: l10n.navQueue, count: queue.length),
        if (queue.isEmpty)
          _Quiet(l10n.queueEmpty)
        else
          for (final q in queue) _QueueRow(item: q),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Row(
        children: [
          Expanded(child: Text(title, style: t.bodyBold)),
          Text('$count', style: t.monoLabel),
        ],
      ),
    );
  }
}

/// An empty section says so quietly instead of vanishing, so the layout does
/// not jump when the last fault clears.
class _Quiet extends StatelessWidget {
  const _Quiet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
    child: Text(text, style: DashTokens.of(context).bodySoft),
  );
}

class _PanelItem extends StatelessWidget {
  const _PanelItem({required this.children, this.stripe});

  final List<Widget> children;

  /// A severity stripe down the leading edge, for faults.
  final Color? stripe;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final stripe = this.stripe;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: t.subCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.subCardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: stripe == null
            ? null
            : BoxDecoration(
                border: BorderDirectional(
                  start: BorderSide(color: stripe, width: 3),
                ),
              ),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

class _FaultItem extends StatelessWidget {
  const _FaultItem({required this.fault});

  final WallFault fault;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final level = fault.error.level;
    final text = fault.text;
    // The same code the printer card prints under a fault.
    final code = fault.error.displayCode;
    return _PanelItem(
      // Fatal and serious in red; common, info and unknown in orange.
      stripe: level != null && level <= 2 ? t.danger : t.accentOrange,
      children: [
        Text(
          fault.printer,
          style: t.titleSm,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (text != null) Text(text, style: t.bodySoft),
        Text(code, style: t.monoMicro),
      ],
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.item});

  final QueueItem item;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final model = item.targetModel;
    // Where the job will run, worded as the queue screen words it.
    final target =
        item.printerName ??
        (item.isCrossModel
            ? l10n.queueAnyOfModels(
                [for (final v in item.variants) v.targetModel].join(', '),
              )
            : model != null
            ? l10n.queueEditAnyModel(model)
            : l10n.printLogAnyPrinter);
    final waiting = item.waitingReason;
    return _PanelItem(
      children: [
        Text(
          item.displayName,
          style: t.titleSm,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(target, style: t.bodySoft),
        if (waiting != null && waiting.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.schedule, size: 14, color: t.accentOrangeInk),
                const SizedBox(width: 4),
                // The server's own sentence; it is not localised.
                Expanded(
                  child: Text(
                    waiting,
                    style: t.body.copyWith(color: t.accentOrangeInk),
                  ),
                ),
              ],
            ),
          ),
      ],
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

class _WallRail extends ConsumerWidget {
  const _WallRail({required this.onSettings, required this.onExpand});

  final VoidCallback onSettings;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final faults = ref.watch(wallFaultsProvider).length;
    final queued = ref.watch(queueProvider).valueOrNull?.length ?? 0;
    return Container(
      width: WallScreen.railWidth,
      decoration: t.cardBox,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          // Read-only counts (D20): a new fault still shows here, and on its
          // tile, while the panel is collapsed.
          Semantics(
            label:
                '${l10n.hmsErrorsCount(faults)}, ${l10n.wallQueueCount(queued)}',
            excludeSemantics: true,
            child: Column(
              children: [
                const SizedBox(height: 8),
                _RailCount(
                  icon: Icons.error_outline_rounded,
                  count: faults,
                  color: faults > 0 ? t.danger : t.textSecondary,
                ),
                const SizedBox(height: 14),
                _RailCount(
                  icon: Icons.format_list_numbered_rounded,
                  count: queued,
                  color: t.textSecondary,
                ),
              ],
            ),
          ),
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

class _RailCount extends StatelessWidget {
  const _RailCount({
    required this.icon,
    required this.count,
    required this.color,
  });

  final IconData icon;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Column(
      children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(height: 2),
        Text('$count', style: t.monoValue.copyWith(color: color)),
      ],
    );
  }
}
