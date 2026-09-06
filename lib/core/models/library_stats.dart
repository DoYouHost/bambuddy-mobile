/// Library statistics from `GET /library/stats`.
///
/// Endpoint has no fixed schema in OpenAPI (returns raw object), so read
/// defensively from several candidate key names and tolerate missing fields
/// — stats header is decorative anyway.
class LibraryStats {
  const LibraryStats({
    this.totalFiles,
    this.totalFolders,
    this.totalSizeBytes,
    this.freeBytes,
  });

  factory LibraryStats.fromJson(Map<String, dynamic> json) {
    int? pick(List<String> keys) {
      for (final k in keys) {
        final v = json[k];
        if (v is int) return v;
        if (v is num) return v.toInt();
      }
      return null;
    }

    return LibraryStats(
      totalFiles: pick(['total_files', 'file_count', 'files']),
      totalFolders: pick(['total_folders', 'folder_count', 'folders']),
      totalSizeBytes: pick([
        'total_size',
        'total_size_bytes',
        'size_bytes',
        'size',
      ]),
      freeBytes: pick([
        'free_bytes',
        'free_space',
        'free_space_bytes',
        'disk_free',
        'disk_free_bytes',
        'free',
      ]),
    );
  }

  final int? totalFiles;
  final int? totalFolders;
  final int? totalSizeBytes;
  final int? freeBytes;
}
