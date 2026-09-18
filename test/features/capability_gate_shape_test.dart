import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Server capability gates take one shape: a latch in the repository, a
/// `capabilityGate(...)` over it, and a screen reading it with `orFalse` or
/// `offer` (docs/server-gates.md, "From latch to screen").
///
/// The two shapes it replaced are what these catch. A `FutureProvider<bool>`
/// reports a loading frame for an answer it already has, so its control
/// appears a frame late on every screen; and nothing asks it again once the
/// server is reachable. A `maybeWhen(data: (v) => v, ...)` read is `orFalse`
/// that also blinks to `false` on every reload.
///
/// Source-scanning, like `wrap_run_spacing_test`: the defect is a fact about
/// the code, and the next gate is the one to catch.
void main() {
  Iterable<(String, String)> sources() sync* {
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      yield (file.path, file.readAsStringSync());
    }
  }

  String at(String path, String source, int offset) =>
      '$path:${'\n'.allMatches(source.substring(0, offset)).length + 1}';

  test('no capability gate is a FutureProvider<bool>', () {
    // Not a server capability: the OS notification permission.
    const allowed = {'_notificationsBlockedProvider'};
    final gate = RegExp(
      r'final\s+(\w+)\s*=\s*FutureProvider(\s*\.\s*autoDispose)?'
      r'(\s*\.\s*family)?\s*<\s*bool\s*[,>]',
    );
    final offenders = [
      for (final (path, source) in sources())
        for (final match in gate.allMatches(source))
          if (!allowed.contains(match.group(1)))
            '${at(path, source, match.start)} ${match.group(1)}',
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'Put the latch in the repository and write the gate as '
          'capabilityGate(...) — see docs/server-gates.md.',
    );
  });

  test('every FutureProvider names its type', () {
    // Otherwise `FutureProvider((ref) async => true)` is a bool gate the check
    // above cannot see.
    final untyped = RegExp(
      r'FutureProvider(\s*\.\s*(autoDispose|family))*\s*\(',
    );
    final offenders = [
      for (final (path, source) in sources())
        for (final match in untyped.allMatches(source))
          at(path, source, match.start),
    ];

    expect(offenders, isEmpty, reason: 'Write FutureProvider<T>(...).');
  });

  test('no gate is read with an identity data: branch', () {
    // In any argument order, with or without a trailing comma, in `when` as
    // well as `maybeWhen`: `data: (v) => v` is `orFalse` that blinks.
    final read = RegExp(r'\bdata:\s*\(\s*(\w+)\s*\)\s*=>\s*\1\s*[,)]');
    final offenders = [
      for (final (path, source) in sources())
        for (final match in read.allMatches(source))
          at(path, source, match.start),
    ];

    expect(
      offenders,
      isEmpty,
      reason: 'Read the gate with .orFalse, or .offer for a button.',
    );
  });
}
