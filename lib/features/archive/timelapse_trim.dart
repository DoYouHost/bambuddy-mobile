/// How far past a boundary still counts as having reached it, in seconds.
///
/// Position updates arrive a frame or two apart, so an exact comparison can be
/// stepped straight over.
const timelapseFrameSlack = 0.1;

/// Whether playback has run to the end of the trimmed region and should loop
/// back to its start.
///
/// Deliberately says nothing about the region's start. A seek lands on a
/// frame, not on an exact millisecond, so a rule that also pulled a position
/// below [trimStart] back up would re-fire on its own undershoot: seek,
/// undershoot, seek again — the decoder flushes continuously and the picture
/// never moves. The start is corrected once, when playback is started, by
/// [timelapseNeedsRewind].
bool timelapseReachedEnd(double position, double trimEnd) =>
    position + timelapseFrameSlack >= trimEnd;

/// Whether pressing play should jump back to [trimStart] first: the position
/// is either before the region or already at its end.
bool timelapseNeedsRewind(double position, double trimStart, double trimEnd) =>
    position < trimStart || timelapseReachedEnd(position, trimEnd);
