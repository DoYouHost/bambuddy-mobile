import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Cienki most na platform channel z [MainActivity] (Kotlin) do stanu/prośby
/// o zwolnienie z optymalizacji baterii. To zwolnienie odblokowuje na
/// Androidzie 12+ start foreground service z tła i ratuje proces przed OEM-owym
/// zabójcą — bez niego monitorowanie w tle bywa krótkotrwałe.
class BatteryOptimization {
  static const MethodChannel _channel =
      MethodChannel('page.codeberg.morganmlgman.bambuddy/battery');

  /// Czy apka jest już zwolniona z optymalizacji. Poza Androidem (testy/desktop)
  /// zwraca `true`, żeby nie pokazywać prośby tam, gdzie nie ma sensu.
  Future<bool> isIgnoring() async {
    if (!Platform.isAndroid) return true;
    final value =
        await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
    return value ?? false;
  }

  /// Otwiera systemowy ekran prośby o zwolnienie z optymalizacji baterii.
  Future<void> request() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('requestIgnoreBatteryOptimizations');
  }
}
