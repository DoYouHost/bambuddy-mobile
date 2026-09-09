import 'package:bambuddy_mobile/data/streamed_download.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('transfer progress', () {
    test('a known length is a fraction', () {
      expect(transferFraction(50, 200), 0.25);
    });

    test('a server that sends no length reports -1, which is not progress', () {
      // Dio passes the -1 straight through. A bar wants null for it — an
      // indeterminate bar — not a negative fraction and not a full one.
      expect(transferFraction(50, -1), isNull);
      expect(transferFraction(0, 0), isNull);
    });

    test('the stepped form rounds down to what a bar can show', () {
      // The point of it is the rebuilds it saves, so it must never round up to
      // a value the transfer has not actually reached.
      expect(transferPercentStep(1, 3), 0.33);
      expect(transferPercentStep(1999, 2000), 0.99);
      expect(transferPercentStep(2000, 2000), 1.0);
    });

    test('the stepped form is null for an unknown length too', () {
      expect(transferPercentStep(50, -1), isNull);
    });
  });

  test('an upload has no send or receive deadline', () {
    // The ordinary timeouts describe a request that is stuck, not one that is
    // big; left in place they cancel a healthy upload on a slow uplink, which
    // reads to the user as the server refusing the file.
    final options = uploadOptions();

    expect(options.sendTimeout, Duration.zero);
    expect(options.receiveTimeout, Duration.zero);
  });
}
