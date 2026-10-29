import 'package:app_guards/app_guards.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'icon sizes, radii, font sizes and alphas in lib/ come from the scales',
    () {
      // The watch has its own type scale (`wear_type_scale_test.dart`).
      final offenders = rawSizes(skip: {'lib/wear/'});
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    },
  );
}
