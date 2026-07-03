/// Human-readable byte size (binary units), e.g. `12.3 MB` / `12 MB`.
/// Whole-number-looking results (≥10 in the chosen unit) drop the decimal —
/// "12 MB" reads cleaner than "12.0 MB".
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var size = bytes / 1024;
  var i = 0;
  while (size >= 1024 && i < units.length - 1) {
    size /= 1024;
    i++;
  }
  return '${size.toStringAsFixed(size >= 10 ? 0 : 1)} ${units[i]}';
}
