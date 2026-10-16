import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/duration_format.dart';
import '../../core/models/printer_status.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../dashboard/widgets/printer_state_pill.dart';
import 'controller_faults.dart';
import 'controller_providers.dart';

/// Where the saver's box is and where it is heading, and its hue.
typedef Bounce = ({Offset position, Offset velocity, double hue});

/// One step of the box: it moves by [dt] and turns at the edges of [room]. Every
/// wall it meets turns its hue — by 90° for a side, by 60° for the top or the
/// bottom, so a corner turns it by both
/// ([docs/single-printer-controller.md] §3).
Bounce bounceStep(Bounce b, Duration dt, Size room, Size box) {
  final seconds = dt.inMicroseconds / Duration.microsecondsPerSecond;
  var x = b.position.dx + b.velocity.dx * seconds;
  var y = b.position.dy + b.velocity.dy * seconds;
  var vx = b.velocity.dx;
  var vy = b.velocity.dy;
  var hue = b.hue;
  final maxX = (room.width - box.width).clamp(0.0, double.infinity);
  final maxY = (room.height - box.height).clamp(0.0, double.infinity);
  if (x <= 0 || x >= maxX) {
    x = x.clamp(0.0, maxX);
    vx = x == 0 ? vx.abs() : -vx.abs();
    hue += _sideTurn;
  }
  if (y <= 0 || y >= maxY) {
    y = y.clamp(0.0, maxY);
    vy = y == 0 ? vy.abs() : -vy.abs();
    hue += _edgeTurn;
  }
  return (position: Offset(x, y), velocity: Offset(vx, vy), hue: hue % 360);
}

const _sideTurn = 90.0;
const _edgeTurn = 60.0;

/// Wraps the controller: counts the time since the last touch and, once it
/// passes the "Start after" setting, puts the saver over everything — an open
/// dialog included. Any touch anywhere restarts the count; a touch on the saver
/// only takes it away ([docs/single-printer-controller.md] §3).
///
/// It also answers this printer's faults: one that has paused the print wakes
/// the screen and opens the fault view, and any other new one wakes it when
/// "Wake on warnings" is on. A fault already there when the controller opened
/// is on screen in the chip, so it raises nothing.
class ControllerSaverHost extends ConsumerStatefulWidget {
  const ControllerSaverHost({
    super.key,
    required this.printerId,
    required this.child,
  });

  final int printerId;
  final Widget child;

  @override
  ConsumerState<ControllerSaverHost> createState() =>
      ControllerSaverHostState();
}

class ControllerSaverHostState extends ConsumerState<ControllerSaverHost> {
  Timer? _idle;
  OverlayEntry? _saver;

  /// Faults that have woken the screen, and faults the alert has been shown
  /// for, by code. A fault that was a warning first and then paused the print
  /// is in the first and not yet in the second.
  final _woken = <String>{};
  final _alerted = <String>{};
  bool _alertOpen = false;

  bool get saverUp => _saver != null;

  @override
  void initState() {
    super.initState();
    // Global, not a Listener over the screen: a touch in a dialog or a sheet,
    // which are routes of their own, is activity too.
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    ref.listenManual(
      controllerPrefsProvider.select((p) => p.saverAfter),
      (_, _) => _restart(),
    );
    final present = _codes(
      ref.read(controllerErrorsProvider(widget.printerId)),
    );
    _woken.addAll(present);
    _alerted.addAll(present);
    ref.listenManual(
      controllerErrorsProvider(widget.printerId),
      (_, _) => _onFaults(),
    );
    ref.listenManual(
      controllerPrinterProvider(
        widget.printerId,
      ).select((p) => p.item?.status?.isPaused ?? false),
      (_, _) => _onFaults(),
    );
    _restart();
  }

  static Set<String> _codes(List<HmsError> errors) => {
    for (final e in errors) e.fullCode ?? e.displayCode,
  };

  void _onFaults() {
    final codes = _codes(ref.read(controllerErrorsProvider(widget.printerId)));
    // A cleared fault that comes back is new again.
    _woken.retainAll(codes);
    _alerted.retainAll(codes);
    final paused =
        ref
            .read(controllerPrinterProvider(widget.printerId))
            .item
            ?.status
            ?.isPaused ??
        false;
    if (paused && !codes.every(_alerted.contains)) {
      _alerted.addAll(codes);
      _woken.addAll(codes);
      wake();
      _openAlert();
      return;
    }
    if (!codes.every(_woken.contains)) {
      _woken.addAll(codes);
      if (ref.read(controllerPrefsProvider).wakeOnWarnings) wake();
    }
  }

  Future<void> _openAlert() async {
    if (_alertOpen || !mounted) return;
    _alertOpen = true;
    await showControllerFaults(
      context,
      widget.printerId,
      title: AppLocalizations.of(context).controllerPrintPaused,
    );
    _alertOpen = false;
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    _idle?.cancel();
    _saver?.remove();
    super.dispose();
  }

  void _onPointer(PointerEvent event) {
    if (event is! PointerDownEvent) return;
    wake();
  }

  /// Takes the saver away, if it is up, and starts the count again.
  void wake() {
    _saver?.remove();
    _saver = null;
    _restart();
  }

  void _restart() {
    _idle?.cancel();
    final after = ref.read(controllerPrefsProvider).saverAfter;
    if (after == null) return;
    _idle = Timer(after, _show);
  }

  void _show() {
    if (!mounted || _saver != null) return;
    _saver = OverlayEntry(
      builder: (_) => ControllerSaver(printerId: widget.printerId),
    );
    Overlay.of(context, rootOverlay: true).insert(_saver!);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The saver itself: black, with a dim box carrying the job's progress that
/// travels the screen. It takes every touch, so nothing under it is pressed;
/// the host's pointer route is what wakes it.
class ControllerSaver extends ConsumerStatefulWidget {
  const ControllerSaver({super.key, required this.printerId});

  final int printerId;

  /// The box's own size; it is laid out at this and bounced within the screen.
  static const box = Size(300, 150);

  @override
  ConsumerState<ControllerSaver> createState() => _ControllerSaverState();
}

class _ControllerSaverState extends ConsumerState<ControllerSaver>
    with SingleTickerProviderStateMixin {
  /// Different speeds on the two axes, so the box meets a corner only now and
  /// then, as the old DVD logo did.
  Bounce _bounce = (
    position: const Offset(40, 30),
    velocity: const Offset(48, 31),
    hue: 140,
  );
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  Size _room = Size.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final dt = elapsed - _last;
      _last = elapsed;
      if (_room.isEmpty) return;
      setState(
        () => _bounce = bounceStep(_bounce, dt, _room, ControllerSaver.box),
      );
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = ref.watch(
      controllerPrefsProvider.select((p) => p.saverBrightness),
    );
    final color = HSVColor.fromAHSV(1, _bounce.hue, 0.55, 1).toColor();
    return Listener(
      behavior: HitTestBehavior.opaque,
      child: ColoredBox(
        color: Colors.black,
        child: LayoutBuilder(
          builder: (context, box) {
            _room = box.biggest;
            return Stack(
              children: [
                Positioned(
                  left: _bounce.position.dx,
                  top: _bounce.position.dy,
                  width: ControllerSaver.box.width,
                  height: ControllerSaver.box.height,
                  child: Opacity(
                    opacity: brightness / 100,
                    child: _SaverBox(printerId: widget.printerId, color: color),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SaverBox extends ConsumerWidget {
  const _SaverBox({required this.printerId, required this.color});

  final int printerId;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final item = ref.watch(controllerPrinterProvider(printerId)).item;
    final status = item?.status;
    final job = status != null && (status.isPrinting || status.isPaused);
    final remaining = status?.remainingTime;
    final ink = t.bodySoft.copyWith(color: color);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DashSpace.xl),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(DashSpace.lg),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (job) ...[
                Row(
                  children: [
                    Text(
                      '${status.progress ?? 0}%',
                      style: t.monoDisplay.copyWith(
                        color: color,
                        fontSize: _percentFont,
                      ),
                    ),
                    const SizedBox(width: DashSpace.lg),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (status.layerNum != null &&
                            status.totalLayers != null)
                          Text(
                            '${status.layerNum}/${status.totalLayers}',
                            style: ink,
                          ),
                        if (remaining != null && remaining > 0)
                          Text(
                            l10n.remaining(formatMinutes(l10n, remaining)),
                            style: ink,
                          ),
                      ],
                    ),
                  ],
                ),
                Text(
                  [
                    ?(status.currentPrint ?? status.gcodeFile),
                    ?item?.printer.name,
                  ].join(' · '),
                  style: ink,
                  maxLines: 1,
                ),
              ] else ...[
                Text(
                  item?.printer.name ?? '',
                  style: t.titleLg.copyWith(color: color),
                ),
                if (status != null) ...[
                  const SizedBox(height: DashSpace.sm),
                  printerStatePill(t, l10n, status, offline: false),
                ],
              ],
              const SizedBox(height: DashSpace.sm),
              Text(l10n.controllerTouchToWake, style: t.labelSoft),
            ],
          ),
        ),
      ),
    );
  }

  static const _percentFont = 44.0;
}
