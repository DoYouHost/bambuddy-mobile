import 'dart:async';

import 'package:flutter/material.dart';

import 'wear_toast.dart';

/// The frame every watch screen sits in.
///
/// One line each in four screens, which is exactly why it is written once: the
/// next thing the watch needs around all of them — and there will be one — goes
/// here instead of into four files that have to be found first.
///
/// The [SafeArea] is a guard rather than a working part. Wear OS reports no
/// insets today: a round display is not one, which is why the layout insets
/// itself (`lib/wear/wear_geometry.dart`), and there is no status bar to dodge.
/// It stays because it costs nothing and the day a watch does report an inset —
/// a flat tyre, a squircle with a chin — this is where it would arrive.
///
/// It also owns the transient-message layer, which is the thing that "and there
/// will be one" turned out to be. [wearToast] hands its message to the nearest
/// frame above the caller, so a message cannot outlive the screen that raised
/// it: swipe away mid-command — the usual way off a Wear OS screen — and the
/// message goes with the screen, where an entry pushed onto the navigator's own
/// overlay would have stayed behind on top of whatever came next.
class WearScreen extends StatefulWidget {
  const WearScreen({super.key, required this.child});

  final Widget child;

  @override
  State<WearScreen> createState() => _WearScreenState();
}

class _WearScreenState extends State<WearScreen> {
  ({String message, WearToastTone tone})? _message;
  Timer? _clock;

  /// One slot, so a second message replaces the first instead of queueing
  /// behind it. Every button on a watch screen acts on the same printer, and a
  /// queue would still be playing back the first tap while the user is on their
  /// third — with the answer to the tap they are watching three seconds away.
  void _show(String message, WearToastTone tone) {
    _clock?.cancel();
    setState(() => _message = (message: message, tone: tone));
    _clock = Timer(wearToastDuration, _dismiss);
  }

  void _dismiss() {
    _clock?.cancel();
    _clock = null;
    if (mounted) setState(() => _message = null);
  }

  @override
  void dispose() {
    // The screen can go before the message does: three seconds is long enough
    // to swipe out of, and a live timer past the last frame is a leak the
    // widget tests fail on as loudly as a device would not.
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: WearToastScope(
            show: _show,
            // Expands so the screen under the message is laid out exactly as it
            // was before there was a layer above it: a Stack sizes itself to its
            // children otherwise, and every watch screen expects to be handed
            // the whole face.
            child: Stack(
              fit: StackFit.expand,
              children: [
                widget.child,
                if (_message case final message?)
                  WearToast(
                    message: message.message,
                    tone: message.tone,
                    onDismiss: _dismiss,
                  ),
              ],
            ),
          ),
        ),
      );
}
