import 'package:flutter/services.dart';

/// One way to ask the platform something it may have nobody to answer.
///
/// The three method-channel wrappers in this app had three different policies
/// for the same question — what happens when the channel is not there — and the
/// difference was accidental rather than argued: the watch's text input caught
/// both channel failures, the watch's shape query caught both and fell back to
/// round, and the battery bridge caught neither and guarded on
/// `Platform.isAndroid` instead. All three mean the same thing by it: this host
/// does not implement the feature, so the caller gets the answer a device
/// without it would give.
class PlatformQuery {
  const PlatformQuery(this.channel);

  final MethodChannel channel;

  /// What [method] answers, or [fallback] when nobody answers — another
  /// platform, a test, a host build without the channel — or the host refuses.
  ///
  /// A refusal folds into the fallback on purpose: to a caller asking a yes/no
  /// question, "the platform said no" and "there is no platform to ask" are one
  /// outcome. A caller that has to tell them apart, because it owes the user a
  /// different screen for each, talks to [channel] itself — see
  /// `WearTextInput.request`.
  Future<T> ask<T>(
    String method, {
    required T fallback,
    Map<String, Object?>? arguments,
  }) async {
    try {
      return await channel.invokeMethod<T>(method, arguments) ?? fallback;
    } on MissingPluginException {
      return fallback;
    } on PlatformException {
      return fallback;
    }
  }

  /// Asks the platform to do something, where nothing comes back and a host that
  /// cannot do it simply does nothing.
  Future<void> tell(String method, {Map<String, Object?>? arguments}) async {
    try {
      await channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Nobody to tell, and nothing here to undo.
    } on PlatformException {
      // The host refused. Same again: there is no state on this side to roll
      // back, and every caller of this is a request the user can repeat.
    }
  }
}
