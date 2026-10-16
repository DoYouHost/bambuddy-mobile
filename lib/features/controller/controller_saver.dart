import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/datetime_format.dart';
import '../../core/format/duration_format.dart';
import '../../core/models/printer_status.dart';
import '../../core/notifications/hms_catalog.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../dashboard/widgets/printer_state_pill.dart';
import '../wall/wall_providers.dart';
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

/// The colour the box is drawn in for [hue]: the full turn of [bounceStep]
/// squeezed into green, teal, blue and violet. Red, amber and yellow are what
/// a fault looks like in this app, and a saver drifting through them read as a
/// printer asking for attention.
double calmHue(double hue) =>
    _calmFrom + (hue % 360) / 360 * (_calmTo - _calmFrom);

const _calmFrom = 130.0;
const _calmTo = 280.0;

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

  bool get saverUp => _saver != null;

  /// Read in `initState`: `dispose` must not touch `ref`.
  late final ScreenAwake _awake;

  @override
  void initState() {
    super.initState();
    _awake = ref.read(screenAwakeProvider);
    // Global, not a Listener over the screen: a touch in a dialog or a sheet,
    // which are routes of their own, is activity too.
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    ref.listenManual(
      controllerPrefsProvider.select((p) => (p.saverAfter, p.keepAwake)),
      (_, _) => _restart(),
    );
    final present = _codes(
      ref.read(controllerErrorsProvider(widget.printerId)),
    );
    _woken.addAll(present);
    // Already paused by it: the chip says so. Still printing: the pause, when
    // it comes, is news, and raises the alert then.
    if (_paused) _alerted.addAll(present);
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

  PrinterStatus? get _status =>
      ref.read(controllerPrinterProvider(widget.printerId)).item?.status;

  bool get _paused => _status?.isPaused ?? false;

  void _onFaults() {
    // A printer that drops off the network lists no faults
    // (`displayableHmsErrors`); that is not its faults clearing, and a fault
    // already answered must not raise the alert again when it comes back.
    final status = _status;
    if (!(status?.connected ?? false)) return;
    // From the status just read, not from [controllerErrorsProvider]: on a
    // reconnect this runs before that provider has caught up, and a stale
    // empty list would read as every fault cleared.
    final codes = _codes(
      displayableHmsErrors(status, describe: HmsCatalog.instance.describe),
    );
    // A cleared fault that comes back is new again.
    _woken.retainAll(codes);
    _alerted.retainAll(codes);
    if (_paused && !codes.every(_alerted.contains)) {
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

  void _openAlert() {
    if (!mounted) return;
    showControllerFaults(
      context,
      widget.printerId,
      title: AppLocalizations.of(context).controllerPrintPaused,
    );
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    _idle?.cancel();
    if (_saver != null) {
      _saver!.remove();
      // Leaving the controller with the saver up must not leave the window dim.
      unawaited(_awake.setBrightness(null));
    }
    super.dispose();
  }

  void _onPointer(PointerEvent event) {
    if (event is! PointerDownEvent) return;
    wake();
  }

  /// Takes the saver away, if it is up, and starts the count again.
  void wake() {
    if (_saver != null) {
      _saver!.remove();
      _saver = null;
      unawaited(_awake.setBrightness(null));
    }
    _restart();
  }

  void _restart() {
    _idle?.cancel();
    final prefs = ref.read(controllerPrefsProvider);
    final after = prefs.saverAfter;
    // Without the screen held on, the phone's own timeout turns it off; the
    // saver is not offered then (Settings says so), so it does not count down.
    if (after == null || !prefs.keepAwake) return;
    _idle = Timer(after, show);
  }

  /// Puts the saver up now: the idle timer runs out, or Settings previews it.
  void show() {
    if (!mounted || _saver != null) return;
    unawaited(
      _awake.setBrightness(
        ref.read(controllerPrefsProvider).saverBrightness / 100,
      ),
    );
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
  static const box = Size(440, 200);

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
    // A method, not a closure holding the step: a hot reload swaps a method's
    // body but leaves a running closure on the code it was created with.
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration elapsed) {
    final dt = elapsed - _last;
    _last = elapsed;
    if (_room.isEmpty) return;
    setState(
      () => _bounce = bounceStep(_bounce, dt, _room, ControllerSaver.box),
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = HSVColor.fromAHSV(1, calmHue(_bounce.hue), 0.55, 1).toColor();
    return Listener(
      behavior: HitTestBehavior.opaque,
      // A Material, not a bare colour: the saver is an overlay entry above the
      // screen's own Material, and text without one gets Flutter's yellow
      // underlined fallback style.
      child: Material(
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
                  // Full strength: the brightness setting dims the backlight
                  // itself (the host's `setBrightness`).
                  child: _SaverBox(printerId: widget.printerId, color: color),
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

  static const _ring = 150.0;
  static const _ringStroke = 12.0;
  static const _percentFont = 44.0;
  static const _leftFont = 26.0;
  static const _clockFont = 64.0;

  /// Near-black under the colour: white figures on it carry from across a
  /// room, and the colour stays an accent rather than a wash.
  static const _ground = Color(0xFF0B0C10);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final fmt = DateTimeFormats.of(context);
    final item = ref.watch(controllerPrinterProvider(printerId)).item;
    final status = item?.status;
    final job = status != null && (status.isPrinting || status.isPaused);
    // Rebuilt every frame by the bounce, so the clock keeps itself current.
    final now = DateTime.now();
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DashSpace.xl),
        gradient: RadialGradient(
          center: Alignment.topLeft,
          radius: 1.2,
          colors: [color.withValues(alpha: 0.22), _ground],
        ),
        border: Border.all(color: color.withValues(alpha: 0.85), width: 2),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.18), blurRadius: 18),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(DashSpace.lg),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: job
              ? _job(t, l10n, fmt, status, item!.printer.name, now)
              : _idle(t, l10n, fmt, status, item?.printer.name ?? '', now),
        ),
      ),
    );
  }

  Widget _job(
    DashTokens t,
    AppLocalizations l10n,
    DateTimeFormats fmt,
    PrinterStatus status,
    String printer,
    DateTime now,
  ) {
    final progress = status.progress ?? 0;
    final remaining = status.remainingTime;
    final quiet = t.bodySoft.copyWith(color: t.textSecondary);
    Widget fact(IconData icon, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: DashSpace.lg, color: color),
        const SizedBox(width: DashSpace.xs),
        Text(text, style: quiet),
      ],
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: _ring,
          child: CustomPaint(
            painter: _RingPainter(
              value: (progress / 100).clamp(0.0, 1.0),
              color: color,
              stroke: _ringStroke,
            ),
            child: Center(
              child: Text(
                '${progress.toStringAsFixed(0)}%',
                style: t.monoDisplay.copyWith(
                  color: t.textPrimary,
                  fontSize: _percentFont,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: DashSpace.xl),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _nameWidth),
              child: Text(
                status.currentPrint ?? status.gcodeFile ?? printer,
                style: t.titleLg.copyWith(color: t.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text('$printer · ${fmt.time(now)}', style: quiet),
            if (remaining != null && remaining > 0) ...[
              const SizedBox(height: DashSpace.md),
              Text(
                l10n.remaining(formatMinutes(l10n, remaining)),
                style: t.monoDisplay.copyWith(
                  color: color,
                  fontSize: _leftFont,
                ),
              ),
            ],
            const SizedBox(height: DashSpace.sm),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (status.layerNum != null && status.totalLayers != null) ...[
                  fact(
                    Icons.layers_outlined,
                    '${status.layerNum}/${status.totalLayers}',
                  ),
                  const SizedBox(width: DashSpace.lg),
                ],
                if (remaining != null && remaining > 0)
                  fact(
                    Icons.flag_outlined,
                    l10n.eta(fmt.time(now.add(Duration(minutes: remaining)))),
                  ),
              ],
            ),
            const SizedBox(height: DashSpace.md),
            Text(l10n.controllerTouchToWake, style: t.labelSoft),
          ],
        ),
      ],
    );
  }

  Widget _idle(
    DashTokens t,
    AppLocalizations l10n,
    DateTimeFormats fmt,
    PrinterStatus? status,
    String printer,
    DateTime now,
  ) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        fmt.time(now),
        style: t.monoDisplay.copyWith(
          color: t.textPrimary,
          fontSize: _clockFont,
        ),
      ),
      const SizedBox(height: DashSpace.xs),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(printer, style: t.titleLg.copyWith(color: color)),
          if (status != null) ...[
            const SizedBox(width: DashSpace.md),
            printerStatePill(t, l10n, status, offline: false),
          ],
        ],
      ),
      const SizedBox(height: DashSpace.md),
      Text(l10n.controllerTouchToWake, style: t.labelSoft),
    ],
  );

  /// The file name never runs the box wider than this.
  static const _nameWidth = 260.0;
}

/// The progress ring: a dim track, and an arc from 12 o'clock with round
/// ends.
class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.value,
    required this.color,
    required this.stroke,
  });

  final double value;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color.withValues(alpha: 0.14);
    canvas.drawArc(rect, 0, 2 * math.pi, false, track);
    if (value <= 0) return;
    final sweep = 2 * math.pi * value;
    // One colour: a sweep gradient wraps around where the round cap reaches
    // back past 12 o'clock, and painted a bright blob at the start.
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, -math.pi / 2, sweep, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.stroke != stroke;
}
