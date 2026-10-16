import 'dart:async';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/printers/offline_debounce.dart';
import '../../core/theme/dash_theme.dart';
import '../../data/printers_repository.dart';
import '../../l10n/app_localizations.dart';
import '../dashboard/widgets/printer_state_pill.dart';
import '../dashboard/ws_providers.dart';
import '../wall/wall_providers.dart';
import 'controller_filament.dart';
import 'controller_heat.dart';
import 'controller_move.dart';
import 'controller_overview.dart';
import 'controller_picker.dart';
import 'controller_providers.dart';

const _landscape = [
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
];

enum ControllerTab {
  overview,
  heat,
  move,
  filament;

  String label(AppLocalizations l10n) => switch (this) {
    ControllerTab.overview => l10n.controllerTabOverview,
    ControllerTab.heat => l10n.controllerTabHeat,
    ControllerTab.move => l10n.ctrlMove,
    ControllerTab.filament => l10n.controllerTabFilament,
  };

  /// Wire value of the control's diagnostic id; never localized.
  String get logId => switch (this) {
    ControllerTab.overview => 'controller.tab_overview',
    ControllerTab.heat => 'controller.tab_heat',
    ControllerTab.move => 'controller.tab_move',
    ControllerTab.filament => 'controller.tab_filament',
  };
}

/// The single-printer touch screen for a phone on a stand
/// ([docs/single-printer-controller.md]): landscape, no system bars, the screen
/// held on while the setting says so. It is opened for one printer and reads
/// that printer through [controllerPrinterProvider] only.
///
/// Pushed over the dashboard, never swapped in for it: the dashboard owns the
/// foreground service and the token refreshers, which must keep running under
/// it.
class ControllerScreen extends ConsumerStatefulWidget {
  const ControllerScreen({super.key, required this.printerId});

  final int printerId;

  @override
  ConsumerState<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends ConsumerState<ControllerScreen> {
  // Read once here: `dispose` must still reach it, and `ref` is gone by then.
  late final ScreenAwake _awake;
  final _debounce = OfflineDebounce();
  ControllerTab _tab = ControllerTab.overview;

  // No status at all is a roster without a frame: unreachable, as the printer
  // card reads it. A printer that is not in the roster says nothing either way.
  bool? _reachability(ControllerPrinter printer) {
    final item = printer.item;
    if (item == null) return null;
    return item.status == null ? false : item.status!.connected;
  }

  @override
  void initState() {
    super.initState();
    _awake = ref.read(screenAwakeProvider);
    unawaited(SystemChrome.setPreferredOrientations(_landscape));
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    unawaited(_awake.set(ref.read(controllerPrefsProvider).keepAwake));
    final printer = controllerPrinterProvider(widget.printerId);
    _debounce.seed(_reachability(ref.read(printer)));
    ref.listenManual(printer.select(_reachability), (_, connected) {
      final since = ref.read(printerStatusesProvider.notifier).inTouchSince;
      _debounce.observe(
        connected,
        debounce:
            since == null || clock.now().difference(since) >= _debounce.window,
        onSustained: () {
          if (mounted) setState(() {});
        },
      );
    });
  }

  @override
  void dispose() {
    _debounce.dispose();
    // Every way out lands here — Back, and `/setup` replacing the whole stack
    // when the session expires — so the rest of the app gets its free rotation,
    // its bars and its screen timeout back on each of them. The app sets no
    // orientation of its own, so "restore" is the empty list, and the bars come
    // back as the overlays the activity starts with (see WallScreen).
    unawaited(SystemChrome.setPreferredOrientations(const []));
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      ),
    );
    unawaited(_awake.set(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(
      controllerPrefsProvider.select((p) => p.keepAwake),
      (_, on) => _awake.set(on),
    );
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final printer = ref.watch(controllerPrinterProvider(widget.printerId));
    final item = printer.item;

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              DashSpace.gutter,
              0,
              DashSpace.gutter,
              DashSpace.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (item != null)
                  _TopBar(
                    item: item,
                    offline: _debounce.offline,
                    tab: _tab,
                    onTab: (tab) => setState(() => _tab = tab),
                  )
                else
                  const _BareBar(),
                const SizedBox(height: DashSpace.md),
                Expanded(
                  child: !printer.rosterKnown
                      ? const Center(child: CircularProgressIndicator())
                      : item == null
                      ? Center(
                          child: Text(
                            l10n.controllerPrinterGone,
                            style: t.bodySoft,
                            textAlign: TextAlign.center,
                          ),
                        )
                      : switch (_tab) {
                          ControllerTab.overview => ControllerOverview(
                            printerId: widget.printerId,
                          ),
                          ControllerTab.heat => ControllerHeat(
                            printerId: widget.printerId,
                          ),
                          ControllerTab.move => ControllerMove(
                            printerId: widget.printerId,
                          ),
                          ControllerTab.filament => ControllerFilament(
                            printerId: widget.printerId,
                          ),
                        },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A button's own height; the bar is built around the targets, not the reverse.
const _barHeight = 44.0;

/// The bar for a printer that is not (yet) there: only the way out.
class _BareBar extends StatelessWidget {
  const _BareBar();

  @override
  Widget build(BuildContext context) =>
      Align(alignment: Alignment.centerLeft, child: _ExitButton());
}

class _ExitButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return logTag(
      'controller.exit',
      IconButton(
        tooltip: AppLocalizations.of(context).controllerExit,
        color: t.textPrimary,
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}

/// Exit, the printer with its switcher, the tabs and the printer's state.
class _TopBar extends ConsumerWidget {
  const _TopBar({
    required this.item,
    required this.offline,
    required this.tab,
    required this.onTab,
  });

  final PrinterWithStatus item;
  final bool offline;
  final ControllerTab tab;
  final ValueChanged<ControllerTab> onTab;

  /// The name never takes more than this, so a long one cannot push the tabs
  /// off a phone-width bar.
  static const _nameMaxWidth = 190.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final printer = item.printer;
    final several = ref.watch(
      wallRosterProvider.select((r) => (r?.length ?? 0) > 1),
    );
    Widget name({required bool chevron}) => ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: _nameMaxWidth,
        minHeight: _barHeight,
      ),
      child: Row(
        children: [
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  printer.name,
                  style: t.titleMd,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (printer.model != null)
                  Text(
                    printer.model!,
                    style: t.labelSoft,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (chevron)
            Icon(
              Icons.expand_more_rounded,
              size: DashSpace.lg,
              color: t.textTertiary,
            ),
        ],
      ),
    );
    return Row(
      children: [
        _ExitButton(),
        const SizedBox(width: DashSpace.sm),
        // With one printer there is nothing to switch to, so the name is plain
        // text: a chevron that only reloaded the same screen would be a lie.
        several
            ? logTag(
                'controller.switch_printer',
                Tooltip(
                  message: l10n.controllerSwitchPrinter,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(DashSpace.md),
                    onTap: () => openController(context, ref, replace: true),
                    child: name(chevron: true),
                  ),
                ),
              )
            : name(chevron: false),
        // Scaled down, never up, when the name, the tabs and the state do not
        // fit one line: a long printer name must not push a tab off the screen.
        Expanded(
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _Tabs(tab: tab, onTab: onTab),
            ),
          ),
        ),
        printerStatePill(t, l10n, item.status, offline: offline),
      ],
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.tab, required this.onTab});

  final ControllerTab tab;
  final ValueChanged<ControllerTab> onTab;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(DashSpace.xs),
      decoration: BoxDecoration(
        color: t.subCard,
        borderRadius: BorderRadius.circular(DashSpace.md + DashSpace.xs),
        border: Border.all(color: t.subCardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final candidate in ControllerTab.values)
            logTag(
              candidate.logId,
              _TabButton(
                label: candidate.label(l10n),
                selected: candidate == tab,
                onTap: () => onTab(candidate),
              ),
              selected: candidate == tab,
            ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final radius = BorderRadius.circular(DashSpace.md);
    return Material(
      color: selected ? t.accent.withValues(alpha: 0.16) : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: selected
            ? BorderSide(color: t.accent.withValues(alpha: 0.4))
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: _barHeight),
          padding: const EdgeInsets.symmetric(horizontal: DashSpace.md),
          alignment: Alignment.center,
          child: Text(
            label,
            style: selected
                ? t.bodyBold.copyWith(color: t.accentInk)
                : t.bodyBold,
          ),
        ),
      ),
    );
  }
}
