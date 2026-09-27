import 'package:bambuddy_mobile/core/format/stable_digest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The published FNV-1a 32-bit vectors: the same numbers on every VM start,
  // which is the whole reason this is not `String.hashCode`.
  test('matches the FNV-1a reference values', () {
    expect(stableDigest(''), 0x811c9dc5);
    expect(stableDigest('a'), 0xe40c292c);
    expect(stableDigest('foobar'), 0xbf9cf968);
  });
}
