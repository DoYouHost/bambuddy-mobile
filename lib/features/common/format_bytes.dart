/// Human-readable byte size (binary units), e.g. `12.3 MB` / `834 KB`.
/// The decimal survives only below 100 in the chosen unit: on a three-digit
/// result it is noise, but between 10 and 99 it is what tells two similar
/// files apart.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var size = bytes / 1024;
  var i = 0;
  while (size >= 1024 && i < units.length - 1) {
    size /= 1024;
    i++;
  }
  return '${size.toStringAsFixed(size >= 100 ? 0 : 1)} ${units[i]}';
}
