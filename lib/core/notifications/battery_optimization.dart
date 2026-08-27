import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../platform/platform_query.dart';

/// Bridge to the platform channel with [MainActivity] (Kotlin) for checking
/// and requesting battery optimization exemption. This exemption unlocks
/// foreground service startup from the background on Android 12+ and protects
/// the process from OEM task killers — without it, background monitoring may be short-lived.
class BatteryOptimization {
  static const _platform = PlatformQuery(
    MethodChannel('page.codeberg.morganmlgman.bambuddy/battery'),
  );

  /// Whether the app is already exempt from battery optimization.
  ///
  /// True where there is nothing to ask — another platform, a test — because
  /// the only thing this answer drives is whether to offer the user a prompt,
  /// and a host with no such setting has no prompt to offer.
  Future<bool> isIgnoring() async {
    // A capability guard, not an error policy — the failure handling lives in
    // [PlatformQuery]. Asking at all is Android-only: elsewhere the answer is
    // fixed, and the round trip would be an extra turn of the event loop that
    // callers awaiting this on a test host do not expect.
    if (!Platform.isAndroid) return true;
    return _platform.ask('isIgnoringBatteryOptimizations', fallback: true);
  }

  /// Opens the system request dialog for battery optimization exemption.
  Future<void> request() async {
    if (!Platform.isAndroid) return;
    await _platform.tell('requestIgnoreBatteryOptimizations');
  }
}
