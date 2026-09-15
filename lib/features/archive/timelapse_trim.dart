/// Slack past a boundary, in seconds: position updates arrive a frame or two
/// apart, so an exact comparison can be stepped straight over.
const timelapseFrameSlack = 0.1;

/// Says nothing about the region's start on purpose: a rule that also pulled an
/// undershooting seek back up would re-fire on its own undershoot and the
/// picture would never move. [timelapseNeedsRewind] corrects the start once.
bool timelapseReachedEnd(double position, double trimEnd) =>
    position + timelapseFrameSlack >= trimEnd;

bool timelapseNeedsRewind(double position, double trimStart, double trimEnd) =>
    position < trimStart || timelapseReachedEnd(position, trimEnd);
