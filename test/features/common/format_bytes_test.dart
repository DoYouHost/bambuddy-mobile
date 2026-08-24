import 'package:bambuddy_mobile/features/common/format_bytes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bytes stay bytes below one kilobyte', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1023), '1023 B');
  });

  test('keeps one decimal below 100 in the unit, then drops it', () {
    expect(formatBytes(1024), '1.0 KB');
    expect(formatBytes(1024 * 1024 * 12 + 300000), '12.3 MB');
    // Three digits are precise enough on their own — the fraction is noise.
    expect(formatBytes(853811), '834 KB');
    expect(formatBytes(1024 * 1024 * 512), '512 MB');
  });

  test('climbs to the largest unit it has', () {
    expect(formatBytes(1024 * 1024 * 1024), '1.0 GB');
    expect(formatBytes(1024 * 1024 * 1024 * 1024 * 3), '3.0 TB');
  });
}
