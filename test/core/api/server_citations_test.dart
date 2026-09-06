import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Citations into the bambuddy server's source name a **symbol**, never a line.
///
/// A line number is right until the server's next commit and then silently
/// wrong: it still points somewhere, just not at the thing the sentence is
/// about. That is worse than no citation at all, because a reader who follows
/// it believes what they land on — and it is invisible here, since the server
/// is another repository that no build of this one checks.
///
/// `routes/users.py::update_user` survives any amount of drift, and `grep`
/// finds it in a second.
void main() {
  test('no comment cites the server by line number', () {
    // `.py`, `.ts` and `.tsx` are the server's; a Dart `file.dart:12` is one of
    // ours and means something else (a stack frame, an IDE link).
    final citation = RegExp(r'[\w/]+\.(?:py|ts|tsx):\d+');
    final offenders = <String>[];

    for (final directory in ['lib', 'test']) {
      final sources = Directory(directory)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      for (final source in sources) {
        final lines = source.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final match = citation.firstMatch(lines[i]);
          if (match != null) {
            offenders.add('${source.path}:${i + 1} — ${match.group(0)}');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Cite the symbol instead: `routes/users.py::update_user`.\n'
          '${offenders.join('\n')}',
    );
  });

  test('every cited symbol still exists in the server source', () {
    // Where the server's own checkout is: the maintainer's clone locally, the
    // one the CI workflow makes before the job starts. Absent on a fresh clone
    // that has neither, and then there is nothing to check against.
    final clone = [
      Directory('reference/bambuddy'),
      Directory('/tmp/bambuddy-server-ref'),
    ].firstWhere((d) => d.existsSync(), orElse: () => Directory('nowhere'));
    if (!clone.existsSync()) {
      printOnFailure('no server checkout — nothing to verify against');
      return;
    }

    final citation = RegExp(r'`([\w/]+\.(?:py|ts|tsx))::(\w+)`');
    // A def, a class, or a module-level constant — every shape a citation
    // points at. Deliberately loose: this asks "does this name exist here",
    // not "is this the right one for the sentence", which no test can answer.
    String declaration(String symbol) =>
        r'(?:^|\s)(?:async\s+)?(?:def|class|function|const|interface|type)\s+' +
        RegExp.escape(symbol) +
        r'\b|^' +
        RegExp.escape(symbol) +
        r'\s*[:=]';

    final missing = <String>[];
    final files = <String, File?>{};

    for (final directory in ['lib', 'test']) {
      for (final source
          in Directory(directory)
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        for (final match in citation.allMatches(source.readAsStringSync())) {
          final path = match.group(1)!;
          final symbol = match.group(2)!;

          final file = files.putIfAbsent(path, () {
            final candidates = clone
                .listSync(recursive: true)
                .whereType<File>()
                .where((f) => f.path.endsWith('/$path'))
                .toList();
            return candidates.length == 1 ? candidates.first : null;
          });
          if (file == null) {
            continue; // Ambiguous or gone: not this test's call.
          }

          final declared = RegExp(declaration(symbol), multiLine: true);
          if (!declared.hasMatch(file.readAsStringSync())) {
            missing.add('${source.path}: $path::$symbol');
          }
        }
      }
    }

    expect(
      missing,
      isEmpty,
      reason:
          'The server renamed or removed these. Follow what replaced them '
          'and update both the citation and the sentence around it — the '
          'behaviour it describes may have moved too.\n${missing.join('\n')}',
    );
  });
}
