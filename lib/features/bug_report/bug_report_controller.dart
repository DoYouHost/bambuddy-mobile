import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/log_store.dart' show recordingLimit;
import '../../core/diagnostics/log_summary.dart';
import '../../core/diagnostics/report_sender.dart';
import '../../providers.dart';

enum BugReportPhase { idle, recording, review }

/// Where the finished log is going.
///
/// Two genuinely different things, not one flow with a switch: the file stays on
/// the phone and needs nothing from the user, while the issue is a public,
/// permanent post that is worthless without a sentence saying what went wrong.
enum ReportDestination { file, issue }

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
    this.destination = ReportDestination.file,
    this.send = const SendState.idle(),
  });

  const BugReportState.idle({RecoveredSession? recovered})
      : this._(BugReportPhase.idle, recovered: recovered);

  const BugReportState.recording(DateTime startedAt)
      : this._(BugReportPhase.recording, startedAt: startedAt);

  const BugReportState.review(String log, {String? autoStoppedBy})
      : this._(BugReportPhase.review, log: log, autoStoppedBy: autoStoppedBy);

  BugReportState copyWith({
    ReportDestination? destination,
    SendState? send,
  }) =>
      BugReportState._(
        phase,
        startedAt: startedAt,
        log: log,
        autoStoppedBy: autoStoppedBy,
        recovered: recovered,
        destination: destination ?? this.destination,
        send: send ?? this.send,
      );

  final BugReportPhase phase;
  final DateTime? startedAt;
  final String? log;

  /// Defaults to the file: it is the choice that keeps the log on the phone, and
  /// a default that publishes to a public repository is not one to make for
  /// somebody.
  final ReportDestination destination;

  /// Where the report is in the send flow. Only meaningful for
  /// [ReportDestination.issue].
  final SendState send;

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

  StreamSubscription<SendState>? _sends;

  @override
  BugReportState build() {
    ref.onDispose(() {
      _limit?.cancel();
      _sends?.cancel();
    });
    // Subscribed for the app's lifetime, not for the screen's: a report waits
    // out its delay whether or not anybody is looking, and the user who comes
    // back to this screen has to find it where they left it.
    final sender = ref.read(reportSenderProvider);
    _sends = sender.states.listen((send) => state = state.copyWith(send: send));
    // A report queued yesterday, or one whose delay outlived the app: this
    // controller is built once at startup — the recording bar wraps every
    // screen — so it is the one place that reliably runs early enough to send it.
    unawaited(sender.flush());
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

  /// Picks where the log is going.
  ///
  /// Choosing the issue is what fetches the challenge, and this is the earliest
  /// moment it can honestly be fetched: the relay charges for a challenge when it
  /// hands one out, so asking before the user has decided would make the *next*
  /// report wait twice as long every time somebody chose the file instead. From
  /// here the wait runs while they write the description, which is the whole
  /// point of paying for it early.
  void chooseDestination(ReportDestination destination) {
    if (state.destination == destination) return;
    state = state.copyWith(destination: destination);
    if (destination == ReportDestination.issue) {
      // Deliberately not awaited: the field has to be typable immediately, and a
      // ticket that never arrives is handled at send time.
      unawaited(ref.read(reportSenderProvider).prepare());
    }
  }

  /// Hands the report to the sender. It goes to disk first, so from here it
  /// survives the screen closing, the app being backgrounded and the app dying.
  Future<void> sendToIssue(String description) async {
    final log = state.log;
    if (log == null || log.isEmpty) return;
    await ref
        .read(reportSenderProvider)
        .submit(description: description, log: log);
  }

  /// Backs out: the recording stops and the files go. A log the user decided
  /// not to send must not linger on disk.
  Future<void> discard() async {
    _limit?.cancel();
    _limit = null;
    // The outbox holds its own copy of the log, with its own timer. Deleting the
    // recording without cancelling that would publish the very log the user just
    // said to throw away — minutes later, from a screen they had already left.
    //
    // A send already in flight is the one case this cannot take back: the relay
    // may have it. The window is one HTTP call wide, and the alternative — not
    // cancelling — leaves the whole wait as the window.
    // Not awaited: the part that stops the send runs synchronously inside, and
    // waiting for the file to be deleted would let a slow disk make "discard"
    // look like a hang.
    unawaited(ref.read(reportSenderProvider).cancel());
    await ref.read(diagnosticRecorderProvider).discard();
    state = const BugReportState.idle();
  }

  LogSummary summarise() => LogSummary.parse(state.log ?? '');
}
