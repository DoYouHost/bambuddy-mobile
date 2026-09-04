import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../wear_theme.dart';
import 'wear_face.dart';

/// How long a message stays up before it takes itself away.
///
/// Longer than the two seconds the snackbar it replaces had. That number came
/// from a phone, where a toast is read out of the corner of an eye while the
/// screen behind it carries on; here the message *is* the screen, and the one
/// that matters most is a failure — a sentence rather than a word. A tap takes
/// it away for anyone who has already read it.
const wearToastDuration = Duration(seconds: 3);

/// What a message is saying. Decides the icon and the accent and nothing else:
/// both tones get the same seconds and the same layout, because what made the
/// old snackbar unreadable was its geometry, not its colour.
enum WearToastTone {
  /// A command that went through, which on a watch has to be said out loud: the
  /// phone's answer — letting the screen update — is too small to notice here.
  success,

  /// One that did not, in the theme's error colour: the same one the setup
  /// screen's error line wears.
  failure,
}

/// Put [message] over the watch screen [context] is in, for
/// [wearToastDuration].
///
/// Needs a `WearScreen` above it — that is where the layer lives. Its absence is
/// a wiring mistake rather than a runtime condition, hence an assert and not a
/// silent drop of something the user was meant to read.
void wearToast(
  BuildContext context,
  String message, {
  required WearToastTone tone,
}) {
  final host = WearToastScope.maybeOf(context);
  assert(host != null, 'wearToast needs a WearScreen above it');
  host?.show(message, tone);
}

/// How [wearToast] reaches the screen frame that owns the message layer.
///
/// Read outside of `build` (from a button's callback), so it is looked up
/// without registering a dependency: the caller does not rebuild when the
/// message changes, only the frame does.
class WearToastScope extends InheritedWidget {
  const WearToastScope({super.key, required this.show, required super.child});

  final void Function(String message, WearToastTone tone) show;

  static WearToastScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<WearToastScope>();

  @override
  bool updateShouldNotify(WearToastScope oldWidget) => show != oldWidget.show;
}

/// A transient message in the Wear OS idiom: the face goes black, an icon and a
/// short line sit in the middle of it, and it is gone by itself.
///
/// This exists instead of a [SnackBar] because a snackbar is laid out against
/// the square the display reports, and a watch is a circle drawn inside that
/// square. Pinned to the bottom of the square, a floating bar lands exactly
/// where the circle has almost no width left: on a 450 px face the reported
/// failure — "Telefon nie odpowiedział" — was legible for about a third of its
/// length, with the rest of the bar off the glass. [ScaffoldMessenger] has no
/// hook to fix that from; nothing about a snackbar's geometry is ours to move.
///
/// The middle of the face is the widest the circle ever gets, so that is where
/// the message goes, inside the same inscribed rectangle every other watch
/// screen uses ([wearFaceInsets]). Black rather than the snackbar's light fill:
/// on an OLED face a white slab reads as a rendering fault, and unlit pixels
/// are what the flavour exists for.
class WearToast extends StatelessWidget {
  const WearToast({
    super.key,
    required this.message,
    required this.tone,
    required this.onDismiss,
  });

  final String message;
  final WearToastTone tone;

  /// Called when the user taps rather than waits. The whole face is the target
  /// — a message covering the screen has no business asking anyone to hit a
  /// 20 dp word on a wrist.
  final VoidCallback onDismiss;

  /// The most lines the message may take. Four and the icon and the dismiss hint
  /// together come to ~120 dp, which the shortest round-safe band — a 192 dp
  /// face — has at 123; it is a ceiling rather than a promise, see [_lines].
  static const _maxLines = 4;

  /// How many lines actually fit in [available] dp at this watch's font scale.
  ///
  /// A fixed four overflows the moment someone turns the system font up: the
  /// band the circle allows does not grow with the text, so at scale 1.3 four
  /// lines want ~78 dp of the ~62 that are there, and Flutter answers an
  /// overflow with the striped bar rather than with an ellipsis. Fewer lines and
  /// an ellipsis is the right answer to a face that has run out of room.
  static int _lines(BuildContext context, double available) {
    final line =
        MediaQuery.textScalerOf(context).scale(WearText.body.fontSize!) *
            _lineHeight;
    return (available / line).floor().clamp(1, _maxLines);
  }

  /// Looser than the default, because this is a paragraph rather than a label.
  static const _lineHeight = 1.25;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final success = tone == WearToastTone.success;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onDismiss,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 120),
        builder: (context, t, child) => Opacity(opacity: t, child: child),
        child: ColoredBox(
          color: Colors.black,
          child: WearFace(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  success
                      ? Icons.check_circle_outline_rounded
                      : Icons.error_outline_rounded,
                  size: 26,
                  color: success ? scheme.primary : scheme.error,
                ),
                const SizedBox(height: 8),
                // Flexible plus a line count measured against what is left:
                // the message gives way to the icon and the hint rather than
                // pushing them off the glass.
                Flexible(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Text(
                      message,
                      textAlign: TextAlign.center,
                      maxLines: _lines(context, constraints.maxHeight),
                      overflow: TextOverflow.ellipsis,
                      style: WearText.body.copyWith(height: _lineHeight),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Not a button: the tap target is the face behind it. It is here
                // so that waiting out the three seconds looks like a choice.
                Text(
                  l10n.wearOk,
                  style: WearText.small.copyWith(color: wearMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
