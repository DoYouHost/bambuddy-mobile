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
      reason: 'Cite the symbol instead: `routes/users.py::update_user`.\n'
          '${offenders.join('\n')}',
    );
  });
}
