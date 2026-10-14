import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps the foreground service's manifest declaration and its Dart start call
/// saying the same thing.
///
/// The two halves live in different languages and different directories, and
/// Android only compares them at the moment the service starts: a type passed
/// to `startForeground` that the manifest does not declare throws, in the
/// background, on a device, minutes after the app was last touched. Nothing in
/// `flutter analyze`, a widget test or a debug build looks at the pair.
///
/// The permissions are here for the same reason. `connectedDevice` is not
/// granted by declaring its own `FOREGROUND_SERVICE_*` permission alone — the
/// app also has to hold one of the permissions that qualify it for that type,
/// and a missing one fails the same way: at start, on a device.
void main() {
  const manifestPath = 'android/app/src/main/AndroidManifest.xml';
  const wearManifestPath = 'android/app/src/wear/AndroidManifest.xml';
  const monitorPath = 'lib/core/notifications/background_monitor.dart';

  /// The service the plugin owns. Scoping the type lookup to it keeps this test
  /// from breaking the day the app declares a second, unrelated service.
  const pluginService =
      'com.pravera.flutter_foreground_task.service.ForegroundService';

  /// Manifest-declarable permissions that qualify an app for `connectedDevice`.
  /// The Bluetooth and UWB ones are runtime permissions and are deliberately
  /// not here: this app reaches its printers over the network.
  const connectedDeviceQualifiers = {
    'CHANGE_NETWORK_STATE',
    'CHANGE_WIFI_STATE',
    'CHANGE_WIFI_MULTICAST_STATE',
    'NFC',
    'TRANSMIT_IR',
  };

  late String manifest;
  late String wearManifest;
  late String monitor;

  setUpAll(() {
    manifest = File(manifestPath).readAsStringSync();
    wearManifest = File(wearManifestPath).readAsStringSync();
    monitor = File(monitorPath).readAsStringSync();
  });

  /// `android.permission.FOO` entries, as bare names.
  ///
  /// Reads the whole tag before looking inside it: XML puts no order on
  /// attributes, and a regex that expects `android:name` first stops matching
  /// the day something moves `tools:node` in front of it — silently, by
  /// reporting no permissions rather than by failing.
  Set<String> permissionsIn(String source, {required bool removed}) {
    final tags = RegExp(r'<uses-permission\b[^>]*>').allMatches(source);
    final name = RegExp(r'android:name="android\.permission\.(\w+)"');
    return {
      for (final tag in tags)
        if (name.firstMatch(tag.group(0)!) case final match?)
          if (tag.group(0)!.contains('tools:node="remove"') == removed)
            match.group(1)!,
    };
  }

  /// The `foregroundServiceType` on the plugin's own service, and nothing else.
  String declaredServiceType(String source) {
    final tag = RegExp(r'<service\b[^>]*>')
        .allMatches(source)
        .map((m) => m.group(0)!)
        .firstWhere((t) => t.contains(pluginService));
    return RegExp(
      r'android:foregroundServiceType="(\w+)"',
    ).firstMatch(tag)!.group(1)!;
  }

  test('the manifest and the start call name the same service type', () {
    final started = RegExp(
      r'ForegroundServiceTypes\.(\w+)',
    ).allMatches(monitor).map((m) => m.group(1)!).toSet();

    // A scan that found nothing would make the comparison vacuous.
    expect(started, isNotEmpty, reason: 'no service type in $monitorPath');
    expect(started, equals({declaredServiceType(manifest)}));
  });

  test('the service type carries its own permission', () {
    final type = declaredServiceType(manifest);
    // connectedDevice -> FOREGROUND_SERVICE_CONNECTED_DEVICE.
    final screamed = type
        .replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m.group(0)}')
        .toUpperCase();

    expect(
      permissionsIn(manifest, removed: false),
      contains('FOREGROUND_SERVICE_$screamed'),
    );
  });

  test('connectedDevice is qualified by a permission the app holds', () {
    final granted = permissionsIn(manifest, removed: false);
    expect(granted, contains('FOREGROUND_SERVICE_CONNECTED_DEVICE'));
    expect(
      granted.intersection(connectedDeviceQualifiers),
      isNotEmpty,
      reason: 'connectedDevice needs one of $connectedDeviceQualifiers',
    );
  });

  test('the watch keeps what its own service needs', () {
    // The watch's Ongoing Activity (Play's WO-V4) runs in WearOngoingService,
    // which WearOngoing.kt starts as connectedDevice. The wear manifest strips
    // phone permissions one by one, so stripping one of these would fail the
    // same way the phone's pair does: at start, on a wrist.
    final stripped = permissionsIn(wearManifest, removed: true);
    final service = RegExp(
      r'<service\b[^>]*WearOngoingService[^>]*>',
    ).firstMatch(wearManifest)?.group(0);
    final kotlin = File(
      'android/app/src/wear/kotlin/page/codeberg/morganmlgman/'
      'bambuddy_mobile/WearOngoing.kt',
    ).readAsStringSync();

    expect(
      service,
      contains('android:foregroundServiceType="connectedDevice"'),
    );
    expect(kotlin, contains('FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE'));
    expect(
      stripped.intersection({
        'FOREGROUND_SERVICE',
        'FOREGROUND_SERVICE_CONNECTED_DEVICE',
        'POST_NOTIFICATIONS',
      }),
      isEmpty,
    );
    expect(
      permissionsIn(
        manifest,
        removed: false,
      ).intersection(connectedDeviceQualifiers).difference(stripped),
      isNotEmpty,
      reason: 'connectedDevice needs one of $connectedDeviceQualifiers',
    );
  });

  test('every service configuration turns the wake lock off by name', () {
    // The lock the plugin takes has no timeout and lives as long as the service,
    // which is as long as the app is backgrounded. Android vitals counts that
    // against a 2 h daily budget and it put this app over the 5% bar; the socket
    // does not need it (see lib/main.dart).
    //
    // Asserting the absence of `true` is not enough on its own: the plugin's
    // constructor defaults `allowWakeLock` to `true`, so deleting the argument
    // re-arms the lock while reading like a tidy-up. Every construction has to
    // say `false` out loud.
    final construction = RegExp(r'ForegroundTaskOptions\(');
    final disabled = RegExp(r'allowWakeLock:\s*false');
    final enabled = RegExp(r'allowWakeLock:\s*true');

    var total = 0;
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      final count = construction.allMatches(source).length;
      total += count;

      expect(
        enabled.hasMatch(source),
        isFalse,
        reason: '${file.path} re-arms the service wake lock',
      );
      expect(
        disabled.allMatches(source).length,
        count,
        reason:
            '${file.path} builds ForegroundTaskOptions without saying '
            'allowWakeLock: false, which the plugin reads as true',
      );
    }

    expect(total, greaterThan(0), reason: 'the sweep found no configuration');
  });
}
