import 'package:flutter/widgets.dart';

import 'filament_material.dart';

/// Names a control for the diagnostic log; untagged, a tap on it records only
/// `role=button`. How to pick an id, and why labels are never recorded:
/// `docs/diagnostics-log.md`.
Widget logTag(String id, Widget child) =>
    Semantics(identifier: id, child: child);

/// Names a control and the filament material it shows, the one exception to the
/// rule above.
Widget logTagMaterial(String id, String? material, Widget child) =>
    logTag(FilamentMaterial.join(id, material), child);

extension LogTagged on Widget {
  /// Postfix [logTag], for long expressions where wrapping would re-indent.
  Widget tagged(String id) => logTag(id, this);

  Widget taggedMaterial(String id, String? material) =>
      logTagMaterial(id, material, this);
}
