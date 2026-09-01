import 'package:bambuddy_mobile/core/notifications/background_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every fact survives the trip to the other isolate', () {
    for (final what in BackgroundSync.values) {
      expect(BackgroundSync.parse(what.message), what);
    }
  });

  test('the wire keys are the ones that shipped', () {
    // The port carries a bare map, so these strings are the entire contract
    // between the app and the service — renaming the enum must not rename them.
    expect(BackgroundSync.parse(const {'diagnostics': 'sync'}),
        BackgroundSync.diagnostics);
    expect(BackgroundSync.parse(const {'clock': 'sync'}), BackgroundSync.clock);
  });

  test('anything else on the port is not a sync', () {
    // The same port carries whatever a future caller sends; a message this
    // isolate does not know has to fall through, not throw.
    expect(BackgroundSync.parse(const {'clock': 'later'}), isNull);
    expect(BackgroundSync.parse(const {'something': 'sync'}), isNull);
    expect(BackgroundSync.parse(const <String, String>{}), isNull);
    expect(BackgroundSync.parse('sync'), isNull);
  });
}
