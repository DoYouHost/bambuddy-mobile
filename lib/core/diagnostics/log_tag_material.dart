import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/widgets.dart';

import 'filament_material.dart';

export 'package:app_diagnostics/app_diagnostics.dart' show logTag, LogTagged;

/// Names a control and the filament material it shows — the one exception to
/// the rule that the log carries identifiers and never content.
///
/// The material rides *inside* the identifier because semantics is the only
/// channel the probe has, and `InteractionProbe.decompose` splits it back out.
/// Why that is safe: `FilamentMaterial`'s closed list, and
/// `docs/diagnostics-log.md`.
Widget logTagMaterial(String id, String? material, Widget child) =>
    logTag(FilamentMaterial.join(id, material), child);

extension LogTaggedMaterial on Widget {
  Widget taggedMaterial(String id, String? material) =>
      logTagMaterial(id, material, this);
}
