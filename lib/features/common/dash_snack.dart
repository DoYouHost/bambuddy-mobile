import 'package:flutter/material.dart';

/// One sentence to the user, in the app's snack bar.
///
/// Written on the messenger rather than on a context because that is how the
/// screens already reach it: a snack usually follows an `await`, by which time
/// the context may be gone, so the messenger is captured before the request
/// goes out and used afterwards.
///
/// This is for the ordinary "it worked" / "nothing to do here" sentence. A
/// failed request goes through `showApiFailure` instead — that one also records
/// that the user was told.
extension DashSnack on ScaffoldMessengerState {
  void snack(
    String message, {
    SnackBarAction? action,
    Duration? duration,

    /// Slides away whatever is on screen first.
    bool replaceCurrent = false,

    /// Drops the whole queue instead — for the printer controls, where a user
    /// can fire commands faster than a snack fades and would otherwise read
    /// answers to taps two actions old.
    bool clearQueue = false,

    /// Material keeps a snack with an action on screen until it is dismissed;
    /// false lets it fade anyway while the action stays tappable.
    bool? persist,
  }) {
    if (clearQueue) {
      clearSnackBars();
    } else if (replaceCurrent) {
      hideCurrentSnackBar();
    }
    showSnackBar(
      SnackBar(
        content: Text(message),
        action: action,
        duration: duration ?? const Duration(seconds: 4),
        persist: persist,
      ),
    );
  }
}
