import 'dart:io' show Platform;

import 'package:app_util/app_util.dart';
import 'package:flutter/services.dart';

/// Battery-optimization exemption, over the channel to `MainActivity`. It is
/// what unlocks starting a foreground service from the background on Android
/// 12+ and what OEM task killers respect.
class BatteryOptimization {
  static const _platform = PlatformQuery(
    MethodChannel('page.codeberg.morganmlgman.bambuddy/battery'),
  );

  /// Whether the app is already exempt. The two "don't know" answers differ, so
  /// the host check stays out of [PlatformQuery]'s single fallback: a host with
  /// no such setting is exempt (there is no prompt to offer), while an Android
  /// host that fails to answer is not — a dismissable dialog costs less than
  /// background monitoring left to the OEM killer with nothing on screen.
  Future<bool> isIgnoring() async {
    if (!Platform.isAndroid) return true;
    return _platform.ask('isIgnoringBatteryOptimizations', fallback: false);
  }

  /// Opens the system request dialog for battery optimization exemption.
  Future<void> request() async {
    if (!Platform.isAndroid) return;
    await _platform.tell('requestIgnoreBatteryOptimizations');
  }
}
