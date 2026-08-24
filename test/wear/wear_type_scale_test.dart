import 'dart:io';

import 'package:bambuddy_mobile/wear/wear_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keeps the watch type scale in one place.
///
/// The same heading used to be 13, 14 and 15 on three screens and the same fine
/// print 9 in one place and 10 in another, because every site picked its own
/// number and no two sites were ever edited on the same day. Nothing about that
/// looks wrong in a review — each literal is plausible where it sits — so the
/// only thing that keeps it from happening again is a check that no literal
/// exists at all.
///
/// Source-scanning rather than runtime: the drift is a fact about the code, and
/// there is no widget both a `Text` style and a `ButtonStyle.textStyle` pass
/// through.
void main() {
  const tokens = 'lib/wear/wear_theme.dart';
  final fontSize = RegExp(r'fontSize:');

  late Map<String, String> sources;

  setUpAll(() {
    sources = {
      for (final file in Directory('lib/wear')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        file.path: file.readAsStringSync(),
    };
  });

  test('the sweep found the watch sources', () {
    // A scan that stopped finding files would make the assertion below vacuous.
    expect(sources, hasLength(greaterThan(8)));
    expect(sources[tokens], isNotNull);
    expect(fontSize.allMatches(sources[tokens]!), isNotEmpty);
  });

  test('no screen names a font size of its own', () {
    final offenders = [
      for (final entry in sources.entries)
        if (entry.key != tokens && fontSize.hasMatch(entry.value)) entry.key,
    ];

    expect(
      offenders,
      isEmpty,
      reason: 'Pick a role from WearText (or add one there) instead of a '
          'literal: a size chosen at the call site drifts from every other '
          'screen showing the same kind of text.',
    );
  });

  test('the snackbar keeps a text colour', () {
    // Overriding `contentTextStyle` replaces the Material default outright, so
    // dropping the colour leaves the text inheriting the ambient white — on a
    // snackbar whose M3 fill is `inverseSurface`, i.e. light. The toast then
    // renders invisibly, which no widget test would notice.
    expect(wearTheme().snackBarTheme.contentTextStyle?.color, isNotNull);
  });

  test('a role carries its own weight, so a call site only picks a colour', () {
    expect(WearText.strong.fontWeight, FontWeight.w600);
    expect(WearText.title.fontWeight, FontWeight.bold);
    expect(WearText.fine.color, wearMuted);
  });
}
