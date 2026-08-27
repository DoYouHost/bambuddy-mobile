import 'package:flutter/material.dart';

/// The frame every watch screen sits in.
///
/// One line each in four screens, which is exactly why it is written once: the
/// next thing the watch needs around all of them — and there will be one — goes
/// here instead of into four files that have to be found first.
///
/// The [SafeArea] is a guard rather than a working part. Wear OS reports no
/// insets today: a round display is not one, which is why the layout insets
/// itself (`lib/wear/wear_geometry.dart`), and there is no status bar to dodge.
/// It stays because it costs nothing and the day a watch does report an inset —
/// a flat tyre, a squircle with a chin — this is where it would arrive.
class WearScreen extends StatelessWidget {
  const WearScreen({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: child));
}
