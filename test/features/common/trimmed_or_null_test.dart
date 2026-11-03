import 'package:flutter_test/flutter_test.dart';
import 'package:bambuddy_mobile/features/common/trimmed_or_null.dart';

void main() {
  test('returns the value unchanged when it has no outer spaces', () {
    expect(trimmedOrNull('a'), 'a');
  });

  test('trims outer spaces', () {
    expect(trimmedOrNull('  a  '), 'a');
  });

  test('turns an empty string into null', () {
    expect(trimmedOrNull(''), isNull);
  });

  test('turns spaces only into null', () {
    expect(trimmedOrNull('   '), isNull);
  });

  test('turns tabs and newlines only into null', () {
    expect(trimmedOrNull('\t\n \r'), isNull);
  });

  test('trims tabs and newlines around a value', () {
    expect(trimmedOrNull('\ta b\n'), 'a b');
  });

  test('keeps spaces inside the value', () {
    expect(trimmedOrNull(' a  b '), 'a  b');
  });
}
