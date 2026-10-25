import 'dart:io';

import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/features/controller/controller_controls.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no button of the controller is a bare outline', () {
    // An outlined button is a border and nothing else, which all but vanishes
    // on the controller's dark ground — and disabled, where the jogs sit while
    // a print runs, it is gone. Buttons go through `controllerButtonStyle`.
    final offenders = [
      for (final file in Directory('lib/features/controller').listSync())
        if (file is File && file.path.endsWith('.dart'))
          if (RegExp(
            r'OutlinedButton|IconButton\.outlined',
          ).hasMatch(file.readAsStringSync()))
            file.path,
    ];

    expect(offenders, isEmpty);
  });

  group('a locked button still reads: its icon and its border stand out', () {
    // The jogs sit disabled for the whole of a print, so this is the look they
    // have most of the time. The tile is blended over the page's ground.
    double contrast(Color a, Color b) {
      final hi = a.computeLuminance() > b.computeLuminance() ? a : b;
      final lo = hi == a ? b : a;
      return (hi.computeLuminance() + 0.05) / (lo.computeLuminance() + 0.05);
    }

    for (final brightness in Brightness.values) {
      final t = brightness == Brightness.dark
          ? DashTokens.dark(bambuddyBrand)
          : DashTokens.light(bambuddyBrand);
      final ground = brightness == Brightness.dark
          ? const Color(0xFF0B0F0C)
          : const Color(0xFFF4F5F0);
      final tones = <String, ButtonStyle>{
        'plain': controllerButtonStyle(t),
        'blue': controllerButtonStyle(t, tone: t.accentBlue),
        'orange': controllerButtonStyle(
          t,
          tone: t.accentOrange,
          ink: t.accentOrangeInk,
        ),
      };
      tones.forEach((name, style) {
        test('$name, $brightness', () {
          final disabled = <WidgetState>{WidgetState.disabled};
          final tile = Color.alphaBlend(
            style.backgroundColor!.resolve(disabled)!,
            ground,
          );
          final icon = Color.alphaBlend(
            style.foregroundColor!.resolve(disabled)!,
            tile,
          );
          final edge = Color.alphaBlend(
            style.side!.resolve(disabled)!.color,
            ground,
          );

          // Grey whatever the tone: a colour means the button works.
          final plain = tones['plain']!;
          expect(
            style.foregroundColor!.resolve(disabled),
            plain.foregroundColor!.resolve(disabled),
          );
          expect(
            style.backgroundColor!.resolve(disabled),
            plain.backgroundColor!.resolve(disabled),
          );
          expect(style.side!.resolve(disabled), plain.side!.resolve(disabled));

          expect(contrast(icon, tile), greaterThanOrEqualTo(3));
          expect(contrast(edge, ground), greaterThanOrEqualTo(1.3));
        });
      });
    }
  });
}
