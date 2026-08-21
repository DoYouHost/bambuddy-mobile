import 'package:bambuddy_mobile/features/common/format_datetime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pads month, day, hour and minute to two digits', () {
    final d = DateTime(2026, 3, 7, 4, 5);

    expect(formatDate(d), '2026-03-07');
    expect(formatDateTime(d), '2026-03-07 04:05');
  });

  test('leaves two-digit parts alone and keeps midnight readable', () {
    expect(formatDateTime(DateTime(2026, 12, 31, 23, 59)), '2026-12-31 23:59');
    expect(formatDateTime(DateTime(2026, 12, 31)), '2026-12-31 00:00');
  });
}
