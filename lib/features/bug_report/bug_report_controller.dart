import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/log_store.dart' show recordingLimit;
import '../../core/diagnostics/log_summary.dart';
import '../../providers.dart';

enum BugReportPhase { idle, recording, review }

/// Where the user is in the report flow. Recording deliberately outlives the
/// screen — the bug gets reproduced on the dashboard, not here — so this state
/// lives in a provider rather than in a widget.
class BugReportState {
  const BugReportState._(
    this.phase, {
    this.startedAt,
    this.log,
    this.autoStoppedBy,
    this.recovered,
  });

  const BugReportState.idle({RecoveredSession? recovered})
      : this._(BugReportPhase.idle, recovered: recovered);

  const BugReportState.recording(DateTime startedAt)
      : this._(BugReportPhase.recording, startedAt: startedAt);

  const BugReportState.review(String log, {String? autoStoppedBy})
      : this._(BugReportPhase.review, log: log, autoStoppedBy: autoStoppedBy);

  final BugReportPhase phase;
  final DateTime? startedAt;
  final String? log;

  /// Which ceiling ended the recording — `time`, `size`, or null when the user
  /// pressed finish. They are somewhere else in the app when a ceiling hits, so
  /// something has to say so, and the two ceilings need different sentences.
  final String? autoStoppedBy;

  bool get autoStopped => autoStoppedBy != null;

  /// A log left on disk by an app that died mid-recording, waiting for the user
  /// to look at it or throw it away. Offered here rather than pushed at startup:
  /// somebody whose app just crashed is coming to this screen anyway, and
  /// nobody else should be interrupted by it.
  final RecoveredSession? recovered;

  bool get isRecording => phase == BugReportPhase.recording;
}

/// What survived a crash: the id, so the files can still be deleted, and the
/// log itself, already read off disk.
class RecoveredSession {
  const RecoveredSession({required this.session, required this.log});

  final String session;
  final String log;
}

final bugReportProvider =
    NotifierProvider<BugReportController, BugReportState>(
  BugReportController.new,
);

class BugReportController extends Notifier<BugReportState> {
  /// Ends the session at [recordingLimit]. The store refuses records past that
  /// point on its own, so this timer is about the app agreeing with it: the bar
  /// goes away and the log is handed over for review instead of the user
  /// walking around with a recording that no longer records.
  Timer? _limit;

  @override
  BugReportState build() {
    ref.onDispose(() => _limit?.cancel());
    // A session id left in prefs means the app died mid-recording. The flag has
    // to go either way — the background isolate reads it and would keep writing
    // into a session nobody owns — but the files it points at are the whole
    // reason the mirror on disk exists.
    final settings = ref.read(settingsRepositoryProvider);
    final orphan = settings.loadDiagnosticsSession();
    if (orphan != null) {
      settings.saveDiagnosticsSession(null);
      // Reading files is async and `build` is not; the card appears a frame or
      // two after the screen, which is nobody's critical path.
      Future.microtask(() => _findRecovered(orphan));
    }
    return const BugReportState.idle();
  }

  Future<void> _findRecovered(String session) async {
    final log = await ref.read(diagnosticRecorderProvider).recover(session);
    // Nothing salvageable, or the user already started a new recording in the
    // meantime — either way there is nothing to offer.
    if (log.isEmpty || state.phase != BugReportPhase.idle) return;
    state = BugReportState.idle(
      recovered: RecoveredSession(session: session, log: log),
    );
  }

  /// Opens the salvaged log for review, exactly as if it had just been
  /// recorded — including [discard], which deletes the same files.
  void showRecovered() {
    final recovered = state.recovered;
    if (recovered == null) return;
    state = BugReportState.review(recovered.log);
  }

  /// Throws the salvaged log away without opening it.
  Future<void> dropRecovered() async {
    final recovered = state.recovered;
    if (recovered == null) return;
    await ref
        .read(diagnosticRecorderProvider)
        .discardSession(recovered.session);
    state = const BugReportState.idle();
  }

  Future<void> start() async {
    if (state.isRecording) return;
    // The store closes itself on either ceiling; this is how the app finds out.
    // The size one has no timer to fall back on — nothing here can predict when
    // a runaway stream fills twenty megabytes — so without this the bar would
    // keep counting down over a recording that stopped recording.
    await ref
        .read(diagnosticRecorderProvider)
        .start(onLimitReached: (limit) => stop(limit: limit));
    _limit?.cancel();
    _limit = Timer(recordingLimit, () => stop(limit: 'time'));
    state = BugReportState.recording(DateTime.now());
  }

  /// "It just happened." Recorded as a marker the reviewer can jump to.
  void mark() => ref.read(diagnosticRecorderProvider).mark();

  /// [limit] names the ceiling that ended it, or null when the user pressed
  /// finish.
  Future<void> stop({String? limit}) async {
    if (!state.isRecording) return;
    _limit?.cancel();
    _limit = null;
    final log = await ref.read(diagnosticRecorderProvider).stop();
    state = BugReportState.review(log, autoStoppedBy: limit);
  }

  /// Backs out: the recording stops and the files go. A log the user decided
  /// not to send must not linger on disk.
  Future<void> discard() async {
    _limit?.cancel();
    _limit = null;
    await ref.read(diagnosticRecorderProvider).discard();
    state = const BugReportState.idle();
  }

  LogSummary summarise() => LogSummary.parse(state.log ?? '');
}
