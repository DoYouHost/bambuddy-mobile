import 'package:app_util/app_util.dart';
import 'package:flutter/services.dart';

/// Raised when the watch has no input activity to hand a request to. The caller
/// falls back to an editable field — a tap that does nothing is the bug this
/// path exists to fix.
class WearTextInputUnavailable implements Exception {
  const WearTextInputUnavailable();

  @override
  String toString() => 'WearTextInputUnavailable';
}

/// Text entry on Wear OS, handed to the watch's own input activity (keyboard,
/// handwriting, dictation) through `MainActivity`'s `wear_input` channel: a
/// plain `TextField` either never opens a keyboard (Pixel Watch 3) or is hidden
/// under a fullscreen window the app is never told about. Details in the Kotlin
/// doc for `requestWearText`.
class WearTextInput {
  static const MethodChannel _channel = MethodChannel(
    'page.codeberg.morganmlgman.bambuddy/wear_input',
  );

  static const _platform = PlatformQuery(_channel);

  /// Whether text has to go through the input activity. False on phones, and on
  /// anything without the channel.
  Future<bool> isSupported() => _platform.ask('isSupported', fallback: false);

  /// Opens the input activity titled [label] and resolves to what was entered.
  ///
  /// Null means "keep the current value": backed out, confirmed empty, or a
  /// request was already open.
  ///
  /// Talks to the channel itself rather than through [PlatformQuery] because
  /// "nobody to ask" is not a fallback value here but a different screen — hence
  /// [WearTextInputUnavailable] rather than a null.
  Future<String?> request({required String label}) async {
    try {
      return await _channel.invokeMethod<String>('requestText', {
        'label': label,
      });
    } on MissingPluginException {
      throw const WearTextInputUnavailable();
    } on PlatformException catch (error) {
      if (error.code == 'unavailable') throw const WearTextInputUnavailable();
      // 'busy' — a second tap while the input screen is still up.
      return null;
    }
  }
}
