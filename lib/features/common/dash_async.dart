import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/api/server_reachability.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';

/// A capability the app has to ask the server for, read as a plain flag:
/// **unresolved is off.** A name rather than a spelling, since `!= false` says the
/// opposite; loading, an error and a refusal must all read the same (docs/ui-primitives.md, "Async
/// state"). A gate that would rather show its control while loading belongs in
/// `ObservedCapability.whenUnknown`.
extension AsyncFlag on AsyncValue<bool> {
  bool get orFalse => valueOrNull ?? false;

  /// [orFalse] for a control that would rather be disabled than missing while
  /// the server has not answered. See [ControlOffer].
  ControlOffer get offer => orFalse
      ? ControlOffer.offered
      : isUnanswered
      ? ControlOffer.pending
      : ControlOffer.hidden;
}

/// Nothing has answered yet — no reply from the server, and no failure either.
///
/// The third state [AsyncFlag.orFalse] folds away. A failure is deliberately
/// **not** it: that is a settled "no", or a control would sit disabled for the
/// rest of the session saying nothing about why.
extension AsyncUnanswered<T> on AsyncValue<T> {
  bool get isUnanswered => !hasValue && !hasError;
}

/// What a control should do about an answer it is gated on.
enum ControlOffer {
  /// The answer settled on "no". The control does not belong on this screen.
  hidden,

  /// On screen but not pressable, because nothing has answered yet: better greyed out
  /// for a moment than absent and then suddenly there. Only for a widget that
  /// **watches** the answer, and only while there is nothing to say; a control left
  /// disabled for good owes the user a line saying why (docs/ui-primitives.md, "Async state").
  pending,

  /// The answer is in, and it is yes.
  offered,
}

/// A screen's three states, with the two every screen words identically already
/// written: the spinner, and "could not load it, try again". Only the data branch is
/// left to the caller. Both skip flags are on by default, so a list already on screen
/// does not blink back to a spinner while it is refreshed (docs/ui-primitives.md, "Async state").
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
  AsyncErrorView failure(String message) => AsyncErrorView(
    message: message,
    retryLabel: l10n.retry,
    // Forgetting first, so the try itself shows its spinner: the shared answer
    // is still "unreachable" until this request comes back, and without this
    // the button would look dead for as long as it takes.
    onRetry: () {
      ServerReachability.instance.forget();
      onRetry();
    },
    icon: errorIcon,
    tonal: tonalRetry,
    scrollable: scrollableError,
  );

  return _WhenServerReturns(
    value: value,
    onServerBack: onRetry,
    builder: (context, reachable) {
      // Nothing to show yet and the server is known to be out of reach: say so
      // now. Waiting means this screen spends its own connect timeout learning
      // what the request that already failed answered for all of them — which
      // is a spinner per screen the user opens, and the same wait each time.
      if (!value.hasValue && !value.hasError && reachable == false) {
        return failure(fallbackMessage ?? l10n.connectFailed);
      }
      return value.when(
        skipLoadingOnReload: skipLoadingOnReload,
        skipLoadingOnRefresh: skipLoadingOnRefresh,
        loading: () => loading,
        error: (error, _) => failure(
          error is AppApiException
              ? error.localized(l10n)
              : fallbackMessage ?? l10n.connectFailed,
        ),
        data: data,
      );
    },
  );
}

/// The same three states for a section inside a screen. One [padding] for both
/// states, so the page does not jump as the answer arrives; [height] keeps a chart's
/// slot from collapsing and springing back (docs/ui-primitives.md, "Async state").
Widget dashAsyncStrip<T>(
  BuildContext context,
  AsyncValue<T> value, {
  required Widget Function(T value) data,
  EdgeInsets padding = const EdgeInsets.all(DashSpace.lg),
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

  Widget failed(String message) =>
      failureBuilder?.call(message) ??
      strip(
        Text(
          message,
          textAlign: TextAlign.center,
          style: DashTokens.of(context).labelSoft,
        ),
      );

  return ValueListenableBuilder<bool?>(
    valueListenable: ServerReachability.instance.reachable,
    builder: (context, reachable, _) {
      // Same rule as [dashAsync]: a section has no more reason to wait out its
      // own timeout than a screen does.
      if (!value.hasValue && !value.hasError && reachable == false) {
        return failed(failureMessage ?? l10n.connectFailed);
      }
      return value.when(
        skipLoadingOnReload: skipLoadingOnReload,
        skipLoadingOnRefresh: skipLoadingOnRefresh,
        loading: () => strip(loading),
        error: (error, _) => failed(
          error is AppApiException
              ? error.localized(l10n)
              : failureMessage ?? l10n.connectFailed,
        ),
        data: data,
      );
    },
  );
}

/// Where a row that was optimistically removed belongs in the list **as it is now**,
/// read off the rows that were around it, never off the index it used to sit at: with
/// two removals in flight an index puts two failed rows back swapped. [before] is the
/// list as it stood when the row was still in it (docs/ui-primitives.md, "Optimistic removal").
int restoredPositionOf<T>(
  List<T> now,
  T row,
  List<T> before, {
  required Object Function(T) idOf,
}) {
  final id = idOf(row);
  final above = {
    for (final r in before.takeWhile((r) => idOf(r) != id)) idOf(r),
  };
  final lastAbove = now.lastIndexWhere((r) => above.contains(idOf(r)));
  if (lastAbove >= 0) return lastAbove + 1;
  final known = {for (final r in before) idOf(r)};
  final firstBelow = now.indexWhere((r) => known.contains(idOf(r)));
  return firstBelow >= 0 ? firstBelow : 0;
}

/// Put a row that was optimistically removed back into the list **as it is now**, never
/// into the snapshot it was removed from; only the row that failed goes back. Its place
/// comes from [restoredPositionOf]. Returns [now] itself when something has already
/// restored the row (docs/ui-primitives.md, "Optimistic removal").
List<T> withRowRestored<T>(
  List<T> now,
  T row,
  List<T> before, {
  required Object Function(T) idOf,
}) {
  final id = idOf(row);
  if (now.any((r) => idOf(r) == id)) return now;
  return [...now]
    ..insert(restoredPositionOf(now, row, before, idOf: idOf), row);
}

/// Rebuilds on [ServerReachability], and asks its screen to fetch again the moment the
/// server comes back. Only a connection failure is retried: a 500 or a refusal is the
/// server's answer (docs/ui-primitives.md, "Refetching when the server returns").
class _WhenServerReturns extends StatefulWidget {
  const _WhenServerReturns({
    required this.value,
    required this.onServerBack,
    required this.builder,
  });

  final AsyncValue<Object?> value;
  final VoidCallback onServerBack;
  final Widget Function(BuildContext context, bool? reachable) builder;

  @override
  State<_WhenServerReturns> createState() => _WhenServerReturnsState();
}

class _WhenServerReturnsState extends State<_WhenServerReturns> {
  ValueNotifier<bool?> get _reachable => ServerReachability.instance.reachable;
  late bool? _last = _reachable.value;

  @override
  void initState() {
    super.initState();
    _reachable.addListener(_heard);
    // Opened after the server came back, holding a failure collected while it
    // was away: the same case as [_heard], one screen later.
    if (_last == true && _waitingOnTheServer) _askAfterTheFrame();
  }

  @override
  void didUpdateWidget(_WhenServerReturns old) {
    super.didUpdateWidget(old);
    // The failure of a request that was still in the air when the server came
    // back lands here, after the flip this state listens for. Without this the
    // screen would keep an error the server has already disproved.
    if (_last == true && !old.value.hasError && _waitingOnTheServer) {
      _askAfterTheFrame();
    }
  }

  @override
  void dispose() {
    _reachable.removeListener(_heard);
    super.dispose();
  }

  void _heard() {
    final next = _reachable.value;
    final regained = _last == false && next == true;
    _last = next;
    if (mounted) setState(() {});
    if (!regained || !_waitingOnTheServer) return;
    _askAfterTheFrame();
  }

  /// After the frame: the fetch this starts writes to a provider, which a
  /// build must not be in the middle of.
  void _askAfterTheFrame() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) widget.onServerBack();
  });

  /// Whether this screen is holding a failure the server has since disproved. A request
  /// still in the air is not one: a second alongside it races for which answer the
  /// provider keeps (docs/ui-primitives.md, "Refetching when the server returns").
  bool get _waitingOnTheServer {
    final value = widget.value;
    if (value.hasValue) return false;
    final error = value.error;
    return error is AppApiException &&
        error.code == AppErrorCode.serverUnreachable;
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _last);
}

/// Work in progress said in one line: a small spinner and what is happening.
class BusyLine extends StatelessWidget {
  const BusyLine(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const DashSpinner(size: 16),
      const SizedBox(width: DashSpace.sm),
      Expanded(child: Text(label, style: DashTokens.of(context).bodySoft)),
    ],
  );
}
