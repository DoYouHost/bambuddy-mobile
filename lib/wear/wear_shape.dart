import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/platform/platform_query.dart';

/// The physical shape of a watch display.
enum WearShape {
  /// The usual Wear OS face, and the one the layout has to dodge:
  /// `wearFaceInsets` cuts the viewport down to the rectangle it inscribes.
  round,

  /// A square or rectangular face, which keeps its corners.
  square,
}

/// Asks the platform whether the display is round, through [MainActivity]'s
/// `wear_shape` channel (`Configuration.isScreenRound`).
///
/// Flutter has no answer of its own: a round display is not a view inset, so
/// `SafeArea` is blind to it — which is how the first list row and the setup
/// button ended up under the bezel in the build Google Play rejected.
///
/// Every failure resolves to [WearShape.round]: it is both the common form
/// factor and the stricter geometry, so a phone, a test without the channel or a
/// platform that answers nothing all err on the safe side.
class WearShapeQuery {
  const WearShapeQuery({this.platform = _platform});

  static const _platform = PlatformQuery(
    MethodChannel('page.codeberg.morganmlgman.bambuddy/wear_shape'),
  );

  /// Who to ask. Injectable so a test can answer for a square face.
  final PlatformQuery platform;

  Future<WearShape> read() async =>
      await platform.ask('isScreenRound', fallback: true)
          ? WearShape.round
          : WearShape.square;
}

/// Reads the watch's shape once and hands it to everything below.
///
/// Sits above the navigator so routes and dialogs read the same answer. Screens
/// take it from [wearShapeOf] rather than from here directly, so a widget pumped
/// without a scope still gets a sane shape instead of an exception.
class WearShapeScope extends StatefulWidget {
  const WearShapeScope({
    super.key,
    required this.child,
    this.query = const WearShapeQuery(),
  });

  final Widget child;

  /// How the shape is obtained. Overridden in tests; there is one implementation.
  final WearShapeQuery query;

  @override
  State<WearShapeScope> createState() => _WearShapeScopeState();
}

class _WearShapeScopeState extends State<WearShapeScope> {
  /// Round until the platform says otherwise — the answer arrives a frame or two
  /// in, and a square face laid out for a round one is merely roomy, while the
  /// other way round is the rejection.
  WearShape _shape = WearShape.round;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final shape = await widget.query.read();
    if (mounted && shape != _shape) setState(() => _shape = shape);
  }

  @override
  Widget build(BuildContext context) =>
      _WearShapeData(shape: _shape, child: widget.child);
}

class _WearShapeData extends InheritedWidget {
  const _WearShapeData({required this.shape, required super.child});

  final WearShape shape;

  @override
  bool updateShouldNotify(_WearShapeData oldWidget) => shape != oldWidget.shape;
}

/// The shape the nearest [WearShapeScope] resolved, or round where there is
/// none.
WearShape wearShapeOf(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<_WearShapeData>()?.shape ??
    WearShape.round;
