import 'package:flutter/widgets.dart';

import 'filament_material.dart';

/// Names a control for the diagnostic log; untagged, a tap on it records only
/// `role=button`. How to pick an id, and why labels are never recorded:
/// `docs/diagnostics-log.md`.
/// [selected] marks a control that is one of a set and currently the chosen
/// one (a segment, a preset chip). It rides here rather than on a `Semantics`
/// of its own because the two have to land on the **same** node: a separate
/// wrapper annotates a different one, so the reader announces the state and the
/// log resolves the press somewhere else — or, as measured, the state reaches
/// nobody at all. Nothing about it is recorded; the probe reads [id] only.
Widget logTag(String id, Widget child, {bool? selected}) =>
    Semantics(identifier: id, selected: selected, child: child);

/// Names a control and the filament material it shows, the one exception to the
/// rule above.
Widget logTagMaterial(String id, String? material, Widget child) =>
    logTag(FilamentMaterial.join(id, material), child);

extension LogTagged on Widget {
  /// Postfix [logTag], for long expressions where wrapping would re-indent.
  Widget tagged(String id, {bool? selected}) =>
      logTag(id, this, selected: selected);

  Widget taggedMaterial(String id, String? material) =>
      logTagMaterial(id, material, this);
}
