import 'package:flutter/material.dart';

import '../../../core/theme/dash_theme.dart';

/// Design's 42×24 pill toggle: green track when ON, neutral when OFF, with a
/// sliding knob. Animated; purely presentational (tap handled by parent).
class PillSwitch extends StatelessWidget {
  const PillSwitch({super.key, required this.on, required this.tokens});

  final bool on;
  final DashTokens tokens;

  static const _height = 24.0;
  static const _knob = 20.0;

  @override
  Widget build(BuildContext context) {
    final knobColor = tokens.isDark
        ? const Color(0xFF0A0C08)
        : (on ? Colors.white : const Color(0xFFFFFFFF));
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      width: 42,
      height: _height,
      padding: const EdgeInsets.all((_height - _knob) / 2),
      decoration: BoxDecoration(
        color: on ? tokens.accentGreen : tokens.gaugeTrack,
        borderRadius: BorderRadius.circular(12),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: _knob,
          height: _knob,
          decoration: BoxDecoration(color: knobColor, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
