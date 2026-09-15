import 'dart:async';

/// How anything in the app that waits creates the wait — injectable so a test
/// drives the schedule instead of sitting out the window.
typedef TimerFactory = Timer Function(Duration, void Function());
