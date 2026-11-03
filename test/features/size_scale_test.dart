import 'package:app_guards/app_guards.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'icon sizes, radii, font sizes and alphas in lib/ come from the scales',
    () {
      final offenders = rawSizes();
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    },
  );
}
