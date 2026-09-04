import 'package:bambuddy_mobile/core/theme/dash_text.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const t = DashTokens.dark();

  /// The ladder, written out: a role that changes size or weight changes every
  /// screen using it, so it should have to change here first.
  final ladder = <String, (TextStyle, double, FontWeight)>{
    'displayLg': (t.displayLg, 26, FontWeight.w700),
    'display': (t.display, 20, FontWeight.w800),
    'titleLg': (t.titleLg, 18, FontWeight.w800),
    'titleMd': (t.titleMd, 16, FontWeight.w700),
    'titleSm': (t.titleSm, 14, FontWeight.w700),
    'bodyStrong': (t.bodyStrong, 14, FontWeight.w600),
    'body': (t.body, 13, FontWeight.w600),
    'bodyBold': (t.bodyBold, 13, FontWeight.w700),
    'bodySoft': (t.bodySoft, 13, FontWeight.w500),
    'bodyPlain': (t.bodyPlain, 13, FontWeight.w400),
    'label': (t.label, 12, FontWeight.w600),
    'labelSoft': (t.labelSoft, 12, FontWeight.w400),
    'micro': (t.micro, 11, FontWeight.w600),
    'microSoft': (t.microSoft, 11, FontWeight.w400),
    'monoDisplay': (t.monoDisplay, 26, FontWeight.w700),
    'monoHeadline': (t.monoHeadline, 18, FontWeight.w700),
    'monoTitle': (t.monoTitle, 16, FontWeight.w800),
    'monoValue': (t.monoValue, 13, FontWeight.w600),
    'monoLabel': (t.monoLabel, 11, FontWeight.w600),
    'monoMicro': (t.monoMicro, 11, FontWeight.w400),
  };

  test('every role sits on its step of the ladder', () {
    ladder.forEach((name, spec) {
      final (style, size, weight) = spec;
      expect(style.fontSize, size, reason: '$name size');
      expect(style.fontWeight, weight, reason: '$name weight');
    });
  });

  test('roles use the app fonts and nothing else', () {
    ladder.forEach((name, spec) {
      final family = spec.$1.fontFamily;
      expect(
        family,
        name.startsWith('mono') ? DashTokens.fontMono : DashTokens.fontUi,
        reason: name,
      );
    });
  });

  test('a role carries a colour, and takes another on request', () {
    expect(t.body.color, t.textPrimary);
    expect(t.label.color, t.textTertiary);
    expect(t.bodySoft.color, t.textSecondary);
    expect(t.body.copyWith(color: t.danger).color, t.danger);
    // Overriding the colour must not disturb the step itself.
    expect(t.body.copyWith(color: t.danger).fontSize, t.body.fontSize);
  });

  test('the light theme differs in colour only', () {
    const light = DashTokens.light();
    expect(light.body.fontSize, t.body.fontSize);
    expect(light.body.fontWeight, t.body.fontWeight);
    expect(light.body.color, light.textPrimary);
    expect(light.body.color, isNot(t.body.color));
  });
}
