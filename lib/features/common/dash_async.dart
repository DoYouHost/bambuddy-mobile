import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import 'dash_progress.dart';
import 'state_views.dart';

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
          : l10n.connectFailed,
      retryLabel: l10n.retry,
      onRetry: onRetry,
      icon: errorIcon,
      tonal: tonalRetry,
      scrollable: scrollableError,
    ),
    data: data,
  );
}
