import 'package:flutter/material.dart';

import '../../core/theme/dash_theme.dart';

/// The app's linear progress bar: rounded ends, the gauge track behind, the
/// accent in front. A null [value] leaves it indeterminate.
///
/// [height] and [radius] stay with the call site — the bars run from 4 px in a
/// spool row to 8 px on a project card — and [color] is for a bar that means
/// something other than progress towards done: a maintenance interval, a spool
/// low on filament.
class DashProgressBar extends StatelessWidget {
  const DashProgressBar({
    super.key,
    required this.value,
    required this.height,
    this.radius = 4,
    this.color,
  });

  final double? value;
  final double height;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: LinearProgressIndicator(
        value: value,
        minHeight: height,
        backgroundColor: t.gaugeTrack,
        color: color ?? t.accentGreen,
      ),
    );
  }
}
