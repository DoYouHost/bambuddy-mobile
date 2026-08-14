/// `m:ss`, growing to `h:mm:ss` only for the rare long recording — a fixed
/// `h:mm:ss` would put a leading `0:` on every clip.
///
/// Seconds are truncated, not rounded, so a playing position never shows a
/// second the video has not reached and a trim never claims a frame it did
/// not keep.
String formatClock(num seconds) {
  final d = Duration(seconds: seconds.floor());
  final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (d.inHours == 0) return '${d.inMinutes}:$secs';
  final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  return '${d.inHours}:$mins:$secs';
}

/// `1x`, `0.25x` — trailing zeros dropped, matching the web UI's chips.
String formatSpeed(double speed) {
  final text = speed
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
  return '${text}x';
}
