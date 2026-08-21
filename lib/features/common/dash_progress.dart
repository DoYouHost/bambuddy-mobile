import 'package:flutter/material.dart';

/// What a screen shows while it has nothing else to show — the spinner alone,
/// centred in whatever space it was given.
class DashLoading extends StatelessWidget {
  const DashLoading({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

/// The spinner that stands in for an icon or a label while one action runs.
///
/// [size] is the slot it replaces, so the row does not reflow when the spinner
/// appears; the stroke stays thin at every size, or it reads as a second icon
/// rather than as waiting. [color] is for the ones that sit on an accent fill,
/// where the default would vanish.
class DashSpinner extends StatelessWidget {
  const DashSpinner({super.key, this.size = 18, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );
}
