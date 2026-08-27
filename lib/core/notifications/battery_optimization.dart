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
  /// The two "don't know" answers here are not the same answer, and the one
  /// fallback [PlatformQuery] takes cannot serve both — so the host check stays
  /// out here rather than folding into it.
  ///
  /// A host with no such setting (another platform, a test) is exempt: the only
  /// thing this drives is whether to offer the user a prompt, and there is no
  /// prompt to offer. An Android host that fails to answer is *not*: the setting
  /// exists there, and the two errors cost different things. Offering the prompt
  /// again costs a dialog the user can dismiss — the system screen shows the
  /// real state anyway. Skipping it leaves background monitoring to the OEM
  /// killer with nothing on screen to say why the printer alerts stopped.
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
