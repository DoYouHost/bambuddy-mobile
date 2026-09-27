import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One way to run a watch action that touches storage or the network — the
/// mechanics only. Where a failure is *shown* stays with the screen: a command
/// the user can repeat is a toast, a step that blocks getting any further has to
/// leave text on screen.
///
/// Each guard below is a bug this app shipped or nearly shipped, and
/// swipe-to-dismiss on Wear OS being a sideways swipe is what makes leaving
/// mid-write an accident rather than a corner case.
mixin WearAction<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool _busy = false;

  /// Whether an action is in flight — a spinner, or buttons taken away.
  bool get busy => _busy;

  /// [onDone] fires on success, [onError] on failure — both only while this
  /// widget is still alive. Omitting [onError] swallows the failure, which is
  /// honest only where the button coming back is itself the message.
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
