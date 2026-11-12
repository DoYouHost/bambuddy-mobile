import 'package:bambuddy_mobile/core/format/fixed_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('trimFixedZeros', () {
    test('drops zeros after the point and the point itself', () {
      expect(trimFixedZeros('2.00'), '2');
      expect(trimFixedZeros('0.0'), '0');
      expect(trimFixedZeros('100.0'), '100');
      expect(trimFixedZeros('10.000'), '10');
    });

    test('keeps the decimals that are not zero', () {
      expect(trimFixedZeros('1.50'), '1.5');
      expect(trimFixedZeros('0.10'), '0.1');
      expect(trimFixedZeros('10.123'), '10.123');
    });

    test('keeps the sign', () {
      expect(trimFixedZeros('-0.50'), '-0.5');
      expect(trimFixedZeros('-0.00'), '-0');
    });

    test('leaves a string with no point alone, so integer zeros survive', () {
      expect(trimFixedZeros('10'), '10');
      expect(trimFixedZeros('100'), '100');
      expect(trimFixedZeros('1e+30'), '1e+30');
    });

    test('empty input stays empty', () {
      expect(trimFixedZeros(''), '');
    });
  });
}
