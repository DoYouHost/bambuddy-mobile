import 'dart:async';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:clock/clock.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/printers/offline_debounce.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../dashboard/ws_providers.dart';
import '../files/file_manager_providers.dart';
import '../wall/wall_providers.dart';
import 'controller_filament.dart';
import 'controller_heat.dart';
import 'controller_move.dart';
import 'controller_overview.dart';
import 'controller_prints.dart';
import 'controller_rail.dart';
import 'controller_providers.dart';
import 'controller_saver.dart';
import 'controller_settings.dart';
import 'scale_to_fit.dart';

const _landscape = [
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
];

/// How many controller screens are mounted. Switching printers pushes the new
/// screen before the old one is disposed, so the old one must not give back the
/// bars, rotation and screen timeout the new one has just taken.
class _OpenScreens {
  int count = 0;
}

final _openScreensProvider = Provider((_) => _OpenScreens());

enum ControllerTab {
  overview,
  heat,
  move,
  filament,
  prints,
  settings;

  String label(AppLocalizations l10n) => switch (this) {
    ControllerTab.overview => l10n.controllerTabOverview,
    ControllerTab.heat => l10n.controllerTabHeat,
    ControllerTab.move => l10n.ctrlMove,
    ControllerTab.filament => l10n.controllerTabFilament,
    ControllerTab.prints => l10n.controllerTabPrints,
    ControllerTab.settings => l10n.controllerTabSettings,
  };

  /// Wire value of the control's diagnostic id; never localized.
  String get logId => switch (this) {
    ControllerTab.overview => 'controller.tab_overview',
    ControllerTab.heat => 'controller.tab_heat',
    ControllerTab.move => 'controller.tab_move',
    ControllerTab.filament => 'controller.tab_filament',
    ControllerTab.prints => 'controller.tab_prints',
    ControllerTab.settings => 'controller.tab_settings',
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
  late final _OpenScreens _open;
  final _debounce = OfflineDebounce();
  ControllerTab _tab = ControllerTab.overview;
  ControllerPrintsView _printsView = ControllerPrintsView.files;

  /// The rail's panel lies over the screen while this is set; the screen under
  /// it takes no touch and says nothing to a reader until it closes.
  bool _railOpen = false;

  void _setRail(bool open) => setState(() => _railOpen = open);

  /// Keeps the library's folder and search state while another tab or view is
  /// showing: the provider is autoDispose, and the user would otherwise land at
  /// the root each time they came back. Opened by the first visit to Prints,
  /// which opens on Files, so nothing is fetched for someone who never looks;
  /// the state closes it with the screen.
  ProviderSubscription<AsyncValue<FileManagerState>>? _library;

  void _selectTab(ControllerTab tab) {
    if (tab == ControllerTab.prints) {
      _library ??= ref.listenManual(fileManagerProvider, (_, _) {});
    }
    setState(() => _tab = tab);
  }

  void _selectPrintsView(ControllerPrintsView view) =>
      setState(() => _printsView = view);

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
    _open = ref.read(_openScreensProvider);
    _open.count++;
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
    // back as the overlays the activity starts with (see WallScreen). Not while
    // another controller screen is up, which is a printer switch.
    if (--_open.count == 0) {
      unawaited(SystemChrome.setPreferredOrientations(const []));
      unawaited(
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: SystemUiOverlay.values,
        ),
      );
      unawaited(_awake.set(false));
    }
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

    final content = !printer.rosterKnown
        ? const Center(child: CircularProgressIndicator())
        : item == null
        ? Center(
            child: Text(
              l10n.controllerPrinterGone,
              style: t.bodySoft,
              textAlign: TextAlign.center,
            ),
          )
        : ScaleToFit(
            reflows: true,
            child: switch (_tab) {
              ControllerTab.overview => ControllerOverview(
                printerId: widget.printerId,
              ),
              ControllerTab.heat => ControllerHeat(printerId: widget.printerId),
              ControllerTab.move => ControllerMove(printerId: widget.printerId),
              ControllerTab.filament => ControllerFilament(
                printerId: widget.printerId,
              ),
              ControllerTab.prints => ControllerPrints(
                printerId: widget.printerId,
                view: _printsView,
                onView: _selectPrintsView,
              ),
              ControllerTab.settings => const ControllerSettings(),
            },
          );
    // `pop`, not `maybePop`: the panel's Exit is tapped while it is open, when
    // the PopScope below would take a `maybePop` for a request to close it.
    void exit() => Navigator.of(context).pop();

    return PopScope(
      canPop: !_railOpen || item == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _railOpen) _setRail(false);
      },
      child: ControllerSaverHost(
        printerId: widget.printerId,
        child: DashBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            // A keyboard must not shrink the body: every tab is scaled to the
            // room it has, so a smaller room would rescale the whole controller.
            resizeToAvoidBottomInset: false,
            // Icons grow with the text only up to [controllerIconScaleCap]. An icon button
            // has no padding here, so the larger icon fills its fixed box and
            // stays at its centre; with the default padding the box was smaller
            // than the glyph and the glyph was drawn off-centre.
            body: _IconScale(
              // Not the sides: Android reports a camera cutout as an inset down the
              // whole edge, though the hole is a small circle, and the strip it
              // left was the widest empty space on the screen. The gutter keeps
              // the content off the glass edge.
              child: SafeArea(
                left: false,
                right: false,
                child: item == null
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(
                          DashSpace.gutter,
                          0,
                          DashSpace.gutter,
                          DashSpace.sm,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _BareBar(),
                            const SizedBox(height: DashSpace.md),
                            Expanded(child: content),
                          ],
                        ),
                      )
                    : Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              DashSpace.sm,
                              DashSpace.sm,
                              DashSpace.gutter,
                              DashSpace.sm,
                            ),
                            // The rail too is under the panel: a reader would hear
                            // every tab twice.
                            child: ExcludeSemantics(
                              excluding: _railOpen,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  ControllerRail(
                                    tab: _tab,
                                    onTab: _selectTab,
                                    onOpen: () => _setRail(true),
                                  ),
                                  const SizedBox(width: DashSpace.sm),
                                  Expanded(child: content),
                                ],
                              ),
                            ),
                          ),
                          if (_railOpen) ...[
                            Positioned.fill(
                              child: logTag(
                                'controller.rail_scrim',
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => _setRail(false),
                                  child: ColoredBox(
                                    color: Colors.black.withValues(
                                      alpha: DashAlpha.scrim,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: DashSpace.sm,
                              top: DashSpace.sm,
                              bottom: DashSpace.sm,
                              child: ControllerRailPanel(
                                item: item,
                                offline: _debounce.offline,
                                tab: _tab,
                                onTab: (tab) {
                                  _selectTab(tab);
                                  _setRail(false);
                                },
                                onClose: () => _setRail(false),
                                onExit: exit,
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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

/// Sets the size of the controller's icons from the system text size, up to
/// [controllerIconScaleCap]: a bare icon, an icon button's icon and the icon of a filled
/// button, which each have a default size of their own. Nothing changes at the
/// normal text size.
class _IconScale extends StatelessWidget {
  const _IconScale({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = MediaQuery.textScalerOf(context).scale(1);
    final k = text.clamp(1.0, controllerIconScaleCap);
    final theme = Theme.of(context);
    // The same widgets at every size, so a change of the system text size does
    // not remount the tab and lose its state; at the normal size they set
    // nothing the theme does not already say.
    return Theme(
      data: text <= 1
          ? theme
          : theme.copyWith(
              iconButtonTheme: IconButtonThemeData(
                style: (theme.iconButtonTheme.style ?? const ButtonStyle())
                    .copyWith(
                      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                      iconSize: WidgetStatePropertyAll(DashIcon.lg * k),
                    ),
              ),
              filledButtonTheme: FilledButtonThemeData(
                style: (theme.filledButtonTheme.style ?? const ButtonStyle())
                    .copyWith(
                      iconSize: WidgetStatePropertyAll(
                        controllerButtonIconSize * k,
                      ),
                    ),
              ),
            ),
      child: IconTheme.merge(
        data: IconThemeData(applyTextScaling: false, size: DashIcon.lg * k),
        child: child,
      ),
    );
  }
}
