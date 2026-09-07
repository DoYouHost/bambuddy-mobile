import 'package:bambuddy_mobile/core/settings/gcode_snippets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('server setting: models with a non-empty snippet', () {
    final models = gcodeSnippetModels(
      '{"A1 mini":{"start_gcode":"G4 S1","end_gcode":""},'
      '"X1C":{"start_gcode":"","end_gcode":";plate-swap"}}',
    );
    expect(models, {
      'A1 mini',
      'X1C',
    }, reason: 'either of the two snippets is enough');
  });

  test('a model with empty snippets does not count', () {
    // The web deletes such an entry, but a hand-written setting can leave it —
    // offering injection for it would promise an empty injection.
    expect(
      gcodeSnippetModels('{"P1S":{"start_gcode":"","end_gcode":"   "}}'),
      isEmpty,
    );
  });

  test('no setting = no snippets', () {
    expect(gcodeSnippetModels(null), isEmpty);
    expect(gcodeSnippetModels(''), isEmpty);
    expect(gcodeSnippetModels('   '), isEmpty);
    expect(gcodeSnippetModels('{}'), isEmpty);
  });

  test('an unreadable setting does not crash the print screen', () {
    expect(gcodeSnippetModels('{not-json'), isEmpty);
    expect(gcodeSnippetModels('[1,2,3]'), isEmpty);
    expect(gcodeSnippetModels(42), isEmpty);
    expect(
      gcodeSnippetModels('{"X1C":"G4 S1"}'),
      isEmpty,
      reason: 'an entry must be an object with start_gcode/end_gcode',
    );
  });

  test(
    'a server handing back an object instead of a string is also understood',
    () {
      expect(
        gcodeSnippetModels(<String, dynamic>{
          'A1 mini': {'start_gcode': 'G4 S1', 'end_gcode': null},
        }),
        {'A1 mini'},
      );
    },
  );

  test('the key is the model exactly as the printer gives it', () {
    // Server matches `printer.model` verbatim — no case folding, no trimming,
    // so "a1 mini" is a different model than "A1 mini" and must not match.
    expect(gcodeSnippetModels('{"a1 mini":{"start_gcode":"G28"}}'), {
      'a1 mini',
    });
  });
}
