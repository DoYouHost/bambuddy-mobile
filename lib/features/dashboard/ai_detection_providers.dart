import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/ai_detection.dart';
import '../../providers.dart';
import 'providers.dart';

/// The web's refetch interval for the same badge (`PrintersPage.tsx`).
const aiDetectionPollInterval = Duration(seconds: 10);

/// What the server's AI failure detection says about the running prints, or
/// null while there is nothing to show: no answer yet, a server without the
/// routes, a session it refuses.
///
/// Watched by the print panels only, so it exists while something prints and
/// asks nothing of an idle farm. Detection that is switched off is asked about
/// once, and again on regained contact and pull-to-refresh; switched on, it is
/// polled like the web polls it, while the dashboard is watched.
final aiDetectionProvider =
    NotifierProvider.autoDispose<AiDetectionNotifier, AiDetectionStatus?>(
      AiDetectionNotifier.new,
    );

class AiDetectionNotifier extends Notifier<AiDetectionStatus?> {
  Timer? _timer;
  int _generation = 0;

  @override
  AiDetectionStatus? build() {
    ref.watch(serverProfileProvider);
    ref.watch(aiDetectionRepositoryProvider);
    final generation = ++_generation;

    ref.listen(serverContactEpochProvider, (_, _) => _poll(generation));
    ref.listen(dashboardWatchedProvider, (_, watched) {
      _arm(generation);
      // Back on screen: catch up now rather than ten seconds from now.
      if (watched) _poll(generation);
    });
    ref.onDispose(() => _timer?.cancel());
    if (ref.read(dashboardWatchedProvider)) {
      Future.microtask(() => _poll(generation));
    }
    return null;
  }

  Future<void> refresh() => _poll(_generation);

  /// The timer runs only while detection is on and the dashboard is watched.
  void _arm(int generation) {
    final wanted =
        (state?.enabled ?? false) && ref.read(dashboardWatchedProvider);
    if (!wanted) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(
        aiDetectionPollInterval,
        (_) => _poll(generation),
      );
    }
  }

  Future<void> _poll(int generation) async {
    // The microtask scheduled by build can outlive an autoDispose provider.
    if (!ref.mounted || generation != _generation) return;
    final AiDetectionStatus? status;
    try {
      status = await ref.read(aiDetectionRepositoryProvider).fetch();
    } on AppApiException {
      // Keep the last answer: the dashboard's own poll reports a lost server,
      // and an expired session sends the user to setup from there.
      return;
    }
    if (!ref.mounted || generation != _generation) return;
    state = status;
    _arm(generation);
  }
}

/// The entry for one printer's card, or null when there is none to show
/// ([AiDetectionStatus.detectionFor]).
final aiDetectionForProvider = Provider.autoDispose.family<AiDetection?, int>(
  (ref, printerId) => ref.watch(aiDetectionProvider)?.detectionFor(printerId),
);
