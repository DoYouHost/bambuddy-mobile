import 'dart:async';

/// "How did this print come out?" waiting for the app shell to ask it (#1898).
///
/// Posted from two places — the server's `print_confirm_request` frame while
/// the app is on screen, and a tap on the outcome notification — and opened in
/// one, the app shell, which listens to [outcomePrompts] from its first
/// `initState`. The slot behind [takeOutcomePrompt] is the same shape as
/// `HmsStopRequest`'s, for a prompt posted before anything listens; the shell
/// empties it whenever it handles one from the stream, so a later read of the
/// slot cannot hand the same prompt out again.
final StreamController<int> _controller = StreamController<int>.broadcast();

/// Archive ids, one per prompt.
Stream<int> get outcomePrompts => _controller.stream;

int? _pending;

void postOutcomePrompt(int archiveId) {
  _pending = archiveId;
  _controller.add(archiveId);
}

/// Clears what it returns, so one tap cannot open the sheet twice.
int? takeOutcomePrompt() {
  final archiveId = _pending;
  _pending = null;
  return archiveId;
}
