import 'package:flutter/services.dart';

/// Raised when the watch has no input activity to hand a request to. The caller
/// should fall back to an editable field: a tap that does nothing at all is the
/// bug this whole path exists to fix.
class WearTextInputUnavailable implements Exception {
  const WearTextInputUnavailable();

  @override
  String toString() => 'WearTextInputUnavailable';
}

/// Text entry on Wear OS, handed to the watch's own input activity (keyboard,
/// handwriting, dictation) through [MainActivity]'s `wear_input` channel.
///
/// A plain `TextField` is not an option there: on the watch the soft keyboard
/// either never opens (Pixel Watch 3) or opens as a fullscreen window that the
/// app is never told about, leaving the field hidden underneath it. Details in
/// the Kotlin doc for `requestWearText`.
class WearTextInput {
  static const MethodChannel _channel =
      MethodChannel('page.codeberg.morganmlgman.bambuddy/wear_input');

  /// Whether this device is a watch, i.e. whether text has to go through the
  /// input activity. False on phones, and on anything without the channel.
  Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens the input activity titled [label] and resolves to what was entered.
  ///
  /// Null means "keep the current value": the user backed out, confirmed an
  /// empty screen, or a request was already open. Throws
  /// [WearTextInputUnavailable] when there is no input activity to open.
  Future<String?> request({required String label}) async {
    try {
      return await _channel
          .invokeMethod<String>('requestText', {'label': label});
    } on MissingPluginException {
      throw const WearTextInputUnavailable();
    } on PlatformException catch (error) {
      if (error.code == 'unavailable') throw const WearTextInputUnavailable();
      // 'busy' — a second tap while the input screen is still up.
      return null;
    }
  }
}
