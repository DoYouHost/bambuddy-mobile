import 'package:flutter/widgets.dart';

import 'filament_material.dart';

/// Names a control for the diagnostic log.
///
/// The log records identifiers and **never** accessibility labels: a label is
/// user-facing text — a model name, a file name, a spool name — and the log goes
/// into a public, permanent issue. So a control the user can press is worth
/// naming here; without it a tap on it reads as `role=button` and nothing more.
///
/// Ids are dotted and stable: `area.thing`, lowercase, never localized, never
/// containing data (`archive.card`, not `archive.card.MyModel`). Repeated rows
/// share one id — which row it was is not what a bug report needs.
///
/// The probe carries an identifier down to the node actually hit, so tagging a
/// card names taps anywhere inside it unless something deeper has its own tag.
Widget logTag(String id, Widget child) =>
    Semantics(identifier: id, child: child);

/// Names a control and records which filament material it is showing.
///
/// The material rides on the identifier (`inventory.spool@PETG`) because the
/// semantics tree is the only channel the probe has; it splits the two apart
/// again, so a record keeps a clean `id` plus a separate `mat` field. Only
/// values from [FilamentMaterial.known] survive — see there for why this one
/// piece of card content is allowed through at all.
Widget logTagMaterial(String id, String? material, Widget child) =>
    logTag(FilamentMaterial.join(id, material), child);

extension LogTagged on Widget {
  /// Same as [logTag], written after the widget instead of around it — for
  /// long widget expressions, where wrapping would re-indent the whole tree.
  Widget tagged(String id) => logTag(id, this);

  /// Postfix form of [logTagMaterial].
  Widget taggedMaterial(String id, String? material) =>
      logTagMaterial(id, material, this);
}
