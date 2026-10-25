import 'package:material_ui/material_ui.dart';

import '../../core/theme/dash_theme.dart';
import '../wear_theme.dart';

/// Wear Material 3's `SwitchButton` (androidx-main `SwitchButton.kt`,
/// `SwitchButtonTokens`, `AnimateTick.kt`): a full-width row, the label at the
/// start and the switch at the end, the whole row the tap target.
///
/// Not ported: the thumb's slide and the tick's draw-in animation, and the
/// disabled state, which nothing on the watch needs yet.
class WearSwitchButton extends StatelessWidget {
  const WearSwitchButton({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = value ? scheme.onPrimaryContainer : scheme.onSurface;
    return Semantics(
      toggled: value,
      child: Material(
        color: value ? scheme.primaryContainer : scheme.surfaceContainer,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onChanged(!value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: wearButtonHeight),
            child: Padding(
              // SwitchButtonDefaults.ContentPadding is 14 by 8.
              padding: const EdgeInsets.symmetric(
                horizontal: WearSpace.buttonHorizontal,
                vertical: DashSpace.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: wearButtonLabel.copyWith(color: content),
                    ),
                  ),
                  // TOGGLE_CONTROL_SPACING is 6; WearSpace has no 6, and a
                  // gap typed in here is what spacing_scale_test refuses.
                  const SizedBox(width: DashSpace.sm),
                  ExcludeSemantics(
                    child: CustomPaint(
                      size: const Size(_switchWidth, _switchOuterHeight),
                      painter: _SwitchPainter(
                        checked: value,
                        rtl: Directionality.of(context) == TextDirection.rtl,
                        track: value ? scheme.primary : scheme.surfaceContainer,
                        trackBorder: value ? scheme.primary : scheme.outline,
                        thumb: value ? scheme.primaryContainer : scheme.outline,
                        tick: scheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _switchWidth = 32.0;
const _switchOuterHeight = 24.0;
const _switchInnerHeight = 22.0;
const _trackBorderWidth = 2.0;
const _thumbRadiusUnchecked = 6.0;
const _thumbRadiusChecked = 9.0;

class _SwitchPainter extends CustomPainter {
  _SwitchPainter({
    required this.checked,
    required this.rtl,
    required this.track,
    required this.trackBorder,
    required this.thumb,
    required this.tick,
  });

  final bool checked;
  final bool rtl;
  final Color track;
  final Color trackBorder;
  final Color thumb;
  final Color tick;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: _switchWidth,
      height: _switchInnerHeight,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)),
      Paint()..color = track,
    );
    // Drawn only when it differs from the track, as the original does.
    if (trackBorder != track) {
      final inner = rect.deflate(_trackBorderWidth / 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(inner, Radius.circular(inner.height / 2)),
        Paint()
          ..color = trackBorder
          ..style = PaintingStyle.stroke
          ..strokeWidth = _trackBorderWidth,
      );
    }

    final radius = checked ? _thumbRadiusChecked : _thumbRadiusUnchecked;
    final inset = _switchInnerHeight / 2 - radius;
    // On sits at the end of the track, which is the left in RTL.
    final atRight = checked != rtl;
    final center = Offset(
      atRight ? rect.right - radius - inset : rect.left + radius + inset,
      rect.center.dy,
    );
    canvas.drawCircle(center, radius, Paint()..color = thumb);

    if (!checked) return;
    // The tick's path is drawn on a 24 by 24 design centred on (12, 12).
    final origin = center - const Offset(12, 12);
    canvas.drawPath(
      Path()
        ..moveTo(origin.dx + 7.4, origin.dy + 13)
        ..relativeLineTo(2.5, 2.5)
        ..moveTo(origin.dx + 10.5, origin.dy + 15.1)
        ..relativeLineTo(6, -6),
      Paint()
        ..color = tick
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SwitchPainter old) =>
      old.checked != checked ||
      old.rtl != rtl ||
      old.track != track ||
      old.trackBorder != trackBorder ||
      old.thumb != thumb ||
      old.tick != tick;
}
