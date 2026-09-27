import 'dart:io';

import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every role in the type scale, so a weight with no face to render in cannot
/// reach a screen unnoticed.
///
/// Flutter does not complain about a missing weight — it picks the nearest
/// declared one and draws that. `monoTitle` asked for w800 against faces that
/// stopped at 700, so it rendered identically to `monoHeadline` in eleven
/// places while the design asked for two different weights. Nothing failed,
/// nothing logged, and the only way to see it was to compare two headings.
Map<String, TextStyle> _typeScale(DashTokens t) => {
  'displayLg': t.displayLg,
  'display': t.display,
  'titleLg': t.titleLg,
  'titleMd': t.titleMd,
  'titleSm': t.titleSm,
  'bodyStrong': t.bodyStrong,
  'body': t.body,
  'bodyBold': t.bodyBold,
  'bodySoft': t.bodySoft,
  'bodyPlain': t.bodyPlain,
  'label': t.label,
  'labelSoft': t.labelSoft,
  'micro': t.micro,
  'microSoft': t.microSoft,
  'monoDisplay': t.monoDisplay,
  'monoHeadline': t.monoHeadline,
  'monoTitle': t.monoTitle,
  'monoValue': t.monoValue,
  'monoLabel': t.monoLabel,
  'monoMicro': t.monoMicro,
};

/// `family -> declared weights`, read out of the pubspec rather than restated
/// here: the point is to compare the app against what it actually ships.
Map<String, Set<int>> _declaredFaces() {
  final lines = File('pubspec.yaml').readAsLinesSync();
  final faces = <String, Set<int>>{};
  String? family;
  for (final line in lines) {
    final named = RegExp(r'^\s*-\s*family:\s*(\S+)').firstMatch(line);
    if (named != null) {
      family = named.group(1);
      faces[family!] = <int>{};
      continue;
    }
    final weight = RegExp(r'^\s*weight:\s*(\d+)').firstMatch(line);
    if (weight != null && family != null) {
      faces[family]!.add(int.parse(weight.group(1)!));
    }
  }
  return faces;
}

void main() {
  // Both themes are built from the same scale; the brightness only moves ink.
  const tokens = DashTokens.dark(bambuddyBrand);

  test('every weight the type scale asks for has a face to render in', () {
    final declared = _declaredFaces();

    final unrenderable = <String>[];
    for (final MapEntry(key: role, value: style) in _typeScale(
      tokens,
    ).entries) {
      final family = style.fontFamily;
      final weight = style.fontWeight;
      if (family == null || weight == null) continue;
      // A family the pubspec does not declare at all is the platform default,
      // which has every weight — not this test's business.
      final faces = declared[family];
      if (faces == null) continue;
      if (!faces.contains(weight.value)) {
        unrenderable.add('$role: $family w${weight.value} (have $faces)');
      }
    }

    expect(
      unrenderable,
      isEmpty,
      reason: 'Flutter silently draws the nearest weight instead',
    );
  });

  test('every face the app ships is one the type scale asks for', () {
    final declared = _declaredFaces();
    final asked = <String, Set<int>>{};
    for (final style in _typeScale(tokens).values) {
      final family = style.fontFamily;
      final weight = style.fontWeight;
      if (family == null || weight == null) continue;
      (asked[family] ??= <int>{}).add(weight.value);
    }
    // Set by hand outside the scale — the one gauge readout that picks a face
    // directly rather than through a role.
    asked[DashTokens.fontMono]!.add(600);

    final dead = <String>[];
    for (final MapEntry(key: family, value: faces) in declared.entries) {
      final used = asked[family];
      if (used == null) continue;
      for (final weight in faces) {
        if (!used.contains(weight)) dead.add('$family w$weight');
      }
    }

    // The mirror image of the first test, and how the dead JetBrains Mono
    // Medium was found: shipped in every APK, asked for by nothing.
    expect(
      dead,
      isEmpty,
      reason: 'a face nothing can render in is dead weight',
    );
  });
}
