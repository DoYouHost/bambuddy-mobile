import 'package:app_guards/app_guards.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no translation leaves a one-letter word at a line end', () {
    final offenders = unGluedShortWords();
    expect(
      offenders,
      isEmpty,
      reason: 'run `just l10n-glue` to fix:\n${offenders.join('\n')}',
    );
  });
}
