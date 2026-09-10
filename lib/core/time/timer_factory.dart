import 'dart:async';

/// How anything in the app that waits creates the wait — injectable so a test
/// drives the schedule instead of sitting out the window.
///
/// One signature under one name: it stood twice, the second time as
/// `RefreshTimerFactory`, so a caller had to know which of the two a
/// constructor meant before passing it the very same function.
typedef TimerFactory = Timer Function(Duration, void Function());
