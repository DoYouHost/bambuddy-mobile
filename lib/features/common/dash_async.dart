import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import 'dash_progress.dart';
import 'state_views.dart';

/// A capability the app has to ask the server for, read as a plain flag:
/// **unresolved is off.**
///
/// A name rather than a spelling, because `!= false` says the opposite and
/// looks just as reasonable at the call site. Every one of these gates a
/// control, so loading, an error and a refusal all have to read the same way —
/// otherwise a control flashes into a screen and out again, or leads to a route
/// the server does not have.
///
/// A gate that would rather show its control while the answer loads belongs on
/// the other side of the question, in `ObservedCapability.whenUnknown`.
extension AsyncFlag on AsyncValue<bool> {
  bool get orFalse => valueOrNull ?? false;
}

/// Nothing has answered yet — no reply from the server, and no failure either.
///
/// The third state [AsyncFlag.orFalse] folds away. A failure is deliberately
/// **not** it: that is a settled "no", or a control would sit disabled for the
/// rest of the session saying nothing about why.
extension AsyncUnanswered<T> on AsyncValue<T> {
  bool get isUnanswered => !hasValue && !hasError;
}

/// What a control should do about the answers it depends on.
enum ControlOffer {
  /// One of them settled on "no". The control does not belong on this screen.
  hidden,

  /// On screen but not pressable: nothing has said "no", and something has not
  /// answered yet. A button the user is waiting to press reads better greyed
  /// out for a moment than absent and then suddenly there — which is what
  /// [AsyncFlag.orFalse] gives, and why it is the wrong reader here.
  pending,

  /// Every answer is in and every one of them is yes.
  offered,
}

/// Folds the answers a control is gated on into what it should do about them.
///
/// Callbacks rather than values, and read **in order, only as far as needed**:
/// the first answer that is not already "yes" decides, and nothing after it is
/// read at all. A list of values would evaluate every `ref.watch` in it before
/// this function ever ran, which is how a control the server has already ruled
/// out ends up subscribing to — and firing — the request behind the next
/// answer. Order them cheapest-first: a session-wide flag before anything that
/// costs a round trip of its own.
///
/// A settled "no" hides the control; an answer still on its way disables it.
/// Only for a widget that **watches** its answers — a control that cannot
/// rebuild would sit greyed for as long as it is on screen.
ControlOffer controlOffer(Iterable<AsyncValue<bool> Function()> answers) {
  for (final read in answers) {
    final answer = read();
    if (answer.orFalse) continue;
    return answer.isUnanswered ? ControlOffer.pending : ControlOffer.hidden;
  }
  return ControlOffer.offered;
}

/// A screen's three states, with the two every screen words identically already
/// written: the spinner while the data is on its way, and "could not load it,
/// try again" when the server said no.
///
/// Only the data branch is left to the caller, because that is the only one a
/// screen has an opinion about. A screen that needs different words for a
/// failure — the photo view, which explains that *this print* has no picture —
/// still writes its own `when`.
///
/// Both skip flags are on by default: a list that is already on screen should
/// not blink back to a spinner because it is being refreshed underneath. Pass
/// false where the wait is worth showing.
Widget dashAsync<T>(
  BuildContext context,
  AsyncValue<T> value, {
  required Widget Function(T value) data,
  required VoidCallback onRetry,
  Widget loading = const DashLoading(),

  /// What to say when the failure did not come from the server and so has no
  /// wording of its own. Features that can name the thing that failed
  /// ("statistics could not be loaded") beat the generic connection line.
  String? fallbackMessage,
  IconData? errorIcon = Icons.cloud_off,
  bool tonalRetry = false,
  bool scrollableError = false,
  bool skipLoadingOnReload = true,
  bool skipLoadingOnRefresh = true,
}) {
  final l10n = AppLocalizations.of(context);
  return value.when(
    skipLoadingOnReload: skipLoadingOnReload,
    skipLoadingOnRefresh: skipLoadingOnRefresh,
    loading: () => loading,
    error: (error, _) => AsyncErrorView(
      message: error is AppApiException
          ? error.localized(l10n)
          : fallbackMessage ?? l10n.connectFailed,
      retryLabel: l10n.retry,
      onRetry: onRetry,
      icon: errorIcon,
      tonal: tonalRetry,
      scrollable: scrollableError,
    ),
    data: data,
  );
}

/// The same three states for a section inside a screen rather than the whole
/// of it: a spinner in a strip, and one sentence in the same strip when it
/// fails.
///
/// One [padding] for both states on purpose — a section that pads its spinner
/// differently from its failure line makes the page jump as the answer
/// arrives. [height] gives the waiting and failed states the height the
/// content will have, so a chart's slot does not collapse and spring back
/// (the history sheets); the data branch keeps sizing itself.
///
/// [failureBuilder] is for a section that already has its own way of saying
/// "nothing here" and wants the failure to look the same.
Widget dashAsyncStrip<T>(
  BuildContext context,
  AsyncValue<T> value, {
  required Widget Function(T value) data,
  EdgeInsets padding = const EdgeInsets.all(16),
  double? height,

  /// The waiting widget, for a strip too small for the full spinner.
  Widget loading = const DashLoading(),
  String? failureMessage,
  Widget Function(String message)? failureBuilder,
  bool skipLoadingOnReload = true,
  bool skipLoadingOnRefresh = true,
}) {
  final l10n = AppLocalizations.of(context);
  Widget strip(Widget child) {
    final padded = Padding(
      padding: padding,
      child: Center(child: child),
    );
    return height == null ? padded : SizedBox(height: height, child: padded);
  }

  return value.when(
    skipLoadingOnReload: skipLoadingOnReload,
    skipLoadingOnRefresh: skipLoadingOnRefresh,
    loading: () => strip(loading),
    error: (error, _) {
      final message = error is AppApiException
          ? error.localized(l10n)
          : failureMessage ?? l10n.connectFailed;
      return failureBuilder?.call(message) ??
          strip(
            Text(
              message,
              textAlign: TextAlign.center,
              style: DashTokens.of(context).labelSoft,
            ),
          );
    },
    data: data,
  );
}
