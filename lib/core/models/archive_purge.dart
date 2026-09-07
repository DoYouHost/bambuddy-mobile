import 'json_utils.dart';

/// Preview of an archive purge from `GET /archives/purge/preview` —
/// count + size of prints eligible for deletion. Read-only.
///
/// Manual, defensive parsing: numeric fields accept both `int` and `double`.
class ArchivePurgePreview {
  const ArchivePurgePreview({
    this.count = 0,
    this.totalBytes = 0,
    this.sampleFilenames = const [],
    this.olderThanDays = 0,
  });

  factory ArchivePurgePreview.fromJson(Map<String, dynamic> json) =>
      ArchivePurgePreview(
        count: toInt(json['count']),
        totalBytes: toInt(json['total_bytes']),
        sampleFilenames: toStringList(json['sample_filenames']),
        olderThanDays: toInt(json['older_than_days']),
      );

  /// Number of archived prints eligible for purge.
  final int count;

  /// Total disk size of eligible prints in bytes.
  final int totalBytes;

  /// A few example filenames (server-provided sample, not exhaustive).
  final List<String> sampleFilenames;

  /// Threshold the count was computed for (echoes the request).
  final int olderThanDays;

  bool get isEmpty => count == 0;
}
