import 'dart:async';

/// "How did this print come out?" waiting for the app shell to ask it (#1898).
///
/// Posted from two places — the server's `print_confirm_request` frame while
/// the app is on screen, and a tap on the outcome notification — so the sheet
/// is opened by exactly one owner. Same two entrances as `HmsStopRequest`: a
/// tap while the app runs arrives on [outcomePrompts], one that launched the
/// app waits in [takeOutcomePrompt] for the first frame.
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
