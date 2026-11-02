import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the screens tell the guided tour: that the user did the thing a step
/// asks for, and where the controls a step points at are. Event and target
/// names follow the diagnostic ids of the controls involved.
class TourBeacon {
  TourBeacon(this._onEvent);

  final void Function(String event) _onEvent;

  /// Newest last: a drag proxy or a route on its way in mounts a second copy
  /// of a target, and the original must be back in charge once it is gone.
  final _targets = <String, List<BuildContext>>{};

  void signal(String event) => _onEvent(event);

  void register(String id, BuildContext context) =>
      (_targets[id] ??= []).add(context);

  void unregister(String id, BuildContext context) {
    final contexts = _targets[id];
    contexts?.remove(context);
    if (contexts?.isEmpty ?? false) _targets.remove(id);
  }

  BuildContext? contextOf(String id) => _targets[id]?.lastOrNull;

  /// The on-screen rectangle of the first of [ids] that is laid out, in
  /// global coordinates. Several ids let a step follow its control into a
  /// drawer or a sheet that is not open yet.
  Rect? rectOf(List<String> ids) {
    for (final id in ids) {
      final box = contextOf(id)?.findRenderObject();
      if (box is RenderBox && box.attached && box.hasSize) {
        return box.localToGlobal(Offset.zero) & box.size;
      }
    }
    return null;
  }
}

/// Non-null only inside the guided tour's demo container, so it doubles as the
/// "am I in the tour" check for code that must not touch the phone itself
/// (the background service, the home-screen widget, the watch).
final tourBeaconProvider = Provider<TourBeacon?>((_) => null);

/// Marks [child] as something a tour step can point at. Outside the tour it
/// adds nothing to the tree.
class TourTarget extends ConsumerStatefulWidget {
  const TourTarget({super.key, required this.id, required this.child});

  final String id;
  final Widget child;

  @override
  ConsumerState<TourTarget> createState() => _TourTargetState();
}

class _TourTargetState extends ConsumerState<TourTarget> {
  TourBeacon? _beacon;

  @override
  void initState() {
    super.initState();
    _beacon = ref.read(tourBeaconProvider)?..register(widget.id, context);
  }

  @override
  void didUpdateWidget(TourTarget old) {
    super.didUpdateWidget(old);
    if (old.id == widget.id) return;
    _beacon
      ?..unregister(old.id, context)
      ..register(widget.id, context);
  }

  // Out of the registry while inactive, not only once disposed: an element
  // taken out of the tree (a drawer closing) stays inactive until the end of
  // the frame, and the spotlight paints before then — asking an inactive
  // element for its render object is an error.
  @override
  void deactivate() {
    _beacon?.unregister(widget.id, context);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _beacon?.register(widget.id, context);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

extension TourTargetWidget on Widget {
  /// `.tagged(id)`'s twin for the tour, usually with the same id.
  Widget tourTarget(String id) => TourTarget(id: id, child: this);
}
