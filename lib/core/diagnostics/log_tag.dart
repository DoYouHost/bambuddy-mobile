import 'package:flutter/widgets.dart';

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

extension LogTagged on Widget {
  /// Same as [logTag], written after the widget instead of around it — for
  /// long widget expressions, where wrapping would re-indent the whole tree.
  Widget tagged(String id) => logTag(id, this);
}
