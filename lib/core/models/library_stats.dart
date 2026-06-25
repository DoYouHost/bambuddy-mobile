/// Statystyki biblioteki z `GET /library/stats`.
///
/// Endpoint nie ma ustalonego schematu w OpenAPI (zwraca surowy obiekt), więc
/// czytamy defensywnie po kilku kandydujących nazwach kluczy i tolerujemy braki
/// — nagłówek statystyk i tak jest tylko ozdobny.
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
      totalSizeBytes:
          pick(['total_size', 'total_size_bytes', 'size_bytes', 'size']),
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
