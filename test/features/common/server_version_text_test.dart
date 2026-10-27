import 'package:bambuddy_mobile/core/app_context.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers.dart';

void main() {
  test('a version the server gave is printed as it came', () {
    expect(serverVersionText(en, const AsyncData('1.2.6b1')), 'Server 1.2.6b1');
  });

  test('while the read is in flight the label keeps its place', () {
    // Not "unknown": that would be a wrong answer for as long as the request
    // is out, and the line would then change twice.
    expect(serverVersionText(en, const AsyncLoading()), 'Server …');
  });

  group('a version already known survives the next read', () {
    // Riverpod carries the previous value into both states, and the version
    // cannot go stale while it is on screen: a server that changed version has
    // restarted, which drops the connection under us anyway.
    test('a refresh keeps it rather than blanking to an ellipsis', () {
      final refreshing = reportedOver(
        const AsyncLoading<String?>(),
        const AsyncData<String?>('1.2.6'),
      );

      expect(serverVersionText(en, refreshing), 'Server 1.2.6');
    });

    test('a failed refresh keeps it rather than forgetting it', () {
      final failed = reportedOver(
        AsyncError<String?>(Exception('unreachable'), StackTrace.empty),
        const AsyncData<String?>('1.2.6'),
      );

      expect(serverVersionText(en, failed), 'Server 1.2.6');
    });
  });

  test('every way of not knowing lands on the same sentence', () {
    // An older bambuddy with no /updates/version route answers null; a read
    // that threw arrives as an error; a blank is a server that sent the field
    // with nothing in it, which would otherwise print as "Server " with the
    // answer missing off the end.
    for (final unknown in <AsyncValue<String?>>[
      const AsyncData(null),
      const AsyncData(''),
      const AsyncData('   '),
      AsyncError(Exception('unreachable'), StackTrace.empty),
    ]) {
      expect(
        serverVersionText(en, unknown),
        'Server version unknown',
        reason: '$unknown',
      );
    }
  });
}
