import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Bridge to the platform channel with [MainActivity] (Kotlin) for checking
/// and requesting battery optimization exemption. This exemption unlocks
/// foreground service startup from the background on Android 12+ and protects
/// the process from OEM task killers — without it, background monitoring may be short-lived.
class BatteryOptimization {
  static const MethodChannel _channel =
      MethodChannel('page.codeberg.morganmlgman.bambuddy/battery');

  /// Checks if the app is already exempt from battery optimization.
  /// On non-Android platforms (tests/desktop), returns `true` to avoid
  /// showing a request where it makes no sense.
  Future<bool> isIgnoring() async {
    if (!Platform.isAndroid) return true;
    final value =
        await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
    return value ?? false;
  }

  /// Opens the system request dialog for battery optimization exemption.
  Future<void> request() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('requestIgnoreBatteryOptimizations');
  }
}
