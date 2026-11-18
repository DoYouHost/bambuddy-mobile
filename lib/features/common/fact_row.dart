import 'package:material_ui/material_ui.dart';

import '../../core/theme/dash_theme.dart';

/// One fact about a thing: what it is on the left, its value on the right and
/// read first, with an icon in front where the list has them. The row of a spool's
/// details, a user's, and a nozzle's figures.
///
/// One look for the whole app (the scale's `label` in the secondary ink for the
/// name, `body` in the primary ink for the value), so a screen that wants its
/// facts to read differently changes this widget, not a copy of it.
///
/// **The label may take up to 45% of the room beside the icon and the value all
/// the rest, at the row's end.** Two flexible children would each be capped at
/// half of it: a long value then wraps at half the row although its label is
/// short. Only the value is flexible here, and the space between pushes a short
/// one to the end.
///
/// [stacked] puts the value under the label, for free text that would otherwise
/// wrap into a narrow right-aligned column. [below] goes under the whole row,
/// lined up with the label.
class FactRow extends StatelessWidget {
  /// A text value in the row's own style.
  FactRow({
    super.key,
    this.icon,
    required this.label,
    required String value,
    this.stacked = false,
    this.below,
  }) : _value = Text(value);

  /// A value that is more than a string — a colour beside a name, a serial in
  /// the mono face. It takes the row's text style and alignment, and a `Text`
  /// in it may override the face.
  const FactRow.custom({
    super.key,
    this.icon,
    required this.label,
    required Widget value,
    this.stacked = false,
    this.below,
  }) : _value = value; // ignore: prefer_initializing_formals

  final IconData? icon;
  final String label;
  final Widget _value;
  final bool stacked;
  final Widget? below;

  /// Puts a 16 dp icon on the first line of the label next to it.
  static const _iconNudge = 2.0;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final labelText = Text(
      label,
      style: t.label.copyWith(color: t.textSecondary),
    );
    final value = DefaultTextStyle.merge(
      textAlign: stacked ? TextAlign.start : TextAlign.end,
      style: t.body.copyWith(color: t.textPrimary),
      child: _value,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DashSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: _iconNudge),
              child: Icon(icon, size: DashIcon.sm, color: t.textSecondary),
            ),
            const SizedBox(width: DashSpace.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (stacked) ...[
                  labelText,
                  const SizedBox(height: DashSpace.xs),
                  value,
                ] else
                  LayoutBuilder(
                    builder: (context, constraints) => Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth * 0.45,
                          ),
                          child: labelText,
                        ),
                        const SizedBox(width: DashSpace.md),
                        Flexible(child: value),
                      ],
                    ),
                  ),
                if (below != null) ...[
                  const SizedBox(height: DashSpace.sm),
                  below!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
