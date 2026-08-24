import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One way to run a watch action that touches storage or the network.
///
/// The mechanics only — where the failure is *shown* stays with the screen,
/// because that differs on purpose: a printer command the user can simply repeat
/// is a toast, while a step that blocks getting any further has to leave text on
/// screen that does not time out.
///
/// Every line below is a bug this app has actually shipped or nearly shipped:
///
/// - no [busy] gate → a double tap started two concurrent writes of the same
///   secrets;
/// - no `mounted` check after the await → `ref` on a disposed widget throws, and
///   swipe-to-dismiss on Wear OS is a sideways swipe, so leaving mid-write is an
///   easy accident rather than a corner case;
/// - no `finally` → a failure that threw outright left the spinner up forever,
///   with no way back on a screen that has no other exit.
mixin WearAction<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool _busy = false;

  /// Whether an action is in flight. Screens use it to swap in a spinner or to
  /// take their buttons away.
  bool get busy => _busy;

  /// Runs [action] with the guards above. [onDone] fires on success, [onError]
  /// on failure — both only while this widget is still alive. Omitting [onError]
  /// swallows the failure, which is only honest where the button coming back is
  /// itself the message.
  Future<void> run(
    Future<void> Function() action, {
    void Function(Object error)? onError,
    VoidCallback? onDone,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) onDone?.call();
    } catch (error) {
      if (mounted) onError?.call(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
