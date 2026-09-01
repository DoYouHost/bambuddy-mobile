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
  final colour = RegExp(r'Color\(0x');

  /// The two files whose job *is* to name a colour: the tokens, and the table
  /// that gives every printer state one.
  const palettes = {tokens, 'lib/wear/wear_status.dart'};

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
    // A scan that stopped finding files would make the assertions below vacuous.
    expect(sources, hasLength(greaterThan(8)));
    expect(sources[tokens], isNotNull);
    expect(fontSize.allMatches(sources[tokens]!), isNotEmpty);
    expect(colour.allMatches(sources[tokens]!), isNotEmpty);
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

  test('no screen mixes a colour of its own', () {
    final offenders = [
      for (final entry in sources.entries)
        if (!palettes.contains(entry.key) && colour.hasMatch(entry.value))
          entry.key,
    ];

    expect(
      offenders,
      isEmpty,
      reason: 'Name it in wear_theme.dart. Four greys had already drifted '
          'apart there — 0xFF1C1C1E and 0xFF2A2A2C with nothing saying which '
          'was for what — and the status chip and the fault card turned out to '
          'be the same tinted box written twice, at 0.15/0.6 and 0.2/0.5 '
          'alpha. Each literal looks plausible where it sits, which is exactly '
          'why the check has to be that none exists.',
    );
  });

  test('no watch screen reaches for a snackbar', () {
    final snackbar = RegExp(r'showSnackBar|SnackBar\(');
    final offenders = [
      for (final entry in sources.entries)
        if (snackbar.hasMatch(entry.value)) entry.key,
    ];

    expect(
      offenders,
      isEmpty,
      reason: 'A snackbar is laid out against the square the display reports, '
          'and a watch is the circle inscribed in it: pinned to the bottom of '
          'that square it lands where the circle has almost no width left, so '
          'most of the bar and most of its sentence are off the glass. Say it '
          'with wearToast, which is given the middle of the face.',
    );
  });

  test('a role carries its own weight, so a call site only picks a colour', () {
    expect(WearText.strong.fontWeight, FontWeight.w600);
    expect(WearText.title.fontWeight, FontWeight.bold);
    expect(WearText.fine.color, wearMuted);
  });
}
