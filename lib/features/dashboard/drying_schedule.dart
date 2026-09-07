import 'package:clock/clock.dart';

/// When a drying run the user is setting up should begin.
enum DryStartMode { now, delay, atTime }

/// Delay presets, in minutes — the same ladder the web offers.
const dryingDelayPresets = [30, 60, 120, 240, 480, 720, 1440];

/// Why there is nothing to send yet.
enum DryingStartProblem {
  /// "At time" with no instant picked. Falling back to starting the dryer
  /// immediately is the one thing the user did not ask for, so this is a
  /// prompt rather than a default.
  noTimePicked,

  /// An instant that has already passed. The server refuses it as a bare 400
  /// (`start_after must be in the future`), so catching it here keeps the
  /// wording ours and costs no request. Reachable even with the date picker
  /// bounded at today: the *time* half can still be earlier this morning.
  timeInPast,
}

/// The instant to schedule for, or the reason there is none.
///
/// Both null means start now — the mode the sheet opens on.
typedef DryingStart = ({DateTime? startAfter, DryingStartProblem? problem});

/// What the sheet's start-time picker adds up to at the moment the button is
/// pressed.
///
/// A delay is measured from *now*, not from when the chip was tapped: the user
/// who picks "after 2 h" and then reconsiders the temperature means two hours
/// from pressing the button.
DryingStart dryingStart({
  required DryStartMode mode,
  required int delayMinutes,
  DateTime? at,
}) {
  final now = clock.now();
  return switch (mode) {
    DryStartMode.now => (startAfter: null, problem: null),
    DryStartMode.delay => (
      startAfter: now.add(Duration(minutes: delayMinutes)),
      problem: null,
    ),
    DryStartMode.atTime when at == null => (
      startAfter: null,
      problem: DryingStartProblem.noTimePicked,
    ),
    DryStartMode.atTime when !at!.isAfter(now) => (
      startAfter: null,
      problem: DryingStartProblem.timeInPast,
    ),
    DryStartMode.atTime => (startAfter: at, problem: null),
  };
}
