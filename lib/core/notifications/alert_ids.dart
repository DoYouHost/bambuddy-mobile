/// Room reserved per event type. The offsets added to a base are server row ids
/// (a printer, a maintenance task, an archive), which grow without bound and
/// are never reused after a delete — so the band has to be wide enough that no
/// realistic install reaches the next event type's numbers and starts replacing
/// its notifications.
const int alertBandWidth = 1000000;
