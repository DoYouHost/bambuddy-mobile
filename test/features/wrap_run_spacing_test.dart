import 'package:app_guards/app_guards.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every Wrap that sets spacing also sets runSpacing', () {
    expect(
      wrapsWithoutRunSpacing(),
      isEmpty,
      reason:
          'These wrap onto a second line with no gap between the rows. Add '
          'runSpacing (usually the same value as spacing).',
    );
  });
}
