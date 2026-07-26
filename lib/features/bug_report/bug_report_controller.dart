import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/log_summary.dart';
import '../../providers.dart';

enum BugReportPhase { idle, recording, review }

/// Where the user is in the report flow. Recording deliberately outlives the
/// screen — the bug gets reproduced on the dashboard, not here — so this state
/// lives in a provider rather than in a widget.
class BugReportState {
  const BugReportState._(this.phase, {this.startedAt, this.log});

  const BugReportState.idle() : this._(BugReportPhase.idle);

  const BugReportState.recording(DateTime startedAt)
      : this._(BugReportPhase.recording, startedAt: startedAt);

  const BugReportState.review(String log)
      : this._(BugReportPhase.review, log: log);

  final BugReportPhase phase;
  final DateTime? startedAt;
  final String? log;

  bool get isRecording => phase == BugReportPhase.recording;
}

final bugReportProvider =
    NotifierProvider<BugReportController, BugReportState>(
  BugReportController.new,
);

class BugReportController extends Notifier<BugReportState> {
  @override
  BugReportState build() {
    // A session id left in prefs means the app died mid-recording. The buffer
    // went with it, so the flag has to go too — otherwise the background
    // isolate would keep writing to a session nobody is going to send. The
    // files stay on disk; offering to recover them is a later step.
    final settings = ref.read(settingsRepositoryProvider);
    if (settings.loadDiagnosticsSession() != null) {
      settings.saveDiagnosticsSession(null);
    }
    return const BugReportState.idle();
  }

  Future<void> start() async {
    if (state.isRecording) return;
    await ref.read(diagnosticRecorderProvider).start();
    state = BugReportState.recording(DateTime.now());
  }

  /// "It just happened." Recorded as a marker the reviewer can jump to.
  void mark() => ref.read(diagnosticRecorderProvider).mark();

  Future<void> stop() async {
    if (!state.isRecording) return;
    final log = await ref.read(diagnosticRecorderProvider).stop();
    state = BugReportState.review(log);
  }

  /// Backs out: the recording stops and the files go. A log the user decided
  /// not to send must not linger on disk.
  Future<void> discard() async {
    await ref.read(diagnosticRecorderProvider).discard();
    state = const BugReportState.idle();
  }

  LogSummary summarise() => LogSummary.parse(state.log ?? '');
}
