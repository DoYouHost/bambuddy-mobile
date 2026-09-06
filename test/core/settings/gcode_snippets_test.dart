import 'package:bambuddy_mobile/core/settings/gcode_snippets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('setting z serwera: modele z niepustym snippetem', () {
    final models = gcodeSnippetModels(
      '{"A1 mini":{"start_gcode":"G4 S1","end_gcode":""},'
      '"X1C":{"start_gcode":"","end_gcode":";plate-swap"}}',
    );
    expect(models, {
      'A1 mini',
      'X1C',
    }, reason: 'wystarczy jeden z dwóch snippetów');
  });

  test('model z pustymi snippetami się nie liczy', () {
    // The web deletes such an entry, but a hand-written setting can leave it —
    // offering injection for it would promise an empty injection.
    expect(
      gcodeSnippetModels('{"P1S":{"start_gcode":"","end_gcode":"   "}}'),
      isEmpty,
    );
  });

  test('brak ustawienia = brak snippetów', () {
    expect(gcodeSnippetModels(null), isEmpty);
    expect(gcodeSnippetModels(''), isEmpty);
    expect(gcodeSnippetModels('   '), isEmpty);
    expect(gcodeSnippetModels('{}'), isEmpty);
  });

  test('nieczytelne ustawienie nie wywraca ekranu druku', () {
    expect(gcodeSnippetModels('{nie-json'), isEmpty);
    expect(gcodeSnippetModels('[1,2,3]'), isEmpty);
    expect(gcodeSnippetModels(42), isEmpty);
    expect(
      gcodeSnippetModels('{"X1C":"G4 S1"}'),
      isEmpty,
      reason: 'wpis musi być obiektem ze start_gcode/end_gcode',
    );
  });

  test('serwer oddający obiekt zamiast stringa też jest rozumiany', () {
    expect(
      gcodeSnippetModels(<String, dynamic>{
        'A1 mini': {'start_gcode': 'G4 S1', 'end_gcode': null},
      }),
      {'A1 mini'},
    );
  });

  test('klucz to model dokładnie tak, jak go podaje drukarka', () {
    // Server matches `printer.model` verbatim — no case folding, no trimming,
    // so "a1 mini" is a different model than "A1 mini" and must not match.
    expect(gcodeSnippetModels('{"a1 mini":{"start_gcode":"G28"}}'), {
      'a1 mini',
    });
  });
}
