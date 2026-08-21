/// The app's calendar-date spelling, `YYYY-MM-DD`.
///
/// Deliberately not locale-formatted: these read as sortable stamps next to
/// file names and queue entries, where a locale-shuffled order confuses more
/// than it helps. Pass a local [DateTime] — `dateTimeFromJson` has already
/// converted server time by the point any screen sees it.
String formatDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// [formatDate] plus `HH:MM`.
String formatDateTime(DateTime d) =>
    '${formatDate(d)} ${_two(d.hour)}:${_two(d.minute)}';

String _two(int n) => n.toString().padLeft(2, '0');
